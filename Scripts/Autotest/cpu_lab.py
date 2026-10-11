"""
CPU LAB (ISSUE #375) — tests our CPU rules instead of trusting them, and looks for better choices.

A. RULE AUDIT — every tunable number (CpuWeights.g) is played at x0 and x2, and every yes/no rule (CpuWeights.on) is
   switched OFF, each on the SAME fixed seeds as the current CPU ("BASE"). Paired differences say whether a rule wins
   games, does nothing, or loses games.                                          -> lab/audit_report.txt
B. BRANCH REPLAY — a match is played normally (counting every real CPU choice), then replayed from the same seed with
   ONE choice (attack, Energy target, Trainer play/skip, retreat, bench, replacement, fetch) replaced by a random
   alternative. The result difference belongs to that choice; grouped by situation it shows where the CPU's own
   choice is beaten by an alternative (candidate new rules) and where it is clearly right.  -> lab/branch_report.txt

Both share one worker pool (no idle gaps). Crash-safe: results are appended to JSONL as they arrive; run again to resume.
  py cpu_lab.py --until "2026-10-11 08:30"      (default: 12 h)
  py cpu_lab.py --smoke                          (4-minute end-to-end test in lab_smoke/)
  create lab/STOP to stop cleanly
"""
import json
import math
import os
import random
import re
import sys
import time
from collections import deque, defaultdict
from concurrent.futures import ThreadPoolExecutor, FIRST_COMPLETED, wait
from datetime import datetime, timedelta

import cpu_tuner as T
import cpu_learner as L

SMOKE = "--smoke" in sys.argv
LAB = os.path.join(os.path.dirname(T.TUNER_DIR), "lab_smoke" if SMOKE else "lab")
WORKERS = 8 if SMOKE else 34
IN_FLIGHT = WORKERS * 2
AUDIT_SEEDS = 6 if SMOKE else 1200
AUDIT_SEED0 = 950_000_000
BRANCHES_PER_SEED = 3
AUDIT_PER_BASE = 3            # audit jobs submitted per branch base job (branch base spawns 3 more jobs)
REPORT_EVERY = 60 if SMOKE else 600
if SMOKE:
    T.JOB_MATCHES = 3

STATE = os.path.join(LAB, "state.json")
LOG = os.path.join(LAB, "lab_log.txt")
AUDIT_RES = os.path.join(LAB, "audit_results.jsonl")
BRANCH_RES = os.path.join(LAB, "branch_results.jsonl")
AUDIT_REPORT = os.path.join(LAB, "audit_report.txt")
BRANCH_REPORT = os.path.join(LAB, "branch_report.txt")
STOP = os.path.join(LAB, "STOP")
PIDFILE = os.path.join(LAB, "lab.pid")
WEIGHTS_SNAP = os.path.join(LAB, "champion_weights.json")
LEARNED_SNAP = os.path.join(LAB, "learned_snapshot.json")
PLANS = os.path.join(LAB, "plans")
LEARN_HOME = LAB if SMOKE else T.TUNER_DIR      # smoke never touches the real learning files
COUNTER_STATS = os.path.join(LEARN_HOME, "counter_stats.json")
COUNTERS = os.path.join(LEARN_HOME, "counters.json")
if SMOKE:
    T.SYN_STATS, T.SYNERGY, T.SYN_REPORT = [os.path.join(LAB, f) for f in ("synergy_stats.json", "synergy.json", "synergy_report.txt")]
    T.LEARN_STATE, T.LEARNED, T.LEARN_REPORT = [os.path.join(LAB, f) for f in ("learned_model_state.json", "learned.json", "learned_report.txt")]
    T.SYN_MIN_DECK, T.SYN_MIN_PAIR, L.MIN_SEEN, L.COUNTER_MIN_PAIR = 1, 1, 1, 1
COUNTER_REPORT = os.path.join(LAB, "counter_report.txt")

T.WORK = os.path.join(LAB, "work")
T.LOG = LOG


def log(msg):
    T.log(msg)


def rule_keys():
    src = open(T.CPU_AI, encoding="utf-8").read()
    return sorted(set(re.findall(r'CpuWeights\.on\("([^"]+)"', src)))


def audit_items(champ):
    keys = T.tunable_keys()
    rules = rule_keys()
    if SMOKE:
        keys, rules = keys[:2], rules[:2]
    items = [("BASE", champ)]
    for k in keys:
        items.append((k + " x0", {**champ, k: 0.0}))
        items.append((k + " x2", {**champ, k: round(champ.get(k, 1.0) * 2.0, 4)}))
    for r in rules:
        items.append((r + " OFF", {**champ, r: 0.0}))
    return items


def score_of(rec):
    return round(T.match_score(rec), 4), 1 if rec.get("result") == "loss" else 0


# ───────────────────────── reports ─────────────────────────

def paired_stats(d):
    n = len(d)
    if n < 10:
        return n, 0.0, 0.0
    mean = sum(d) / n
    var = sum((x - mean) ** 2 for x in d) / (n - 1)
    se = math.sqrt(var / n) if var > 0 else 0.0
    return n, mean, (mean / se if se > 0 else 0.0)


def write_audit_report():
    per = defaultdict(dict)
    if os.path.exists(AUDIT_RES):
        for line in open(AUDIT_RES, encoding="utf-8"):
            try:
                r = json.loads(line)
            except Exception:
                continue
            per[r["item"]].update(r["recs"])
    base = per.get("BASE", {})
    rows = []
    for item, recs in per.items():
        if item == "BASE":
            continue
        common = [s for s in recs if s in base]
        n, mean, z = paired_stats([recs[s][0] - base[s][0] for s in common])
        wr = sum(recs[s][1] for s in common) / max(1, len(common))
        bwr = sum(base[s][1] for s in common) / max(1, len(common))
        rows.append((z, mean, n, item, wr, bwr))
    def verdict(item, z):
        if abs(z) < 2:
            return "no measurable effect"
        if item.endswith(" x2"):
            return "STRONGER IS BETTER" if z > 0 else "stronger is worse (current value fine or too high)"
        return ("REMOVING IT WINS MORE — rule may be HURTING" if z > 0 else "rule HELPS (removing it loses games)")
    rows.sort(key=lambda r: r[0])
    lines = ["CPU RULE AUDIT (updated %s) — each variant vs the current CPU (BASE) on the same %d fixed seeds" % (T.now(), AUDIT_SEEDS),
             "mean = paired score change (win = 1, + 0.04 per Prize of margin); z >= 2 or <= -2 = real effect.", "",
             "%-44s %8s %7s %6s  %-6s %s" % ("variant", "mean", "z", "games", "win%", "verdict")]
    for z, mean, n, item, wr, bwr in rows:
        lines.append("%-44s %+8.4f %+7.2f %6d  %5.1f%% %s" % (item, mean, z, n, wr * 100, verdict(item, z)))
    lines += ["", "BASE win rate on these seeds: %.1f%% over %d games" % (100 * sum(v[1] for v in base.values()) / max(1, len(base)), len(base))]
    T.atomic_write_text(AUDIT_REPORT, "\n".join(lines) + "\n")


def branch_move(r):
    k, lab = r["kind"], r.get("labels", [])
    alt = lab[r["alt"]] if r["alt"] < len(lab) else "?"
    ch = lab[r["chosen"]] if r["chosen"] < len(lab) else "?"
    if k == "energy":
        return "skip the attach" if alt == "no attach" else "attach elsewhere"
    if k == "trainer":
        return ("skip (instead of %s)" % ch) if alt == "none" else ("play %s" % alt)
    if k in ("retreat", "bench"):
        return alt
    return "other choice"


def write_branch_report():
    recs = []
    if os.path.exists(BRANCH_RES):
        for line in open(BRANCH_RES, encoding="utf-8"):
            try:
                recs.append(json.loads(line))
            except Exception:
                pass
    by = defaultdict(list)
    for r in recs:
        mv = branch_move(r)
        ctx = r.get("ctx", {})
        d = r["delta"]
        by[(r["kind"], "ANY")].append(d)
        by[(r["kind"], mv)].append(d)
        st = "ahead" if ctx.get("ahead", 0) > 0 else ("behind" if ctx.get("ahead", 0) < 0 else "even")
        conds = ["when " + x for x in ctx.get("rel", [])] + ["when " + st, "turn " + ("<=6" if ctx.get("turn", 0) <= 6 else ">6")]
        for c in conds:
            by[(r["kind"], mv + " | " + c)].append(d)
    rows = []
    for (kind, label), d in by.items():
        n, mean, z = paired_stats(d)
        if n >= (5 if SMOKE else 40):
            rows.append((z, mean, n, kind, label))
    lines = ["CPU BRANCH REPLAY (updated %s) — %s branched games" % (T.now(), f"{len(recs):,}"),
             "Each = the same match replayed with ONE CPU choice swapped for a random alternative.",
             "mean = alternative minus the CPU's own choice (negative = the CPU chose better).", "",
             "OVERALL by decision type:"]
    for z, mean, n, kind, label in sorted([r for r in rows if r[4] == "ANY"], key=lambda r: r[0]):
        lines.append("  %-9s %+.4f  z %+6.2f  (%d)" % (kind, mean, z, n))
    lines += ["", "WHERE THE ALTERNATIVE BEATS THE CPU (candidate new rules, z >= 2):"]
    good = sorted([r for r in rows if r[4] != "ANY" and r[0] >= 2], key=lambda r: -r[0])
    lines += ["  %-9s %-60s %+.4f  z %+5.2f  (%d)" % (k, l[:60], m, z, n) for z, m, n, k, l in good[:60]] or ["  (none yet)"]
    lines += ["", "WHERE THE CPU IS CLEARLY RIGHT (alternative loses, z <= -3):"]
    bad = sorted([r for r in rows if r[4] != "ANY" and r[0] <= -3], key=lambda r: r[0])
    lines += ["  %-9s %-60s %+.4f  z %+5.2f  (%d)" % (k, l[:60], m, z, n) for z, m, n, k, l in bad[:40]] or ["  (none yet)"]
    T.atomic_write_text(BRANCH_REPORT, "\n".join(lines) + "\n")


# ───────────────────────── main loop ─────────────────────────

def main():
    os.makedirs(T.WORK, exist_ok=True)
    os.makedirs(PLANS, exist_ok=True)
    if os.path.exists(PIDFILE):
        try:
            old = int(open(PIDFILE).read().strip())
            if old != os.getpid() and T.pid_alive(old):
                print("Lab already running (pid %d)." % old)
                return
        except Exception:
            pass
    open(PIDFILE, "w").write(str(os.getpid()))
    args = sys.argv[1:]
    st = {}
    if os.path.exists(STATE):
        try:
            st = json.load(open(STATE, encoding="utf-8"))
        except Exception:
            st = {}
    if not st:
        hours = 0.07 if SMOKE else 12.0
        st = {"started": T.now(), "deadline_ts": time.time() + hours * 3600, "branch_seed": 600_000_000, "games": 0}
        champ = {k: float(v) for k, v in json.load(open(T.BEST, encoding="utf-8")).items() if not k.startswith("_")} if os.path.exists(T.BEST) else {}
        T.atomic_write_json(WEIGHTS_SNAP, champ)
        if os.path.exists(T.LEARNED):
            T.atomic_write_text(LEARNED_SNAP, open(T.LEARNED, encoding="utf-8").read())
        log("NEW LAB RUN. Champion weights + learned matchups snapshotted.")
    if "--until" in args:
        st["deadline_ts"] = datetime.strptime(args[args.index("--until") + 1], "%Y-%m-%d %H:%M").timestamp()
    T.atomic_write_json(STATE, st)
    champ = json.load(open(WEIGHTS_SNAP, encoding="utf-8"))
    learned = LEARNED_SNAP if os.path.exists(LEARNED_SNAP) else None
    if os.path.exists(STOP):
        os.remove(STOP)
    if not SMOKE:
        T.kill_orphans()
    T.keep_awake(True)

    items = audit_items(champ)
    # Every lab game also feeds the learners: synergy, counters (card vs card, trait vs player style) and matchups.
    feat_cards, feat_attacks = L.extract_features(T.CARD_DIR)
    names = L.card_names(T.CARD_DIR)
    model = L.Model(T.LEARN_STATE)
    counters = L.Counters(COUNTER_STATS)
    syn_stats = T.load_syn_stats()

    def learn(recs):
        recs = [r for r in recs if isinstance(r, dict)]
        T.add_syn_stats(syn_stats, recs)
        counters.add(recs, feat_cards)
        model.train([ex for r in recs for ex in r.get("ex", [])], feat_cards, feat_attacks)

    def export_learning():
        T.atomic_write_json(T.SYN_STATS, syn_stats)
        table = T.build_synergy(syn_stats)
        if table:
            T.atomic_write_json(T.SYNERGY, table)
            T.write_syn_report(table, syn_stats)
        counters.save()
        ct = counters.export(COUNTERS, feat_cards)
        counters.report(COUNTER_REPORT, ct, names, T.now())
        model.save()
        model.export(T.LEARNED, feat_cards, feat_attacks)
        model.report(T.LEARN_REPORT, T.now())
    done = set()
    if os.path.exists(AUDIT_RES):
        for line in open(AUDIT_RES, encoding="utf-8"):
            try:
                r = json.loads(line)
                done.add((r["item"], r["start"]))
            except Exception:
                pass
    audit_q = deque((name, w, s) for s in range(AUDIT_SEED0, AUDIT_SEED0 + AUDIT_SEEDS, T.JOB_MATCHES)
                    for name, w in items if (name, s) not in done)
    log("LAB: %d audit variants (%d chunks left of %d), %d workers, until %s." % (
        len(items), len(audit_q), len(items) * math.ceil(AUDIT_SEEDS / T.JOB_MATCHES), WORKERS,
        datetime.fromtimestamp(st["deadline_ts"]).strftime("%Y-%m-%d %H:%M")))

    follow = deque()        # branch replays waiting to be submitted (they go first)
    pending = {}
    rng = random.Random(int(time.time()))
    turn = 0
    last_report = 0.0

    def next_job():
        nonlocal turn
        if follow:
            return follow.popleft()
        turn += 1
        if audit_q and turn % (AUDIT_PER_BASE + 1) != 0:
            name, w, s = audit_q.popleft()
            return ("audit", (name, s), (w, s, min(T.JOB_MATCHES, AUDIT_SEED0 + AUDIT_SEEDS - s), None, 0.0, learned, None, None))
        s = st["branch_seed"]
        st["branch_seed"] += T.JOB_MATCHES
        T.atomic_write_json(STATE, st)
        return ("base", s, (champ, s, T.JOB_MATCHES, None, 0.0, learned, None, None))

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        while time.time() < st["deadline_ts"] and not os.path.exists(STOP):
            while len(pending) < IN_FLIGHT:
                kind, meta, a = next_job()
                pending[pool.submit(T.run_job, *a)] = (kind, meta)
            fin, _ = wait(list(pending), timeout=30, return_when=FIRST_COMPLETED)
            for f in fin:
                kind, meta = pending.pop(f)
                try:
                    res = f.result()
                except Exception as e:
                    log("job failed: %r" % e)
                    continue
                st["games"] += len(res)
                learn(list(res.values()))
                if kind == "audit":
                    name, s = meta
                    T.append_jsonl(AUDIT_RES, {"item": name, "start": s, "recs": {str(k): score_of(v) for k, v in res.items()}})
                elif kind == "base":
                    base = {k: v for k, v in res.items() if int(v.get("dp", 0)) >= 2}
                    for b in range(BRANCHES_PER_SEED):
                        plan = {str(k): rng.randint(1, int(v["dp"])) for k, v in base.items()}
                        if not plan:
                            continue
                        pf = os.path.join(PLANS, "p_%d_%d.json" % (meta, b))
                        T.atomic_write_json(pf, plan)
                        follow.append(("branch", (meta, {str(k): score_of(v)[0] for k, v in base.items()}, pf),
                                       (champ, meta, T.JOB_MATCHES, None, 0.0, learned, None, ["--branch-plan=" + pf])))
                elif kind == "branch":
                    s0, base_scores, pf = meta
                    for k, v in res.items():
                        br = v.get("branch") or {}
                        if not br or str(k) not in base_scores:
                            continue
                        T.append_jsonl(BRANCH_RES, {"seed": k, "kind": br.get("kind"), "chosen": br.get("chosen"), "alt": br.get("alt"),
                                                    "labels": br.get("labels", []), "ctx": br.get("ctx", {}),
                                                    "delta": round(score_of(v)[0] - base_scores[str(k)], 4)})
                    try:
                        os.remove(pf)
                    except OSError:
                        pass
            if time.time() - last_report >= REPORT_EVERY:
                last_report = time.time()
                T.atomic_write_json(STATE, st)
                write_audit_report()
                write_branch_report()
                export_learning()
                log("LAB: %s games; audit chunks left %d; branch records %s." % (
                    f"{st['games']:,}", len(audit_q), f"{sum(1 for _ in open(BRANCH_RES, encoding='utf-8')) if os.path.exists(BRANCH_RES) else 0:,}"))
        T.atomic_write_json(STATE, st)
        write_audit_report()
        write_branch_report()
        export_learning()
        log("LAB: %s — final reports written." % ("STOP file found" if os.path.exists(STOP) else "deadline reached"))
    T.keep_awake(False)
    try:
        os.remove(PIDFILE)
    except OSError:
        pass


if __name__ == "__main__":
    for attempt in range(50):
        try:
            main()
            break
        except KeyboardInterrupt:
            break
        except Exception as e:
            import traceback
            os.makedirs(LAB, exist_ok=True)
            log("CRASH: %r — restarting in 30 s (attempt %d)\n%s" % (e, attempt + 1, traceback.format_exc()))
            time.sleep(30)
