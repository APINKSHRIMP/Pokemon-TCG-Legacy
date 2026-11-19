"""STEP 4 helper: builds the review queue and an evidence pack per batch (card text + flags + the handler code), so the
reviewer reads one compact file instead of grepping. Usage:
  python -I Scripts/Utilities/audit/make_batch.py            -> audit_out/queue.txt (ranked uids, once)
  python -I Scripts/Utilities/audit/make_batch.py N [size]   -> audit_out/batch_N.md with the next `size` (default 22) uids not in done.txt
"""
import csv, json, re, glob, os, sys, collections
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "audit_out")
BD = os.path.join(ROOT, "Scripts", "Main_Match_Gameplay_Scripts")
def rd(p): return open(p, encoding="utf-8", errors="replace").read()

def rows(name):
    p = os.path.join(OUT, name)
    return list(csv.DictReader(open(p, encoding="utf-8"))) if os.path.exists(p) else []
KEEP = {"b_wrap_no_match", "d_undispatched_uncovered", "d_body_unreferenced", "d_power_unreferenced", "d_trainer_unreferenced", "f_data_damage", "f_data_cost",
        "f_data_empty_text", "f_data_hp", "f_data_encoding", "f_data_modifier_no_text", "run_hang", "run_script_error", "run_damage_mismatch", "run_damage_below_base",
        "run_status_missing", "run_draw_short", "run_trainer_no_effect", "run_stated_damage_not_seen"}   # TIGHTENED after batch 1 (0/20 real): static collision/number/choice flags dropped
triage = [r for r in rows("triage.csv") if r["flag"] in KEEP]
runs = [r for r in rows("run_diffs.csv") if r["flag"] in KEEP]
for r in triage:   # hand-added lead from the autotester (step 3): the Pebble Throw cards
    pass
W = {"run_hang": 9, "run_script_error": 9, "run_not_implemented": 9, "run_damage_mismatch": 7, "run_status_missing": 7, "run_damage_below_base": 6,
     "run_stated_damage_not_seen": 5, "run_draw_short": 5, "run_trainer_no_effect": 5, "run_power_no_effect": 3, "run_choice_no_prompt": 3, "run_refused_setup": 0, "run_no_post_state": 0,
     "b_wrap_no_match": 5, "d_undispatched_uncovered": 4, "d_body_unreferenced": 4, "d_power_unreferenced": 4, "d_trainer_unreferenced": 4,
     "c_choice_no_prompt": 3, "b_name_collision": 3, "a_number_missing": 2, "f_data_damage": 2, "f_data_cost": 2, "f_data_empty_text": 2,
     "a_damage_not_in_handler": 1, "e_trainer_flat_cpu_score": 1, "e_power_no_cpu": 1}
SETORD = {s: i for i, s in enumerate(["ex10", "ex11", "ex12", "ex13", "ex14", "ex15", "ex16", "ex1", "ex2", "ex3", "ex4", "ex5", "ex6", "ex7", "ex8", "ex9"])}
def setof(u): return u.split("-")[0].lower()
score = collections.defaultdict(float); flags = collections.defaultdict(list)
for r in triage + runs:
    u = r["uid"].lower(); score[u] += W.get(r["flag"], 1); flags[u].append(r)
for u in score:   # cards seen by BOTH triage and a real run get a bonus
    if any(r["flag"].startswith("run_") for r in flags[u]) and any(not r["flag"].startswith("run_") for r in flags[u]): score[u] += 5
ranked = sorted(score, key=lambda u: (SETORD.get(setof(u), 99), -score[u]))   # ex sets first, best first within set
qp = os.path.join(OUT, "queue.txt")
if not os.path.exists(qp) or len(sys.argv) == 1:
    for u in ("ex3-55", "ex12-67", "ex13-65", "ex16-64"): score[u] += 8; flags[u].append({"uid": u, "item": "attack:Pebble Throw", "flag": "autotest_skipped_attack", "detail": "step 3: CPU skipped it; log said no recognised effects for the choose-1-Benched text"})
    ranked = sorted(score, key=lambda u: (SETORD.get(setof(u), 99), -score[u]))
    open(qp, "w", encoding="utf-8").write("\n".join("%s\t%.0f" % (u, score[u]) for u in ranked))
    print("queue:", len(ranked), "cards;", sum(1 for u in ranked if setof(u) in SETORD), "in ex sets")
if len(sys.argv) == 1: sys.exit()

N = sys.argv[1]; size = int(sys.argv[2]) if len(sys.argv) > 2 else 22
dp = os.path.join(OUT, "done.txt"); done = set(rd(dp).split()) if os.path.exists(dp) else set()
queue = [l.split("\t")[0] for l in rd(qp).split("\n") if l]
# real-run evidence and big scores first within what is not done
todo = [u for u in queue if u not in done and (setof(u) in SETORD or "--all-sets" in sys.argv)]
todo.sort(key=lambda u: -score[u])
pick = todo[:size]
meta = {}
for p in glob.glob(os.path.join(ROOT, "Card_Set_Data", "*.json")):
    if p.endswith("pack_prices.json"): continue
    for c in json.load(open(p, encoding="utf-8")):
        if isinstance(c, dict) and "id" in c: meta[c["id"].lower()] = c
src = {os.path.basename(p): rd(p) for p in glob.glob(BD + "/*.gd")}
AE = src["Attack_Effects.gd"].split("\n"); PB = src["Powers_And_Bodies_Effects.gd"].split("\n"); TE = src["Trainer_Effects.gd"].split("\n")
funcs = {}
for fn, t in src.items():
    for m in re.finditer(r"^func (\w+)\(", t, re.M):
        funcs.setdefault(m.group(1), (fn, t, m.start()))
def body(name, maxl=45):
    if name not in funcs: return ""
    fn, t, st = funcs[name]; ln = t[st:].split("\n"); out = [ln[0]]
    for l in ln[1:]:
        if l.startswith("func "): break
        out.append(l)
    return "[%s]\n" % fn + "\n".join(out[:maxl])
def handlers_for(item, text):
    kind, _, name = item.partition(":")
    lines = []
    if kind == "attack":
        al = name.lower(); tl = text.lower()
        for i, ln in enumerate(AE, 1):
            if ('_attack_dispatch["%s"]' % al in ln) or re.search(r'_r[34]_wrap(_if)?\("%s"' % re.escape(al), ln): lines.append(("Attack_Effects.gd", i, ln.strip()))
    elif kind == "power" or kind == "body":
        for i, ln in enumerate(PB, 1):
            if '_power_dispatch["%s"]' % name in ln: lines.append(("Powers_And_Bodies_Effects.gd", i, ln.strip()))
    return lines
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "batch_%s.md" % N), "w", encoding="utf-8") as f:
    f.write("# batch %s: %s\n" % (N, ", ".join(pick)))
    for u in pick:
        c = meta[u]; f.write("\n\n=========== %s %s (%s) score %.0f\n" % (u, c["name"], "/".join(c.get("subtypes", []) or []), score[u]))
        items = collections.OrderedDict()
        for r in flags[u]: items.setdefault(r["item"], []).append(r)
        for item, rs in items.items():
            kind, _, name = item.partition(":")
            text = ""
            if kind == "attack":
                for a in c.get("attacks", []):
                    if a["name"] == name: text = "dmg=%s cost=%s | %s" % (a.get("damage", ""), "".join(x[0] for x in a.get("cost", [])), a.get("text", ""))
            elif kind in ("power", "body"):
                for a in c.get("abilities", []):
                    if a["name"] == name: text = a.get("text", "")
            else: text = " ".join(c.get("rules", []) or [])
            f.write("\n--- %s\nTEXT: %s\n" % (item, text))
            for r in rs: f.write("FLAG %s: %s\n" % (r["flag"], r["detail"][:200]))
            hs = handlers_for(item, text)
            for fn, i, ln in hs[-3:]:
                f.write("HANDLER %s:%d  %s\n" % (fn, i, ln[:260]))
            if hs:
                m = re.findall(r"\b((?:execute|r3|r4|_r3|_r4|effect|power)_\w+)\(", hs[-1][2])
                if m: f.write(body(m[0]) + "\n")
            elif kind == "trainer":
                import_line = [ (i, l.strip()) for i, l in enumerate(TE, 1) if '_trainer_dispatch["%s"]' % u in l]
                if import_line:
                    f.write("HANDLER Trainer_Effects.gd:%d  %s\n" % import_line[0])
                    m = re.findall(r"\b(effect_\w+)\(", import_line[0][1])
                    if m: f.write(body(m[0]) + "\n")
print("batch_%s.md: %d cards, %d bytes" % (N, len(pick), os.path.getsize(os.path.join(OUT, "batch_%s.md" % N))))
