"""
Human vs CPU decision analysis (ISSUE #375) — reads the dev match recorder's logs (user://match_logs/*.jsonl, written in
DebugMode for every real match) and compares each of the PLAYER's decisions with what the CPU's own logic would have done
in the same seat (the recorded "shadow"). Writes match_logs/human_vs_cpu.txt.

  py cpu_match_analyse.py

Per decision type: how often the CPU agrees with the player, then every disagreement with its board context, so recurring
patterns ("the player builds a backup earlier", "plays Bill first", "keeps Defender for the KO turn") can be turned into CPU
rules — and then proven with cpu_ab_test.py before they ship.
"""
import glob
import json
import os
from collections import defaultdict

LOGS = os.path.join(os.environ["APPDATA"], "Godot", "app_userdata", "Pokemon_TCG_Legacy", "match_logs")
OUT = os.path.join(LOGS, "human_vs_cpu.txt")


def mons(side):
    out = []
    if side.get("active"):
        out.append(("active", side["active"]))
    for b in side.get("bench", []):
        out.append(("bench", b))
    return out


def ctx(state):
    p, c = state["player"], state["cpu"]
    pa, ca = p.get("active") or {}, c.get("active") or {}
    return "T%d | you: %s %s/%s (%dE), bench %d, hand %d, prizes %d | CPU: %s %s/%s (%dE), bench %d, prizes %d" % (
        state["turn"], pa.get("name", "-"), pa.get("hp", 0), pa.get("max", 0), len(pa.get("energy", [])), len(p["bench"]),
        len(p["hand"]), len(p["prizes"]), ca.get("name", "-"), ca.get("hp", 0), ca.get("max", 0), len(ca.get("energy", [])),
        len(c["bench"]), len(c["prizes"]))


def energy_target(before, after, energy_uid):
    """Which of the player's Pokémon gained `energy_uid` between two snapshots."""
    b_counts = {m["uid"]: m.get("energy", []).count(energy_uid) for _, m in mons(before["player"])}
    for _, m in mons(after["player"]):
        if m.get("energy", []).count(energy_uid) > b_counts.get(m["uid"], 0):
            return m
    return None


def main():
    files = sorted(glob.glob(os.path.join(LOGS, "*.jsonl")))
    agree = defaultdict(lambda: [0, 0])     # kind -> [agree, total]
    diffs = defaultdict(list)
    results = defaultdict(int)
    for fpath in files:
        rows = []
        for line in open(fpath, encoding="utf-8"):
            try:
                rows.append(json.loads(line))
            except Exception:
                pass
        opp = rows[0].get("opponent", "?") if rows else "?"
        for r in rows:
            if r["t"] == "end":
                results[r["result"]] += 1
        for i, r in enumerate(rows):
            if r["t"] != "decision":
                continue
            sh = r.get("shadow") or {}
            st = r["state"]
            nxt = next((x for x in rows[i + 1:] if "state" in x), None)
            after = nxt["state"] if nxt else st
            kind = r["kind"]
            tag = "%s | %s" % (os.path.basename(fpath)[:19], opp)
            if kind == "play_card":
                uid = r.get("card", "")
                name = r.get("card_name", "")
                hand_cards = st["player"]["hand"]
                # Energy attach: the played card is now attached to one of your Pokémon.
                tgt = energy_target(st, after, uid)
                if tgt is not None:
                    if sh.get("energy"):
                        ok = tgt["uid"] == sh["energy"]["target"]
                        agree["energy target"][0] += ok
                        agree["energy target"][1] += 1
                        if not ok:
                            diffs["energy target"].append("%s\n      you: %s -> %s   CPU: -> %s (score %s)\n      %s" % (
                                tag, name, tgt["name"], sh["energy"]["target_name"], sh["energy"]["score"], ctx(st)))
                    continue
                trs = {t["name"]: t for t in sh.get("trainers", [])}
                if name in trs:
                    t = trs[name]
                    agree["trainer: play now"][0] += bool(t["play"])
                    agree["trainer: play now"][1] += 1
                    if not t["play"]:
                        diffs["trainer: play now"].append("%s\n      you played %s; CPU would hold it (score %s)\n      %s" % (tag, name, t["score"], ctx(st)))
                    continue
                if sh.get("evolve") and uid == sh["evolve"]["card"]:
                    agree["evolve"][0] += 1
                    agree["evolve"][1] += 1
                    continue
                if sh.get("bench") is not None and uid == sh["bench"]["uid"]:
                    agree["bench choice"][0] += 1
                    agree["bench choice"][1] += 1
                    continue
                if sh.get("bench") is not None and len(after["player"]["bench"]) > len(st["player"]["bench"]):
                    agree["bench choice"][1] += 1
                    diffs["bench choice"].append("%s\n      you benched %s; CPU would bench %s (score %s)\n      %s" % (
                        tag, name, sh["bench"]["name"], sh["bench"]["score"], ctx(st)))
            elif kind == "attack":
                atks = sh.get("attacks", [])
                if atks:
                    ok = atks[0]["name"] == r.get("attack", "")
                    agree["attack choice"][0] += ok
                    agree["attack choice"][1] += 1
                    if not ok:
                        diffs["attack choice"].append("%s\n      you: %s   CPU: %s   (CPU scores: %s)\n      %s" % (
                            tag, r.get("attack", ""), atks[0]["name"], ", ".join("%s %s" % (a["name"], a["score"]) for a in atks), ctx(st)))
                # Ending the turn by attacking with Energy still in hand the CPU would have attached
                if sh.get("energy") and not st["player"].get("energy_played"):
                    diffs["skipped Energy attach"].append("%s\n      attacked without attaching; CPU would attach %s -> %s\n      %s" % (
                        tag, sh["energy"]["energy"], sh["energy"]["target_name"], ctx(st)))
            elif kind == "retreat":
                rt = sh.get("retreat") or {}
                ok = bool(rt.get("would"))
                agree["retreat (you retreated)"][0] += ok
                agree["retreat (you retreated)"][1] += 1
                if not ok:
                    diffs["retreat (you retreated)"].append("%s\n      you retreated; CPU would stay\n      %s" % (tag, ctx(st)))
            elif kind == "end_turn":
                rt = sh.get("retreat") or {}
                if rt.get("would"):
                    agree["retreat (you stayed)"][1] += 1
                    diffs["retreat (you stayed)"].append("%s\n      you stayed; CPU would retreat into %s\n      %s" % (tag, rt.get("to_name", ""), ctx(st)))
                held = [t["name"] for t in sh.get("trainers", []) if t["play"]]
                if held:
                    diffs["trainers you held"].append("%s\n      you ended the turn holding %s — the CPU would play them\n      %s" % (tag, ", ".join(held), ctx(st)))
    lines = ["HUMAN vs CPU — %d matches recorded (you won %d, lost %d, drew %d)" % (len(files), results["win"], results["loss"], results["draw"]),
             "For each of YOUR decisions: would the CPU's own logic (in your seat) have done the same?", ""]
    for k, (a, n) in sorted(agree.items()):
        lines.append("  %-28s CPU agrees %3d / %3d  (%d%%)" % (k, a, n, 100 * a // max(1, n)))
    for k, items in sorted(diffs.items()):
        lines += ["", "== %s — %d cases" % (k.upper(), len(items))]
        lines += ["  " + x for x in items[:80]]
    open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("\n".join(lines[:40]))
    print("\nFull report:", OUT)


if __name__ == "__main__":
    main()
