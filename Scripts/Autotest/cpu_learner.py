"""
CPU counter/matchup learner (ISSUE #375) — used by cpu_tuner.py.

Learns WHY one Pokémon / attack does well against another, from self-play, as weights on combinations of TRAITS —
never "card X beats card Y" — so new sets work by just re-reading their card text.

  Traits (static, from Card_Set_Data card text):  t:Grass, hp:hi, rc:3, stage:2, power, body, ex,
                                                  atk:poison, atk:bench, atk:staller, dmg:hi, cost:3 ...
  Attack traits (per "uid|attack name"):          a:poison, a:paralyze, a:bench, a:gust, a:disrupt, a:dmg_hi ...
  Live relations (computed by the game itself, CPU_AI.cpu_rel_features, so training and play use the same code):
                                                  hits_weak, is_weak, resisted, resists, i_ohko, they_ohko, hp_adv ...

Every CPU turn of a tuning game is one EXCHANGE: from the start of the CPU's turn to the start of its next one, the
damage + Prizes swung each way (y > 0 = good for the CPU). A linear model is fitted online (SGD, L2) on crosses:

  A|my trait|their trait      R|relation      R|relation|their trait          -> matchup(me, foe)
  B|attack trait|their trait  BB|attack trait|their bench trait  BR|attack trait|relation  -> attack value
  S|state, BIAS               (soak up who was ahead; constant across the CPU's options, so not used in play)

Export (learned.json): {"cards": {uid: [traits]}, "attacks": {"uid|name": [traits]}, "bench_traits": [...],
"w": {cross: weight}} — the game sums the crosses for the option it is weighing.
"""
import glob
import json
import os
import re

BENCH_TRAITS = ["hp:lo", "power", "body", "atk:staller", "stage:2", "ex", "dmg:hi"]
LR = 0.02
L2 = 1e-4
MIN_SEEN = 150          # a cross must be seen this often before it is exported
EXPORT_CAP = 0.6        # |weight| cap on export


def _hp_band(hp):
    if hp <= 50: return "hp:lo"
    if hp <= 80: return "hp:mid"
    if hp <= 110: return "hp:hi"
    return "hp:vhi"


def _dmg(d):
    m = re.match(r"(\d+)", str(d or ""))
    return int(m.group(1)) if m else 0


def attack_traits(atk):
    tl = (atk.get("text") or "").lower()
    out = []
    if "poison" in tl: out.append("a:poison")
    if "paralyz" in tl: out.append("a:paralyze")
    if "asleep" in tl: out.append("a:sleep")
    if "confus" in tl: out.append("a:confuse")
    if "burn" in tl: out.append("a:burn")
    if "bench" in tl and ("damage to" in tl or "damage counter" in tl) and "your opponent" in tl: out.append("a:bench")
    if "switch" in tl and "defending" in tl and "opponent" in tl: out.append("a:gust")
    if "discard" in tl and "energy" in tl and "defending" in tl: out.append("a:disrupt")
    if ("draw" in tl or "search your deck" in tl) and _dmg(atk.get("damage")) <= 20: out.append("a:setup")
    if "prevent all" in tl or "reduced by" in tl: out.append("a:protect")
    if "remove" in tl and "damage counter" in tl and "from" in tl: out.append("a:heal")
    if "flip a coin" in tl or "flip 2" in tl or "flip 3" in tl: out.append("a:coin")
    if "does" in tl and "damage to itself" in tl: out.append("a:recoil")
    if "discard" in tl and "energy" in tl and "attached to" in tl and "defending" not in tl: out.append("a:selfdiscard")
    d = _dmg(atk.get("damage"))
    out.append("a:dmg0" if d == 0 else ("a:dmg_lo" if d <= 20 else ("a:dmg_mid" if d <= 50 else "a:dmg_hi")))
    c = len(atk.get("cost") or [])
    out.append("a:cost%d" % min(c, 4))
    return out


def card_traits(c):
    out = []
    for t in c.get("types") or ["Colorless"]:
        out.append("t:" + t)
    try:
        out.append(_hp_band(int(c.get("hp") or 0)))
    except ValueError:
        out.append("hp:mid")
    out.append("rc:%d" % min(3, int(c.get("convertedRetreatCost") or len(c.get("retreatCost") or []))))
    subs = c.get("subtypes") or []
    out.append("stage:2" if "Stage 2" in subs else ("stage:1" if "Stage 1" in subs else "stage:0"))
    if "EX" in subs or " ex" in (c.get("name") or ""): out.append("ex")
    for ab in c.get("abilities") or []:
        ty = (ab.get("type") or "").lower()
        if "body" in ty: out.append("body")
        elif "power" in ty: out.append("power")
    best = 0
    staller = False
    seen = set()
    for a in c.get("attacks") or []:
        best = max(best, _dmg(a.get("damage")))
        for t in attack_traits(a):
            if t.startswith("a:") and not t.startswith("a:dmg") and not t.startswith("a:cost"):
                seen.add("atk:" + t[2:])
            if t in ("a:setup", "a:protect", "a:heal"):
                staller = True
    out += sorted(seen)
    if staller: out.append("atk:staller")
    out.append("dmg:lo" if best <= 20 else ("dmg:mid" if best <= 50 else "dmg:hi"))
    return out


def extract_features(card_dir):
    cards, attacks = {}, {}
    for f in glob.glob(os.path.join(card_dir, "*.json")):
        try:
            data = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(data, list):
            continue
        for c in data:
            if not isinstance(c, dict) or "id" not in c or not str(c.get("supertype", "")).startswith("Pok"):
                continue
            uid = c["id"].lower()
            cards[uid] = card_traits(c)
            for a in c.get("attacks") or []:
                attacks[uid + "|" + (a.get("name") or "").lower()] = attack_traits(a)
    return cards, attacks


def crosses(ex, cards, attacks):
    """All active crosses for one exchange record."""
    me = cards.get(ex.get("me", ""), [])
    foe = cards.get(ex.get("foe", ""), [])
    rel = ex.get("rel", [])
    out = ["BIAS"] + ["S|" + s for s in ex.get("state", [])]
    out += ["A|%s|%s" % (m, f) for m in me for f in foe]
    out += ["R|" + r for r in rel]
    out += ["R|%s|%s" % (r, f) for r in rel for f in foe]
    at = attacks.get(ex.get("atk", ""), [])
    if at:
        bench = set()
        for b in ex.get("foe_bench", []):
            for t in cards.get(b, []):
                if t in BENCH_TRAITS:
                    bench.add(t)
        if not ex.get("foe_bench"):
            bench.add("empty")
        out += ["B|%s|%s" % (a, f) for a in at for f in foe]
        out += ["BB|%s|%s" % (a, b) for a in at for b in sorted(bench)]
        out += ["BR|%s|%s" % (a, r) for a in at for r in rel]
    return out


class Model:
    def __init__(self, path):
        self.path = path
        self.w, self.n = {}, {}
        self.records = 0
        try:
            d = json.load(open(path, encoding="utf-8"))
            self.w, self.n, self.records = d["w"], d["n"], d.get("records", 0)
        except Exception:
            pass

    def predict(self, xs):
        return sum(self.w.get(x, 0.0) for x in xs)

    def train(self, exchanges, cards, attacks):
        for ex in exchanges:
            y = float(ex.get("y", 0.0))
            xs = crosses(ex, cards, attacks)
            err = self.predict(xs) - max(-3.0, min(3.0, y))
            step = LR / max(1.0, len(xs) ** 0.5)
            for x in xs:
                cnt = self.n.get(x, 0) + 1
                self.n[x] = cnt
                wv = self.w.get(x, 0.0)
                self.w[x] = wv - step * (err + L2 * wv * cnt ** 0.5)
            self.records += 1

    def save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"w": self.w, "n": self.n, "records": self.records}, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.path)

    def export(self, path, cards, attacks):
        w = {k: round(max(-EXPORT_CAP, min(EXPORT_CAP, v)), 4) for k, v in self.w.items()
             if self.n.get(k, 0) >= MIN_SEEN and abs(v) >= 0.002 and not k.startswith(("S|", "BIAS"))}
        data = {"cards": cards, "attacks": attacks, "bench_traits": BENCH_TRAITS, "w": w, "records": self.records}
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
        return len(w)

    def report(self, path, stamp):
        rows = [(v, k, self.n.get(k, 0)) for k, v in self.w.items() if self.n.get(k, 0) >= MIN_SEEN and not k.startswith(("S|", "BIAS"))]
        rows.sort()
        def nice(k):
            p = k.split("|")
            kind = {"A": "my Pokémon [%s] vs their [%s]", "R": "relation [%s]" + (" vs their [%s]" if len(p) == 3 else ""),
                    "B": "attack [%s] vs their Active [%s]", "BB": "attack [%s] when their Bench has [%s]",
                    "BR": "attack [%s] when [%s]"}.get(p[0], "%s")
            try:
                return kind % tuple(p[1:])
            except TypeError:
                return k
        lines = ["LEARNED MATCHUPS — WHY things work (updated %s), from %s exchanges" % (stamp, f"{self.records:,}"),
                 "Value = expected swing of one CPU turn exchange (damage + Prizes, ~1.0 = a KO's worth). Traits come from card text.",
                 "", "STRONGEST POSITIVES (the CPU should seek these):"]
        lines += ["  %+.3f  %-70s (seen %s)" % (v, nice(k), f"{n:,}") for v, k, n in rows[::-1][:70]]
        lines += ["", "STRONGEST NEGATIVES (the CPU should avoid these):"]
        lines += ["  %+.3f  %-70s (seen %s)" % (v, nice(k), f"{n:,}") for v, k, n in rows[:50]]
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(tmp, path)
