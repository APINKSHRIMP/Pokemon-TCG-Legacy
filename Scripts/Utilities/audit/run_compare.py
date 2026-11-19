"""STEP 2 compare: audit_out/run_log.jsonl (what the game DID) vs the card text -> audit_out/run_diffs.csv.
Run:  python -I Scripts/Utilities/audit/run_compare.py
Board: standard defender has 900 HP, no weakness/resistance/abilities; attacker has its full cost + 2 spare Energy.
Coin flips make some results random, so anything whose text flips a coin is only checked for errors/prompts."""
import json, re, csv, glob, os, sys, collections
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(ROOT, "audit_out")
meta = {}
for p in glob.glob(os.path.join(ROOT, "Card_Set_Data", "*.json")):
    if p.endswith("pack_prices.json"): continue
    try: d = json.load(open(p, encoding="utf-8"))
    except Exception: continue
    for c in d:
        if isinstance(c, dict) and "id" in c: meta[c["id"].lower()] = c
CHOICE = re.compile(r"\b(choose|you may|up to|any number|look at|of your choice|select)\b", re.I)
STAT = re.compile(r"(?:defending pok.mon|it) is now (asleep|confused|paralyzed|poisoned|burned)", re.I)

def text_of(rec, c):
    if rec["kind"] == "attack":
        a = c["attacks"][0:] ;
        for x in a:
            if x["name"] == rec["name"]: return x
    elif rec["kind"] == "power":
        for x in c.get("abilities", []):
            if x["name"] == rec["name"]: return {"name": x["name"], "text": x.get("text", ""), "damage": ""}
    else:
        return {"name": c["name"], "text": " ".join(c.get("rules", []) or []), "damage": ""}
    return {"name": rec["name"], "text": "", "damage": ""}

rows = []
def add(rec, c, fl, detail): rows.append((rec["uid"], c.get("name", "?"), rec["kind"] + ":" + str(rec["name"]), fl, detail))

n = 0
ALL = {}   # newest record per job (a job re-run later in run_log.jsonl replaces the older one)
for line in open(os.path.join(OUT, "run_log.jsonl"), encoding="utf-8"):
    r0 = json.loads(line); n += 1
    ALL[(r0["uid"].lower(), r0["kind"], str(r0["name"]), r0.get("scen", ""))] = r0
BASE = {}  # (uid, attack name) -> damage dealt on the standard board, for the conditional-board comparisons
for k0, r0 in ALL.items():
    if k0[1] == "attack" and r0.get("post"): BASE[(k0[0], k0[2])] = r0["pre"]["def_hp"] - r0["post"]["def_hp"]
for rec in ALL.values():
    if rec["kind"] not in ("attack", "power", "trainer"): continue
    c = meta.get(rec["uid"].lower())
    if not c: continue
    t = text_of(rec, c); text = t.get("text", "") or ""; tl = text.lower()
    pre, post = rec["pre"], rec["post"]
    msgs = " | ".join(rec["msgs"]); msgl = msgs.lower()
    if rec["timed_out"]: add(rec, c, "run_hang", "no result within %d frames; last msgs: %s" % (rec["frames"], msgs[:120])); continue
    ps = any(x.get("name") == "Power Saver" for x in c.get("abilities", []) or [])   # PROBE ARTIFACT (known): Power Saver -> get_attacks_for_card = [] -> Main:9967
    for e in rec["errors"]:
        if e.startswith("Card_Probe.gd") or (ps and "Core_Gameplay_Script.gd:9967" in e): continue
        add(rec, c, "run_script_error", e)
    onplay = re.search(r"when you (play|put) .{0,60}(from your hand)", tl) is not None   # on-evolve / on-bench Powers run from hooks, not activate_power
    if "not implemented" in msgl and not (rec["kind"] == "power" and onplay): add(rec, c, "run_not_implemented", msgs[:140])
    refused = any(k in msgl for k in ["can't be used", "is disabled", "can't attack", "can't use", "isn't"])
    if not post: add(rec, c, "run_no_post_state", "match ended or state unreadable"); continue
    flips = "flip" in tl or "coin" in tl
    # PROBE ARTIFACT: there is no basic Darkness Energy, so Darkness attackers are paid with Darkness Energy (Special: +10 damage each).
    dark = "Darkness" in (c.get("types") or [])
    bonus_ok = 10 * pre.get("me_energy", 0) if dark else 0
    has_body = any("Body" in (x.get("type") or "") for x in c.get("abilities", []) or [])
    if has_body or post.get("foe_active_swapped"): flips = True   # Bodies like Vigorous Aura change damage; switched defender = dealt looks 0
    if dark: flips = True   # Darkness attackers: damage checks are unreliable on this board (Special Darkness Energy adds damage)
    if "different amount of energy" in tl or "instead" in tl or "more damage for each" in tl or "times the" in tl or "each of your opponent" in tl or "each pok" in tl or "that has any" in tl or "for each" in tl or "to 1 of your" in tl: flips = True   # conditional base damage the probe board decides
    dealt = pre["def_hp"] - post["def_hp"]
    deltas = [dealt] + [a - b for a, b in zip(pre["foe_bench_hp"], post["foe_bench_hp"])] + [pre["me_hp"] - post["me_hp"]]
    deltas = [d for d in deltas if d]
    if rec["kind"] == "attack":
        dm = (t.get("damage") or "").strip()
        plain = re.fullmatch(r"\d+", dm or "")
        if plain and not flips and not refused:
            if dealt != int(dm) and not (dark and int(dm) < dealt <= int(dm) + bonus_ok and (dealt - int(dm)) % 10 == 0): add(rec, c, "run_damage_mismatch", "printed %s, dealt %d (text: %s)" % (dm, dealt, text[:70]))
        elif dm.endswith("+") and dm[:-1].isdigit() and not flips and not refused and dealt < int(dm[:-1]):
            add(rec, c, "run_damage_below_base", "printed %s, dealt %d (text: %s)" % (dm, dealt, text[:70]))
        if not flips and not refused:
            for ndm in ([] if "for each" in tl or "times" in tl or "plus" in tl else set(int(x) for x in re.findall(r"(\d+) damage", tl))):
                if ndm >= 10 and ndm not in [abs(d) for d in deltas] and not (dm.rstrip("+×x-") == str(ndm) and dealt):
                    add(rec, c, "run_stated_damage_not_seen", "text says %d damage; observed hp changes %s (text: %s)" % (ndm, deltas, text[:70]))
            sm = STAT.search(tl)
            if sm and "if " not in tl.split(sm.group(0))[0][-40:] and "unless" not in tl:
                want = sm.group(1)
                has = {"asleep": post["def_cond"] == "Asleep", "confused": post["def_cond"] == "Confused", "paralyzed": post["def_cond"] == "Paralyzed",
                       "poisoned": post["def_pois"], "burned": post["def_burn"]}[want]
                if not has and post["def_in_play"] and not post["foe_active_swapped"]:
                    add(rec, c, "run_status_missing", "text says %s but defender shows cond=%r pois=%s burn=%s" % (want, post["def_cond"], post["def_pois"], post["def_burn"]))
            dr = re.search(r"draw (\d+) cards?", tl)
            if dr and "opponent" not in tl.split(dr.group(0))[0][-30:] and "if " not in tl.split("draw")[0]:
                got = post["my_hand"] - pre["my_hand"]
                if got < min(int(dr.group(1)), pre["my_deck"]): add(rec, c, "run_draw_short", "text draws %s, hand changed by %d" % (dr.group(1), got))
    elif rec["kind"] == "power":
        if pre == post and not rec["prompts"] and not refused and "not implemented" not in msgl and not onplay:
            add(rec, c, "run_power_no_effect", "state identical before/after; text: %s" % text[:90])
    else:
        if pre["my_hand"] == post["my_hand"] and pre["my_disc"] == post["my_disc"] and not rec["prompts"] and "not implemented" not in msgl:
            add(rec, c, "run_trainer_no_effect", "hand/discard unchanged after play; msgs: %s" % msgs[:90])
    if CHOICE.search(text) and not rec["prompts"] and not refused and rec["kind"] != "attack":
        add(rec, c, "run_choice_no_prompt", "text has choice wording, bot was asked nothing; text: %s" % text[:80])
    elif CHOICE.search(text) and not rec["prompts"] and rec["kind"] == "attack" and not refused:
        add(rec, c, "run_choice_no_prompt", "attack text has choice wording, bot was asked nothing; text: %s" % text[:80])
    if refused: add(rec, c, "run_refused_setup", "attack refused on the standard board (probe limit, not necessarily a bug): " + msgs[:100])

_n_saved = n
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "run_compare_ext.py"), encoding="utf-8").read())
n = _n_saved   # Tools / Stadiums / Special Energy / conditional boards

with open(os.path.join(OUT, "run_diffs.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["uid", "card", "item", "flag", "detail"]); w.writerows(rows)
fc = collections.Counter(r[3] for r in rows)
print("jobs logged:", n, " diffs:", len(rows), " distinct cards:", len({r[0] for r in rows}))
for k, v in fc.most_common(): print("  %-30s%d" % (k, v))
