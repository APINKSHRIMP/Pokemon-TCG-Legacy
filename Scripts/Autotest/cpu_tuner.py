"""
CPU self-play weight tuner (ISSUE #375).

Plays the CPU (real opponents' decks and rules) against the smart bot thousands of times, nudging the tunable
numbers in CPU_AI.gd (every CpuWeights.g("key", default) call) and keeping a change only when it wins measurably
more on the SAME seeds as the current best (paired comparison: same decks, same shuffles, so luck mostly cancels).

Crash-safe: everything it knows lives in TUNER_DIR (state.json written atomically after every step). Kill it, close
the window, lose power — run it again (or let the Startup entry do it) and it carries on from the last generation.

  py cpu_tuner.py                 start a new run (12 h), or resume the current one
  py cpu_tuner.py --hours 8       new run length (only when starting a new run)
  py cpu_tuner.py --until "2026-10-10 09:00"   set the run's deadline (works on a new or resumed run)
  py cpu_tuner.py --resume        resume only if a run is active and before its deadline (used by the Startup entry)
  py cpu_tuner.py --new           discard the current run's state and start again from the shipped weights
  create TUNER_DIR/STOP           finish the current step and exit cleanly

Outputs in TUNER_DIR:
  report.txt          human summary — best weights vs the original game, every accepted change, progress
  best_weights.json   the current champion multipliers (copy to res://NPC_and_Opponent_Data/CPU_Weights.json to ship)
  history.jsonl       every candidate tried and how it scored
  tuner_log.txt       timestamped log
"""
import ctypes
import cpu_learner
import json
import math
import os
import random
import re
import subprocess
import sys
import time
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta

PROJECT = r"C:\Pokemon TCG Legacy"
GODOT = r"C:\Godot\Godot_v4.6.1-stable_win64_console.exe"
CPU_AI = os.path.join(PROJECT, "Scripts", "Main_Match_Gameplay_Scripts", "CPU_AI.gd")
SHIPPED = os.path.join(PROJECT, "NPC_and_Opponent_Data", "CPU_Weights.json")
TUNER_DIR = os.path.join(os.environ["APPDATA"], "Godot", "app_userdata", "Pokemon_TCG_Legacy", "autotest", "tuner")
WORK = os.path.join(TUNER_DIR, "work")

WORKERS = 30                 # parallel Godot processes (i9-13900HX: 24 cores / 32 threads, 64 GB — "full pelt")
JOB_MATCHES = 30             # matches per Godot process (≈5 s start-up each)
CANDIDATES_PER_GEN = 4       # candidates screened together against one shared baseline
SCREEN_SEEDS = 240           # seeds per screening (paired)
CONFIRM_SEEDS = 480          # extra fresh seeds to confirm the best screened candidate
SCREEN_Z = 1.0               # screening pass mark (paired z-score)
ACCEPT_Z = 2.5               # combined z needed to accept (strict: hundreds of candidates are tried)
CONFIRM_Z = 1.0              # the confirmation seeds alone must agree too
BENCH_SEEDS = 960            # fixed benchmark: champion vs the ORIGINAL weights
BENCH_SEED_BASE = 900_000_000
BENCH_EVERY_ACCEPTS = 3
BENCH_EVERY_HOURS = 2.0
JOB_TIMEOUT = 25 * 60        # seconds before a hung Godot job is killed (its matches are dropped from both sides)
MULT_MIN, MULT_MAX = 0.1, 5.0
SIGMA = 0.45                 # log-normal step size for a nudge
EXPLORE_SEEDS = 300          # per generation: champion games with random free fetch choices (synergy data only)
EXPLORE_RATE = 0.25          # chance each free "fetch a card" choice is random in those games
SYN_REBUILD_EVERY = 4        # generations between synergy-table rebuilds (only ever between generations)
SYN_MIN_PAIR = 40            # games a pair must appear in (per deck) before it counts
SYN_SHRINK = 150.0           # shrinkage: a pair seen n times keeps n / (n + SYN_SHRINK) of its measured lift
SYN_CAP = 30.0               # max points either way per pair
SYN_MIN_DECK = 100           # games a deck needs before its pairs are used
FILLERS = 16                 # extra exploration workers at IDLE priority: they only use CPU the main jobs leave free
LEARN_EXPORT_EVERY = 3       # generations between learned-matchup exports

STATE = os.path.join(TUNER_DIR, "state.json")
LOG = os.path.join(TUNER_DIR, "tuner_log.txt")
HISTORY = os.path.join(TUNER_DIR, "history.jsonl")
REPORT = os.path.join(TUNER_DIR, "report.txt")
BEST = os.path.join(TUNER_DIR, "best_weights.json")
STOP = os.path.join(TUNER_DIR, "STOP")
PIDFILE = os.path.join(TUNER_DIR, "tuner.pid")
SYN_STATS = os.path.join(TUNER_DIR, "synergy_stats.json")
SYNERGY = os.path.join(TUNER_DIR, "synergy.json")
SYN_REPORT = os.path.join(TUNER_DIR, "synergy_report.txt")
LEARN_STATE = os.path.join(TUNER_DIR, "learned_model_state.json")
LEARNED = os.path.join(TUNER_DIR, "learned.json")
LEARN_REPORT = os.path.join(TUNER_DIR, "learned_report.txt")
CARD_DIR = os.path.join(PROJECT, "Card_Set_Data")
IDLE = 0x00000040

CREATE_NO_WINDOW = 0x08000000
BELOW_NORMAL = 0x00004000


# ───────────────────────── small helpers ─────────────────────────

def now():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def log(msg):
    line = f"[{now()}] {msg}"
    print(line, flush=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")
        f.flush()
        os.fsync(f.fileno())


def atomic_write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def atomic_write_text(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def append_jsonl(path, obj):
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(obj, sort_keys=True) + "\n")
        f.flush()
        os.fsync(f.fileno())


def keep_awake(on=True):
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED — stops Windows idling into sleep while the tuner runs (lid-close may still).
    try:
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | (0x00000001 if on else 0))
    except Exception:
        pass


def pid_alive(pid):
    try:
        out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"], capture_output=True, text=True,
                             creationflags=CREATE_NO_WINDOW).stdout
        low = out.lower()
        return str(pid) in out and ("python" in low or "py.exe" in low)
    except Exception:
        return False


def kill_orphans():
    """Godot --tune jobs left behind by a previous tuner process that died (not after a reboot — nothing survives that)."""
    ps = ("Get-CimInstance Win32_Process -Filter \"Name='Godot_v4.6.1-stable_win64_console.exe'\" | "
          "Where-Object { $_.CommandLine -like '*--tune*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }")
    try:
        subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, timeout=60,
                       creationflags=CREATE_NO_WINDOW)
    except Exception:
        pass


def tunable_keys():
    src = open(CPU_AI, encoding="utf-8").read()
    return sorted(set(re.findall(r'CpuWeights\.g\("([^"]+)"', src)))


def load_shipped():
    try:
        d = json.load(open(SHIPPED, encoding="utf-8"))
        return {k: float(v) for k, v in d.items() if not k.startswith("_")}
    except Exception:
        return {}


# ───────────────────────── running matches ─────────────────────────

def run_job(weights, seed_start, n, synergy=None, explore=0.0, learned=None, priority=None):
    """One Godot process: n matches from seed_start with these multipliers. Returns {seed: record}."""
    tag = uuid.uuid4().hex[:10]
    wpath = os.path.join(WORK, f"w_{tag}.json")
    rpath = os.path.join(WORK, f"r_{tag}.jsonl")
    with open(wpath, "w", encoding="utf-8") as f:
        json.dump(weights, f)
    cmd = [GODOT, "--headless", "--fixed-fps", "60", "--path", PROJECT, "res://Scenes/Autotest/Autotest_Runner.tscn",
           "--", "--tune", f"--matches={n}", f"--seed={seed_start}", f"--worker={tag}",
           f"--weights={wpath}", f"--result={rpath}"]
    if synergy:
        cmd.append(f"--synergy={synergy}")
    if explore > 0:
        cmd.append(f"--explore={explore}")
    if learned:
        cmd.append(f"--learned={learned}")
    out = {}
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                             creationflags=CREATE_NO_WINDOW | (priority or BELOW_NORMAL), cwd=PROJECT)
        try:
            p.wait(timeout=JOB_TIMEOUT)
        except subprocess.TimeoutExpired:
            p.kill()
            log(f"job {tag} (seeds {seed_start}+{n}) timed out — killed; its finished matches are kept")
        if os.path.exists(rpath):
            for line in open(rpath, encoding="utf-8"):
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if "seed" in rec:
                    out[int(rec["seed"])] = rec
    finally:
        for pth in (wpath, rpath):
            try:
                os.remove(pth)
            except OSError:
                pass
        wdir = os.path.join(WORK, "w" + tag)
        if os.path.isdir(wdir):
            for fn in os.listdir(wdir):
                try:
                    os.remove(os.path.join(wdir, fn))
                except OSError:
                    pass
            try:
                os.rmdir(wdir)
            except OSError:
                pass
    return out


def evaluate(pool, weight_sets, seed_start, n_seeds, synergy=None, learned=None):
    """Run every weight set on the same seeds, in parallel. Returns a list of {seed: record} per set."""
    jobs = []
    for wi, w in enumerate(weight_sets):
        for s in range(seed_start, seed_start + n_seeds, JOB_MATCHES):
            jobs.append((wi, w, s, min(JOB_MATCHES, seed_start + n_seeds - s)))
    random.shuffle(jobs)
    futures = [(wi, pool.submit(run_job, w, s, n, synergy, 0.0, learned)) for wi, w, s, n in jobs]
    results = [dict() for _ in weight_sets]
    for wi, fut in futures:
        try:
            results[wi].update(fut.result())
        except Exception as e:
            log(f"job failed: {e!r}")
    return results


def match_score(rec):
    """CPU's view: a win is 1, a loss 0, draws/aborts ½ — plus a little for the Prize margin."""
    r = rec.get("result", "")
    base = 1.0 if r == "loss" else (0.0 if r == "win" else 0.5)   # 'loss' = the BOT lost = the CPU won
    cp, bp = rec.get("cpu_prizes_left", -1), rec.get("bot_prizes_left", -1)
    margin = 0.04 * (bp - cp) if cp >= 0 and bp >= 0 else 0.0
    return base + margin


def paired(cand, base):
    seeds = sorted(set(cand) & set(base))
    d = [match_score(cand[s]) - match_score(base[s]) for s in seeds]
    n = len(d)
    if n < 10:
        return {"n": n, "mean": 0.0, "z": 0.0, "sum": 0.0, "sumsq": 0.0, "wins_c": 0, "wins_b": 0, "changed": 0}
    mean = sum(d) / n
    var = sum((x - mean) ** 2 for x in d) / (n - 1)
    se = math.sqrt(var / n) if var > 0 else 0.0
    z = mean / se if se > 0 else (0.0 if mean == 0 else math.copysign(9.9, mean))
    return {"n": n, "mean": mean, "z": z, "sum": sum(d), "sumsq": sum(x * x for x in d),
            "wins_c": sum(1 for s in seeds if cand[s].get("result") == "loss"),
            "wins_b": sum(1 for s in seeds if base[s].get("result") == "loss"),
            "changed": sum(1 for x in d if x != 0)}


def combine(a, b):
    n = a["n"] + b["n"]
    if n < 10:
        return {"n": n, "mean": 0.0, "z": 0.0}
    s, ss = a["sum"] + b["sum"], a["sumsq"] + b["sumsq"]
    mean = s / n
    var = max(0.0, (ss - n * mean * mean) / (n - 1))
    se = math.sqrt(var / n) if var > 0 else 0.0
    z = mean / se if se > 0 else 0.0
    return {"n": n, "mean": mean, "z": z}


def winrate(res):
    if not res:
        return 0.0
    return sum(1 for r in res.values() if r.get("result") == "loss") / len(res)


# ───────────────────────── learned synergy ─────────────────────────
# Per real opponent deck: how often each card / pair of cards reached play, and how often the CPU then won.
# lift(A,B) = winrate(A and B both played) - base - [(winrate(A) - base) + (winrate(B) - base)] / 2
# i.e. what the PAIR adds beyond each card on its own. Shrunk toward 0 for small samples, averaged over decks.

def load_syn_stats():
    try:
        return json.load(open(SYN_STATS, encoding="utf-8"))
    except Exception:
        return {}


def add_syn_stats(stats, records):
    for rec in records:
        deck = rec.get("opponent", "")
        cards = sorted(set(rec.get("cpu_cards", [])))
        if not deck or not cards or rec.get("result") not in ("win", "loss"):
            continue
        won = 1 if rec["result"] == "loss" else 0
        d = stats.setdefault(deck, {"n": 0, "w": 0, "s": {}, "p": {}})
        d["n"] += 1
        d["w"] += won
        for i, a in enumerate(cards):
            s = d["s"].setdefault(a, [0, 0])
            s[0] += 1
            s[1] += won
            for b in cards[i + 1:]:
                pr = d["p"].setdefault(a + "|" + b, [0, 0])
                pr[0] += 1
                pr[1] += won


def build_synergy(stats):
    acc = {}   # "a|b" -> [sum(lift * n), sum(n)]
    for deck, d in stats.items():
        if d["n"] < SYN_MIN_DECK:
            continue
        base = d["w"] / d["n"]
        for key, (n_ab, w_ab) in d["p"].items():
            if n_ab < SYN_MIN_PAIR or n_ab > d["n"] - SYN_MIN_PAIR:
                continue   # too rare, or (nearly) always together: no contrast to learn from
            a, b = key.split("|")
            na, wa = d["s"][a]
            nb, wb = d["s"][b]
            lift = (w_ab / n_ab - base) - ((wa / na - base) + (wb / nb - base)) / 2.0
            lift *= n_ab / (n_ab + SYN_SHRINK)
            cur = acc.setdefault(key, [0.0, 0])
            cur[0] += lift * n_ab
            cur[1] += n_ab
    table = {}
    for key, (s, n) in acc.items():
        pts = max(-SYN_CAP, min(SYN_CAP, 100.0 * s / n))
        if abs(pts) < 1.0:
            continue
        a, b = key.split("|")
        table.setdefault(a, {})[b] = round(pts, 1)
        table.setdefault(b, {})[a] = round(pts, 1)
    return table


def write_syn_report(table, stats):
    names = {}
    pairs = []
    for a, row in table.items():
        for b, v in row.items():
            if a < b:
                pairs.append((v, a, b))
    pairs.sort(reverse=True)
    games = sum(d["n"] for d in stats.values())
    lines = ["LEARNED CARD SYNERGY (updated %s) — from %s self-play games over %d decks" % (now(), f"{games:,}", len(stats)),
             "Points = extra CPU win %% when both cards reach play, beyond each card alone (shrunk for small samples).",
             "", "BEST PAIRS:"]
    lines += ["  %+5.1f  %s + %s" % p for p in pairs[:60]]
    lines += ["", "WORST PAIRS (anti-synergy):"]
    lines += ["  %+5.1f  %s + %s" % p for p in pairs[-40:][::-1]]
    atomic_write_text(SYN_REPORT, "\n".join(lines) + "\n")


# ───────────────────────── the tuner ─────────────────────────

def propose(champ, keys, st):
    cand = dict(champ)
    k = random.choice([1, 1, 2, 2, 3])
    # mild preference for keys that have produced accepted changes before
    weights = [1.0 + 2.0 * st["key_accepts"].get(key, 0) for key in keys]
    chosen = set()
    while len(chosen) < k:
        chosen.add(random.choices(keys, weights)[0])
    changes = {}
    for key in chosen:
        old = cand.get(key, 1.0)
        new = old * math.exp(random.gauss(0.0, SIGMA))
        if random.random() < 0.15:
            new = old * random.choice([0.5, 2.0])   # an occasional bold jump
        new = round(min(MULT_MAX, max(MULT_MIN, new)), 3)
        if abs(new - old) < 0.02:
            new = round(min(MULT_MAX, max(MULT_MIN, old * (1.3 if random.random() < 0.5 else 0.77))), 3)
        cand[key] = new
        changes[key] = [old, new]
    return cand, changes


def take_seeds(st, n):
    s = st["next_seed"]
    st["next_seed"] += n
    atomic_write_json(STATE, st)   # seeds are never reused, even across a crash
    return s


def write_report(st, keys):
    el = (time.time() - st["started_ts"]) / 3600.0
    lines = [
        "CPU SELF-PLAY TUNER — report (updated %s)" % now(),
        "",
        "Run started %s, ends %s.  %.1f h elapsed.  %s matches played.  %d generations, %d candidates tried, %d accepted."
        % (st["started"], st["deadline"], el, f"{st['matches']:,}", st["generation"], st["candidates"], len(st["accepted"])),
        "Opponent: the smart bot playing the player's decks; CPU plays every real opponent (decks, Prize counts, match rules).",
        "",
    ]
    b = st.get("last_bench")
    if b:
        lines += [
            "BENCHMARK (%s, %d fixed seeds): champion %.1f%% CPU wins vs ORIGINAL weights %.1f%%  — paired diff %+.4f, z %.2f"
            % (b["time"], b["n"], b["champ_wr"] * 100, b["orig_wr"] * 100, b["mean"], b["z"]), ""]
    else:
        lines += ["BENCHMARK: none yet (runs after %d accepted changes or every %.0f h)" % (BENCH_EVERY_ACCEPTS, BENCH_EVERY_HOURS), ""]
    lines.append("CHAMPION MULTIPLIERS (1.0 = original value in CPU_AI.gd); only changed keys:")
    changed = {k: v for k, v in sorted(st["champion"].items()) if abs(v - 1.0) > 1e-9}
    if not changed:
        lines.append("  (none yet)")
    for k, v in changed.items():
        lines.append("  %-34s ×%.3f" % (k, v))
    lines += ["", "ACCEPTED CHANGES (newest last):"]
    for a in st["accepted"]:
        ch = ", ".join("%s %.2f→%.2f" % (k, o, n) for k, (o, n) in a["changes"].items())
        lines.append("  gen %d  %s  z %.2f  mean %+.4f over %d paired matches  [%s]" % (a["gen"], a["time"], a["z"], a["mean"], a["n"], ch))
    if not st["accepted"]:
        lines.append("  (none yet)")
    lines += ["", "TUNABLE KEYS (%d): %s" % (len(keys), ", ".join(keys))]
    atomic_write_text(REPORT, "\n".join(lines) + "\n")


def current_synergy():
    return SYNERGY if os.path.exists(SYNERGY) else None


def current_learned():
    return LEARNED if os.path.exists(LEARNED) else None


class Filler:
    """Exploration games on IDLE-priority workers, running continuously: Windows only gives them CPU the main
    comparison jobs leave free (the gaps while a round waits for its slowest games). Data only — never compared."""
    def __init__(self, n):
        self.lock = threading.Lock()
        self.records = []
        self.champ = {}
        self.stop = False
        self.games = 0
        self.threads = [threading.Thread(target=self.loop, daemon=True) for _ in range(n)]
        for th in self.threads:
            th.start()

    def loop(self):
        rng = random.Random()
        while not self.stop:
            try:
                res = run_job(dict(self.champ), rng.randint(1_000_000_000, 2_000_000_000), JOB_MATCHES,
                              current_synergy(), EXPLORE_RATE, current_learned(), IDLE)
                with self.lock:
                    self.records += list(res.values())
                    self.games += len(res)
            except Exception as e:
                log(f"filler job failed: {e!r}")
                time.sleep(10)

    def take(self):
        with self.lock:
            out, self.records = self.records, []
            n, self.games = self.games, 0
        return out, n


def benchmark(pool, st):
    log("BENCHMARK: champion vs the ORIGINAL weights on %d fixed seeds..." % BENCH_SEEDS)
    if not st.get("orig_bench"):
        orig = evaluate(pool, [{}], BENCH_SEED_BASE, BENCH_SEEDS, None)[0]
        st["orig_bench"] = {str(k): v for k, v in orig.items()}   # the original weights are deterministic: run once
        atomic_write_json(STATE, st)
    orig = {int(k): v for k, v in st["orig_bench"].items()}
    champ = evaluate(pool, [st["champion"]], BENCH_SEED_BASE, BENCH_SEEDS, current_synergy(), current_learned())[0]
    st["matches"] += len(champ)
    p = paired(champ, orig)
    st["last_bench"] = {"time": now(), "n": p["n"], "champ_wr": winrate(champ), "orig_wr": winrate(orig),
                        "mean": p["mean"], "z": p["z"]}
    st["bench_ts"] = time.time()
    st["accepts_at_bench"] = len(st["accepted"])
    log("BENCHMARK: champion %.1f%% vs original %.1f%% CPU wins (paired mean %+.4f, z %.2f, n %d)"
        % (winrate(champ) * 100, winrate(orig) * 100, p["mean"], p["z"], p["n"]))
    atomic_write_json(STATE, st)


def new_state(hours):
    t = datetime.now()
    champ = load_shipped()
    return {"started": t.strftime("%Y-%m-%d %H:%M"), "started_ts": time.time(),
            "deadline": (t + timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M"),
            "deadline_ts": time.time() + hours * 3600, "active": True,
            "champion": champ, "generation": 0, "candidates": 0, "matches": 0,
            "next_seed": random.randint(10_000_000, 400_000_000), "accepted": [], "key_accepts": {},
            "bench_ts": time.time(), "accepts_at_bench": 0, "last_bench": None, "orig_bench": None}


def smoke_setup():
    """--smoke: a tiny end-to-end run in a separate folder, to prove the loop works."""
    global TUNER_DIR, WORK, STATE, LOG, HISTORY, REPORT, BEST, STOP, PIDFILE
    global WORKERS, JOB_MATCHES, SCREEN_SEEDS, CONFIRM_SEEDS, BENCH_SEEDS, SCREEN_Z, ACCEPT_Z, CONFIRM_Z
    global EXPLORE_SEEDS, SYN_REBUILD_EVERY, SYN_MIN_PAIR, SYN_MIN_DECK, SYN_STATS, SYNERGY, SYN_REPORT
    EXPLORE_SEEDS, SYN_REBUILD_EVERY, SYN_MIN_PAIR, SYN_MIN_DECK = 6, 1, 1, 1
    global FILLERS, LEARN_EXPORT_EVERY, LEARN_STATE, LEARNED, LEARN_REPORT
    FILLERS, LEARN_EXPORT_EVERY = 2, 1
    cpu_learner.MIN_SEEN = 1
    TUNER_DIR = TUNER_DIR + "_smoke"
    WORK = os.path.join(TUNER_DIR, "work")
    STATE, LOG, HISTORY = [os.path.join(TUNER_DIR, f) for f in ("state.json", "tuner_log.txt", "history.jsonl")]
    REPORT, BEST, STOP, PIDFILE = [os.path.join(TUNER_DIR, f) for f in ("report.txt", "best_weights.json", "STOP", "tuner.pid")]
    SYN_STATS, SYNERGY, SYN_REPORT = [os.path.join(TUNER_DIR, f) for f in ("synergy_stats.json", "synergy.json", "synergy_report.txt")]
    LEARN_STATE, LEARNED, LEARN_REPORT = [os.path.join(TUNER_DIR, f) for f in ("learned_model_state.json", "learned.json", "learned_report.txt")]
    WORKERS, JOB_MATCHES, SCREEN_SEEDS, CONFIRM_SEEDS, BENCH_SEEDS = 8, 3, 12, 12, 12
    SCREEN_Z, ACCEPT_Z, CONFIRM_Z = -99.0, -99.0, -99.0   # accept anything: exercises every branch


def main():
    args = sys.argv[1:]
    if "--smoke" in args:
        smoke_setup()
    os.makedirs(WORK, exist_ok=True)
    hours = 12.0
    if "--hours" in args:
        hours = float(args[args.index("--hours") + 1])

    if os.path.exists(PIDFILE):
        try:
            old = int(open(PIDFILE).read().strip())
            if old != os.getpid() and pid_alive(old):
                print(f"Tuner already running (pid {old}). Exiting.")
                return
        except Exception:
            pass
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))

    st = None
    if os.path.exists(STATE) and "--new" not in args:
        try:
            st = json.load(open(STATE, encoding="utf-8"))
        except Exception:
            st = None
            if os.path.exists(STATE + ".tmp"):
                try:
                    st = json.load(open(STATE + ".tmp", encoding="utf-8"))
                except Exception:
                    st = None
    if "--resume" in args:
        if st is None or not st.get("active") or time.time() >= st.get("deadline_ts", 0):
            print("No active tuning run to resume.")
            return
    if st is None or not st.get("active") or time.time() >= st.get("deadline_ts", 0):
        if "--resume" in args:
            return
        st = new_state(hours)
        log("NEW RUN: %.1f h, until %s. Starting from %s." % (hours, st["deadline"],
            "the shipped CPU_Weights.json" if st["champion"] else "the original weights"))
        atomic_write_json(STATE, st)
    else:
        log("RESUMING run started %s (until %s): generation %d, %d accepted, %s matches so far."
            % (st["started"], st["deadline"], st["generation"], len(st["accepted"]), f"{st['matches']:,}"))

    if "--until" in args:
        # --until "YYYY-MM-DD HH:MM": move the current run's deadline (new or resumed run).
        until = datetime.strptime(args[args.index("--until") + 1], "%Y-%m-%d %H:%M")
        st["deadline"] = until.strftime("%Y-%m-%d %H:%M")
        st["deadline_ts"] = until.timestamp()
        st["active"] = True
        atomic_write_json(STATE, st)
        log("Deadline set to %s." % st["deadline"])
    if os.path.exists(STOP):
        os.remove(STOP)
    kill_orphans()
    keys = tunable_keys()
    log("%d tunable keys found in CPU_AI.gd; %d workers." % (len(keys), WORKERS))
    random.seed(st["next_seed"] ^ int(time.time()))
    keep_awake(True)
    write_report(st, keys)

    syn_stats = load_syn_stats()
    feat_cards, feat_attacks = cpu_learner.extract_features(CARD_DIR)
    model = cpu_learner.Model(LEARN_STATE)
    log("LEARNER: traits for %d Pokémon / %d attacks; model has %s exchanges so far." % (
        len(feat_cards), len(feat_attacks), f"{model.records:,}"))
    filler = Filler(FILLERS)
    filler.champ = st["champion"]
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        while time.time() < st["deadline_ts"] and not os.path.exists(STOP):
            if len(st["accepted"]) - st.get("accepts_at_bench", 0) >= BENCH_EVERY_ACCEPTS or \
                    time.time() - st.get("bench_ts", 0) >= BENCH_EVERY_HOURS * 3600:
                benchmark(pool, st)
                write_report(st, keys)
                continue

            st["generation"] += 1
            gen = st["generation"]
            champ = st["champion"]
            cands = [propose(champ, keys, st) for _ in range(CANDIDATES_PER_GEN)]
            syn = current_synergy()
            lrn = current_learned()
            filler.champ = champ
            # Exploration games run in the same pool, alongside the screening (synergy data only).
            xs = take_seeds(st, EXPLORE_SEEDS)
            xfuts = [pool.submit(run_job, champ, s, min(JOB_MATCHES, xs + EXPLORE_SEEDS - s), syn, EXPLORE_RATE, lrn)
                     for s in range(xs, xs + EXPLORE_SEEDS, JOB_MATCHES)]
            s0 = take_seeds(st, SCREEN_SEEDS)
            t0 = time.time()
            res = evaluate(pool, [champ] + [c for c, _ in cands], s0, SCREEN_SEEDS, syn, lrn)
            gen_records = [r for rs in res for r in rs.values()]
            for f in xfuts:
                try:
                    xr = f.result()
                    gen_records += list(xr.values())
                    st["matches"] += len(xr)
                except Exception as e:
                    log(f"explore job failed: {e!r}")
            base = res[0]
            st["matches"] += sum(len(r) for r in res)
            scored = []
            for (cand, changes), r in zip(cands, res[1:]):
                p = paired(r, base)
                st["candidates"] += 1
                scored.append((p, cand, changes, r))
                append_jsonl(HISTORY, {"gen": gen, "time": now(), "stage": "screen", "changes": changes,
                                       "n": p["n"], "mean": round(p["mean"], 5), "z": round(p["z"], 3),
                                       "changed_matches": p["changed"], "cand_wins": p["wins_c"], "base_wins": p["wins_b"]})
            scored.sort(key=lambda x: x[0]["z"], reverse=True)
            best_p, best_c, best_ch, _ = scored[0]
            log("gen %d screen (%.0fs, base %.1f%%): best z %.2f mean %+.4f %s"
                % (gen, time.time() - t0, winrate(base) * 100, best_p["z"], best_p["mean"],
                   {k: v[1] for k, v in best_ch.items()}))
            if best_p["z"] >= SCREEN_Z and (best_p["mean"] > 0 or SCREEN_Z < -50):
                s1 = take_seeds(st, CONFIRM_SEEDS)
                t1 = time.time()
                r2 = evaluate(pool, [champ, best_c], s1, CONFIRM_SEEDS, syn, lrn)
                st["matches"] += len(r2[0]) + len(r2[1])
                gen_records += list(r2[0].values()) + list(r2[1].values())
                p2 = paired(r2[1], r2[0])
                comb = combine(best_p, p2)
                ok = comb["z"] >= ACCEPT_Z and p2["z"] >= CONFIRM_Z and (comb["mean"] > 0 or ACCEPT_Z < -50)
                append_jsonl(HISTORY, {"gen": gen, "time": now(), "stage": "confirm", "changes": best_ch,
                                       "n": p2["n"], "mean": round(p2["mean"], 5), "z": round(p2["z"], 3),
                                       "combined_z": round(comb["z"], 3), "accepted": ok})
                log("gen %d confirm (%.0fs): z %.2f, combined z %.2f over %d -> %s"
                    % (gen, time.time() - t1, p2["z"], comb["z"], comb["n"], "ACCEPTED" if ok else "rejected"))
                if ok:
                    st["champion"] = best_c
                    st["accepted"].append({"gen": gen, "time": now(), "changes": best_ch, "z": round(comb["z"], 3),
                                           "mean": round(comb["mean"], 5), "n": comb["n"]})
                    for k in best_ch:
                        st["key_accepts"][k] = st["key_accepts"].get(k, 0) + 1
                    atomic_write_json(BEST, {"_note": "CPU weight multipliers from the self-play tuner (1.0 = original). "
                                                      "Copy to res://NPC_and_Opponent_Data/CPU_Weights.json to ship.",
                                             **best_c})
            frecs, fgames = filler.take()
            gen_records += frecs
            st["matches"] += fgames
            st["filler_games"] = st.get("filler_games", 0) + fgames
            tl0 = time.time()
            exchanges = [ex for r in gen_records for ex in r.get("ex", [])]
            model.train(exchanges, feat_cards, feat_attacks)
            model.save()
            if gen % LEARN_EXPORT_EVERY == 0:
                nw = model.export(LEARNED, feat_cards, feat_attacks)
                model.report(LEARN_REPORT, now())
                log("LEARNED: %s exchanges this gen (%.0fs), %s total; exported %d weights" % (
                    f"{len(exchanges):,}", time.time() - tl0, f"{model.records:,}", nw))
            add_syn_stats(syn_stats, gen_records)
            atomic_write_json(SYN_STATS, syn_stats)
            if gen % SYN_REBUILD_EVERY == 0:
                table = build_synergy(syn_stats)
                if table:
                    atomic_write_json(SYNERGY, table)
                    write_syn_report(table, syn_stats)
                    log("SYNERGY: table rebuilt — %d cards, %d pairs" % (len(table), sum(len(r) for r in table.values()) // 2))
            atomic_write_json(STATE, st)
            write_report(st, keys)

        if time.time() >= st["deadline_ts"]:
            log("Deadline reached — final benchmark.")
            benchmark(pool, st)
            st["active"] = False
            atomic_write_json(STATE, st)
            write_report(st, keys)
            log("RUN FINISHED.")
        else:
            log("STOP file found — exiting cleanly (resume with: py cpu_tuner.py).")
    filler.stop = True
    keep_awake(False)
    try:
        os.remove(PIDFILE)
    except OSError:
        pass


if __name__ == "__main__":
    # Crash-tolerant: an unexpected exception is logged and the run resumes from the last saved state.
    for attempt in range(50):
        try:
            main()
            break
        except KeyboardInterrupt:
            log("Interrupted (Ctrl+C) — state is saved; run again to resume.")
            break
        except Exception as e:
            import traceback
            os.makedirs(TUNER_DIR, exist_ok=True)
            log("CRASH: %r — restarting in 30 s (attempt %d)\n%s" % (e, attempt + 1, traceback.format_exc()))
            time.sleep(30)
            if "--resume" not in sys.argv:
                sys.argv.append("--resume")
