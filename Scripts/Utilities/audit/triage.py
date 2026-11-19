"""STEP 1 triage: cheap static red flags per attack/power/body/trainer. Pure Python, no model.
Run from project root:  python -I Scripts/Utilities/audit/triage.py   -> audit_out/triage.csv
Every flag is a LEAD, not a verdict."""
import json, re, csv, glob, os, sys, collections
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
BD = os.path.join(ROOT, "Scripts", "Main_Match_Gameplay_Scripts")
OUT = os.path.join(ROOT, "audit_out"); os.makedirs(OUT, exist_ok=True)

def rd(p): return open(p, encoding="utf-8", errors="replace").read()
src = {os.path.basename(p): rd(p) for p in glob.glob(BD + "/*.gd")}
CARD_CLASS = rd(os.path.join(ROOT, "Scripts", "Objects_And_Classes", "Card_Class_Object_Script.gd"))
ALL = "\n".join(src.values()); ALL_L = ALL.lower()

# ---------- function index + call closure ----------
funcs = {}
for fn, t in src.items():
    ms = list(re.finditer(r"^func (\w+)\(", t, re.M))
    for i, m in enumerate(ms):
        end = ms[i+1].start() if i+1 < len(ms) else len(t)
        funcs[m.group(1)] = funcs.get(m.group(1), "") + "\n" + t[m.start():end]
_clo = {}
def closure(name, depth=2):
    key = (name, depth)
    if key in _clo: return _clo[key]
    body = funcs.get(name, ""); acc = body
    if depth > 0:
        for c in set(re.findall(r"\b(\w+)\(", body)):
            if c in funcs and c != name: acc += closure(c, depth-1)
    _clo[key] = acc; return acc
def closure_of_line(line, depth=2):
    return line + "".join(closure(c, depth) for c in set(re.findall(r"\b(\w+)\(", line)) if c in funcs)

# ---------- attack registry chains (file order) ----------
AE = src["Attack_Effects.gd"].split("\n")
chains = collections.defaultdict(list)
special = set()
for i, ln in enumerate(AE, 1):
    m = re.search(r'_attack_dispatch\["([^"]+)"\]\s*=', ln)
    if m: chains[m.group(1)] = [("reg", None, i, ln)]; continue
    m = re.search(r'_r3_wrap\("([^"]+)",\s*"((?:[^"\\]|\\.)*)"', ln)
    if m: chains[m.group(1)].append(("w3", m.group(2).lower(), i, ln)); continue
    m = re.search(r'_r4_wrap_if\("([^"]+)",(.*)', ln)
    if m: chains[m.group(1)].append(("w4", [s.lower() for s in re.findall(r'"([^"]+)"', m.group(2))[:3]], i, ln)); continue
for i in range(416, 480):
    for n in re.findall(r'an == "([^"]+)"', AE[i]): special.add(n)

def resolve(name, text):
    t = text.lower()
    for kind, data, ln, line in reversed(chains.get(name, [])):
        if kind == "reg": return ("reg", ln, line)
        if kind == "w3" and data in t: return ("w3", ln, line)
        if kind == "w4" and any(s in t for s in data): return ("w4", ln, line)
    return ("generic", 0, "")

PB = src["Powers_And_Bodies_Effects.gd"].split("\n")
power_reg = {}
for i, ln in enumerate(PB, 1):
    m = re.search(r'_power_dispatch\["([^"]+)"\]\s*=', ln)
    if m: power_reg[m.group(1)] = (i, ln)
TE = src["Trainer_Effects.gd"].split("\n")
trainer_reg = {}
for i, ln in enumerate(TE, 1):
    m = re.search(r'_trainer_dispatch\["([^"]+)"\]\s*=', ln)
    if m: trainer_reg[m.group(1)] = (i, ln)
CPU = src["CPU_AI.gd"]; CPU_L = CPU.lower()
pm = re.search(r"^func cpu_phase_activate_powers", src["Powers_And_Bodies_Effects.gd"], re.M)
CPU_POWER_REGION_L = ((src["Powers_And_Bodies_Effects.gd"][pm.start():] if pm else "") + CPU).lower()

skip = []
fp = os.path.join(ROOT, "AUDIT_FINDINGS_2026-11-18.md")
if os.path.exists(fp):
    for m in re.finditer(r"^### \d+\. \[.\] (\S+) (.+?) — (.+?)\s+\((\w+)\)", rd(fp), re.M):
        skip.append((m.group(1).lower(), m.group(3).lower()))
def skipped(uid, item):
    it = item.lower().split(":", 1)[-1]
    return any(u == uid.lower() and (it in i or i in it) for u, i in skip)

NUMW = {"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10}
REV = {v: k for k, v in NUMW.items()}
def nums(text):
    s = set(int(x) for x in re.findall(r"(?<![\d.])(\d{1,3})(?!\d)", text))
    for w, n in NUMW.items():
        if re.search(r"\b%s\b\s+(coins?|cards?|damage|energy|prizes?|counters?|pok.mon|times|of)" % w, text, re.I): s.add(n)
    return {n for n in s if n >= 2}
def has_num(n, clo):
    if re.search(r"(?<![\d.])%d(?!\d)" % n, clo): return True
    return n in REV and re.search(r"\b%s\b" % REV[n], clo, re.I) is not None
CHOICE = re.compile(r"\b(choose|you may|up to|any number|look at|of your choice|select)\b", re.I)
_pp = closure("parse_card_text_effects", 1).lower()
PARSER_LITS = {l for l in re.findall(r'"([^"\n]{5,})"', _pp) if " " in l.strip() and l.strip() not in ("the defending pokémon","your opponent's","defending pokémon")}
STATUSES = ["asleep","paralyzed","confused","poisoned","burned"]
def uncovered_sentences(text, name):
    t = text.lower().replace(name.lower(), "{self}")
    out = []
    for sen in re.split(r"(?<=[.!?])\s+", t):
        sen = sen.strip()
        if not sen or re.fullmatch(r"flip an? coins?\.?|flip \d+ coins?\.?", sen): continue
        if any(l in sen for l in PARSER_LITS) or any(st in sen for st in STATUSES): continue
        if re.search(r"times the number of heads|^\(don't apply weakness|you can't add more than|^\(don't apply", sen): continue   # handled by parse_coin_flip_count / bench-damage helpers
        if re.fullmatch(r"(this attack|{self}) does .{0,40}damage\.?", sen): continue
        out.append(sen)
    return out
PROMPT = re.compile(r"(prompt|pick_|_pick|choose|select_|_may\b|ask_|show_enlarged|pick\()", re.I)

rows = []
def flag(uid, card, item, fl, detail):
    if skipped(uid, item): return
    rows.append((uid, card, item, fl, detail))
def setof(uid): return re.match(r"([a-z]+\d*)-", uid).group(1)

def check_attack(c, a):
    uid, nm = c["id"], c["name"]; an = a["name"]; al = an.lower(); text = a.get("text", "") or ""
    item = "attack:" + an
    dmg = (a.get("damage") or "").strip()
    cost = a.get("cost", []) or []
    if a.get("convertedEnergyCost") is not None and len(cost) != a["convertedEnergyCost"]:
        flag(uid, nm, item, "f_data_cost", "cost list %d vs converted %s" % (len(cost), a["convertedEnergyCost"]))
    if dmg and not re.fullmatch(r"\d+[+×x\-]?", dmg):
        flag(uid, nm, item, "f_data_damage", "odd damage field %r" % dmg)
    if dmg and dmg[-1] in "+×x-" and not text:
        flag(uid, nm, item, "f_data_modifier_no_text", "damage %r has no text explaining it" % dmg)
    if "�" in text or "Ã" in text or "â€" in text:
        flag(uid, nm, item, "f_data_encoding", "garbled characters in text")
    if al not in chains and al not in special:
        if '"%s"' % al not in ALL_L and text:
            u = uncovered_sentences(text, c["name"])
            if u: flag(uid, nm, item, "d_undispatched_uncovered", "generic parser has no phrase for: " + " | ".join(x[:70] for x in u[:3]))
        return
    if al in special and al not in chains: return
    r = resolve(al, text)
    if r[0] == "generic":
        if text: flag(uid, nm, item, "b_wrap_no_match", "name has handlers but none matches this text (falls to generic copy): " + text[:80])
        return
    clo = closure_of_line(r[2], 2)
    miss = [n for n in sorted(nums(text)) if not has_num(n, clo)]
    if miss and r[0] == "reg":
        flag(uid, nm, item, "a_number_missing", "text numbers %s not in handler (L%d) closure" % (miss, r[1]))
    dn = re.match(r"\d+", dmg)
    if dn and int(dn.group()) >= 10 and r[0] == "reg" and not re.search(r'parse_attack_base_damage|get\("damage"|base_damage|base_dmg', clo) and not re.search(r"(?<!\d)%s(?!\d)" % dn.group(), clo):
        flag(uid, nm, item, "a_damage_not_in_handler", "printed damage %s neither parsed nor literal in handler L%d" % (dmg, r[1]))
    mm = CHOICE.search(text)
    if mm and not PROMPT.search(clo):
        flag(uid, nm, item, "c_choice_no_prompt", "'%s' in text but no prompt/pick in handler L%d" % (mm.group(0), r[1]))

def check_power(c, p):
    uid, nm = c["id"], c["name"]; pn = p["name"]; text = p.get("text", "") or ""
    typ = p.get("type", "") or ""
    item = ("body:" if "Body" in typ else "power:") + pn
    if not text.strip(): flag(uid, nm, item, "f_data_empty_text", "ability has no text")
    reg = power_reg.get(pn)
    in_code = '"%s"' % pn.lower() in ALL_L
    if "Body" in typ:
        if not in_code and ('has_ability("%s")' % pn) not in CARD_CLASS: flag(uid, nm, item, "d_body_unreferenced", "Poke-Body name never referenced in battle scripts")
        return
    if reg is None and not in_code:
        flag(uid, nm, item, "d_power_unreferenced", "Power name has no dispatch and is never referenced")
    if reg:
        clo = closure_of_line(reg[1], 2)
        miss = [n for n in sorted(nums(text)) if not has_num(n, clo)]
        if miss: flag(uid, nm, item, "a_number_missing", "text numbers %s not in handler (L%d) closure" % (miss, reg[0]))
        mm = CHOICE.search(text)
        if mm and not PROMPT.search(clo):
            flag(uid, nm, item, "c_choice_no_prompt", "'%s' in text but no prompt/pick in power handler L%d" % (mm.group(0), reg[0]))
    if re.search(r"once during your turn|as often as you like", text, re.I) and '"%s"' % pn.lower() not in CPU_POWER_REGION_L:
        flag(uid, nm, item, "e_power_no_cpu", "activated power never named in cpu_phase_activate_powers / CPU_AI")

def check_trainer(c):
    uid, nm = c["id"], c["name"]; rules = " ".join(c.get("rules", []) or []); item = "trainer"
    sub = "/".join(c.get("subtypes", []) or [])
    if not rules.strip(): flag(uid, nm, item, "f_data_empty_text", "trainer/energy has no rules text"); return
    reg = trainer_reg.get(uid)
    named = '"%s"' % nm.lower() in ALL_L or '"%s"' % uid.lower() in ALL_L
    if reg is None and not named:
        flag(uid, nm, item, "d_trainer_unreferenced", "%s: no trainer dispatch and uid/name never referenced" % sub)
    if reg:
        clo = closure_of_line(reg[1], 2)
        miss = [n for n in sorted(nums(rules)) if not has_num(n, clo)]
        if miss: flag(uid, nm, item, "a_number_missing", "rules numbers %s not in handler (L%d) closure" % (miss, reg[0]))
        mm = CHOICE.search(rules)
        if mm and not PROMPT.search(clo):
            flag(uid, nm, item, "c_choice_no_prompt", "'%s' in rules but no prompt/pick in handler L%d" % (mm.group(0), reg[0]))
    if '"%s"' % uid.lower() not in CPU_L and '"%s"' % nm.lower() not in CPU_L:
        flag(uid, nm, item, "e_trainer_flat_cpu_score", "%s: uid/name not in CPU_AI -> default score" % sub)

sets_seen = collections.Counter()
byname = collections.defaultdict(dict)
for p in sorted(glob.glob(os.path.join(ROOT, "Card_Set_Data", "*.json"))):
    if p.endswith("pack_prices.json"): continue
    try: cards = json.load(open(p, encoding="utf-8"))
    except Exception: continue
    if not isinstance(cards, list): continue
    for c in cards:
        if not isinstance(c, dict) or "id" not in c: continue
        sets_seen[setof(c["id"])] += 1
        st = c.get("supertype")
        if st == "Pokémon":
            if not c.get("hp"): flag(c["id"], c["name"], "card", "f_data_hp", "missing hp")
            for a in c.get("attacks", []) or []:
                check_attack(c, a)
                t = re.sub(r"\s+", " ", (a.get("text") or "").strip().lower())
                byname[a["name"].lower()].setdefault((t, a.get("damage") or ""), []).append((c["id"], c["name"], a["name"]))
            for ab in c.get("abilities", []) or []: check_power(c, ab)
        elif st == "Trainer": check_trainer(c)
        elif st == "Energy" and "Special" in (c.get("subtypes") or []): check_trainer(c)

for al, variants in byname.items():
    if len(variants) < 2 or al not in chains: continue
    by_handler = collections.defaultdict(list)
    if len({t for (t, d) in variants}) < 2: continue
    for (t, d), cs in variants.items():
        by_handler[resolve(al, t)[1]].append((t, d, cs))
    for hl, vs in by_handler.items():
        if hl and len({v[0] for v in vs}) > 1 and '"text"' not in closure_of_line(AE[hl-1], 2) and "text_lower" not in closure_of_line(AE[hl-1], 2):
            for t, d, cs in vs:
                others = [x for x in vs if x[:2] != (t, d)]
                for uid, nm, an in cs:
                    flag(uid, nm, "attack:" + an, "b_name_collision",
                         "%d different text/damage variants share handler L%d; e.g. dmg=%r %r" % (len(vs), hl, others[0][1], others[0][0][:60]))

seen = set(); out = []
for r in rows:
    if r in seen: continue
    seen.add(r); out.append(r)
with open(os.path.join(OUT, "triage.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["uid", "card", "item", "flag", "detail"]); w.writerows(out)
print("rows:", len(out), " distinct cards:", len({r[0] for r in out}), " cards scanned:", sum(sets_seen.values()), " skip entries:", len(skip))
fc = collections.Counter(r[3] for r in out); sc = collections.Counter(setof(r[0]) for r in out)
print("\nPER FLAG")
for k, v in fc.most_common(): print("  %-28s%d" % (k, v))
print("\nPER SET (flags / distinct cards / cards in set)")
for s in sorted(sc): print("  %-7s%5d / %4d / %d" % (s, sc[s], len({r[0] for r in out if setof(r[0]) == s}), sets_seen[s]))

# per-card priority list for step 4 (higher = review first)
W = {"b_wrap_no_match": 5, "d_undispatched_uncovered": 4, "d_body_unreferenced": 4, "d_power_unreferenced": 4, "d_trainer_unreferenced": 4,
     "c_choice_no_prompt": 3, "b_name_collision": 3, "a_number_missing": 2, "f_data_damage": 2, "f_data_cost": 2, "f_data_empty_text": 2,
     "a_damage_not_in_handler": 1, "e_trainer_flat_cpu_score": 1, "e_power_no_cpu": 1}
cs = collections.defaultdict(lambda: [0, set(), ""])
for uid, card, item, fl, det in out:
    e = cs[uid]; e[0] += W.get(fl, 1); e[1].add(fl); e[2] = card
with open(os.path.join(OUT, "triage_cards.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["uid", "card", "score", "flags"])
    for uid, (sc_, fls, card) in sorted(cs.items(), key=lambda kv: -kv[1][0]): w.writerow([uid, card, sc_, ",".join(sorted(fls))])
print("cards with score>=4:", sum(1 for v in cs.values() if v[0] >= 4), " >=6:", sum(1 for v in cs.values() if v[0] >= 6))
