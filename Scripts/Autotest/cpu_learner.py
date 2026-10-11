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
        # ISSUE #375 counters: what the Power / Body DOES, read from its text (scales to any future set).
        at = (ab.get("text") or "").lower()
        blocks = ("can't play" in at or "cannot play" in at or "can't be played" in at or ("no " in at and "can be played" in at))
        if "trainer" in at and blocks:
            out.append("pw:trainer_lock")
        if (blocks or "can't evolve" in at) and "evolution" in at:
            out.append("pw:evo_lock")
        if ("pokémon powers" in at or "poké-powers" in at or "poké-bodies" in at) and ("can't" in at or "ignore all" in at or "no effect" in at):
            out.append("pw:power_lock")
        if "bench" in at and ("prevent" in at or "no damage" in at) and "damage" in at:
            out.append("pw:bench_guard")
        if "damage counter" in at and ("move" in at or "swap" in at):
            out.append("pw:damage_move")
        if "attach" in at and "energy" in at and ("hand" in at or "deck" in at or "discard" in at or "your pokémon" in at or "as often as you like" in at or "doesn't use up" in at):
            out.append("pw:energy_accel")
        if "draw" in at and "card" in at:
            out.append("pw:draw")
        if "remove" in at and "damage counter" in at:
            out.append("pw:heal")
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
            if not isinstance(c, dict) or "id" not in c:
                continue
            if str(c.get("supertype", "")) == "Trainer":
                cards[c["id"].lower()] = ["super:trainer"]
                continue
            if not str(c.get("supertype", "")).startswith("Pok"):
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


# ───────────────────────── COUNTERS (ISSUE #375) ─────────────────────────
# Which CPU cards win more when the PLAYER shows a given card, and which CPU card traits pay off against a player's play
# STYLE. Outcome = CPU win minus that CPU deck's running win rate (so strong/weak decks don't masquerade as counters).

def opp_style(uids, cards):
    """The player's style from the cards they showed — mirrored exactly by CPU_AI.cpu_opp_style()."""
    flags = set()
    trainers = pokemon = 0
    for u in set(uids):
        tr = cards.get(u, [])
        if "super:trainer" in tr: trainers += 1
        if any(x.startswith("stage:") for x in tr): pokemon += 1
        if "stage:1" in tr or "stage:2" in tr: flags.add("opp:evolves")
        if "atk:bench" in tr: flags.add("opp:bench_dmg")
        if "power" in tr: flags.add("opp:powers")
        if "atk:staller" in tr: flags.add("opp:stall")
        if "hp:vhi" in tr: flags.add("opp:high_hp")
    if trainers >= 3: flags.add("opp:trainers")
    if pokemon >= 6: flags.add("opp:many_pokemon")
    return sorted(flags)


COUNTER_MIN_PAIR = 60
COUNTER_SHRINK = 150.0
COUNTER_CAP = 25.0


class Counters:
    def __init__(self, path):
        self.path = path
        self.d = {"deck": {}, "pair": {}, "cpu": {}, "bot": {}, "tstyle": {}, "trait": {}, "style": {}, "games": 0}
        try:
            self.d = json.load(open(path, encoding="utf-8"))
        except Exception:
            pass

    @staticmethod
    def _add(table, key, r):
        v = table.setdefault(key, [0, 0.0])
        v[0] += 1
        v[1] += r

    def add(self, records, cards):
        d = self.d
        for rec in records:
            deck = rec.get("opponent", "")
            if not deck or rec.get("result") not in ("win", "loss") or "bot_cards" not in rec:
                continue
            won = 1.0 if rec["result"] == "loss" else 0.0
            ds = d["deck"].setdefault(deck, [0, 0.0])
            base = (ds[1] + 0.65 * 20) / (ds[0] + 20)       # running deck win rate (prior 65%)
            ds[0] += 1
            ds[1] += won
            r = won - base
            d["games"] += 1
            mine = sorted(set(rec.get("cpu_cards", [])))
            theirs = sorted(u for u in set(rec.get("bot_cards", [])) if any(x.startswith("stage:") for x in cards.get(u, [])))
            for y in mine:
                self._add(d["cpu"], y, r)
            for x in theirs:
                self._add(d["bot"], x, r)
            for y in mine:
                for x in theirs:
                    self._add(d["pair"], y + "|" + x, r)
            styles = opp_style(rec.get("bot_cards", []), cards)
            traits = sorted({tr for y in mine for tr in cards.get(y, []) if tr.startswith(("pw:", "atk:", "power", "body", "hp:", "stage:", "super:"))})
            for s in styles:
                self._add(d["style"], s, r)
            for tr in traits:
                self._add(d["trait"], tr, r)
                for s in styles:
                    self._add(d["tstyle"], tr + "|" + s, r)

    def save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.d, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.path)

    def _lift(self, both, a, b):
        n, s = both
        if n < COUNTER_MIN_PAIR:
            return None
        ma = a[1] / a[0] if a and a[0] else 0.0
        mb = b[1] / b[0] if b and b[0] else 0.0
        lift = (s / n) - ma - mb
        return max(-COUNTER_CAP, min(COUNTER_CAP, 100.0 * lift * n / (n + COUNTER_SHRINK)))

    def export(self, path, cards):
        d = self.d
        out = {"cards": {}, "style": {}, "traits": cards, "games": d["games"]}
        for key, v in d["pair"].items():
            y, x = key.split("|")
            pts = self._lift(v, d["cpu"].get(y), d["bot"].get(x))
            if pts is not None and abs(pts) >= 1.0:
                out["cards"].setdefault(y, {})[x] = round(pts, 1)
        for key, v in d["tstyle"].items():
            tr, s = key.split("|")
            pts = self._lift(v, d["trait"].get(tr), d["style"].get(s))
            if pts is not None and abs(pts) >= 0.5:
                out["style"].setdefault(tr, {})[s] = round(pts, 1)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(out, f)
        os.replace(tmp, path)
        return out

    def report(self, path, table, names, stamp):
        pairs = sorted(((v, y, x) for y, row in table["cards"].items() for x, v in row.items()), reverse=True)
        styles = sorted(((v, tr, s) for tr, row in table["style"].items() for s, v in row.items()), reverse=True)
        nm = lambda u: "%s (%s)" % (names.get(u, "?"), u)
        lines = ["LEARNED COUNTERS (updated %s) from %s games" % (stamp, f"{self.d['games']:,}"),
                 "Points = extra CPU win %% when the CPU's card is out AND the player shows theirs, beyond each alone.", "",
                 "CPU TRAITS vs PLAYER STYLE (the WHY — scales to new cards):"]
        lines += ["  %+5.1f  CPU card with [%s] vs a player who %s" % (v, tr, s) for v, tr, s in styles[:40]]
        lines += ["  ...", "  worst:"] + ["  %+5.1f  CPU card with [%s] vs a player who %s" % (v, tr, s) for v, tr, s in styles[-20:]]
        lines += ["", "BEST CARD COUNTERS (CPU card  vs  player's card):"]
        lines += ["  %+5.1f  %s  vs  %s" % (v, nm(y), nm(x)) for v, y, x in pairs[:60]]
        lines += ["", "WORST (CPU card struggles against):"]
        lines += ["  %+5.1f  %s  vs  %s" % (v, nm(y), nm(x)) for v, y, x in pairs[-40:][::-1]]
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(tmp, path)


def card_names(card_dir):
    names = {}
    for f in glob.glob(os.path.join(card_dir, "*.json")):
        try:
            data = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        if isinstance(data, list):
            for c in data:
                if isinstance(c, dict) and "id" in c:
                    names[c["id"].lower()] = c.get("name", "?")
    return names
