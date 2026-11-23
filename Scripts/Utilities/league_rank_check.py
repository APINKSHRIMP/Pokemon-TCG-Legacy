"""LEAGUE RANK CHECK (2026-11-22): where does beating EVERY opponent once land the player?

Reads the live roster (All_NPC_Constant_Data.json "opponents": stars + match_format) and League_Config.json
(base_lp_by_opponent_rank, rank_xp, visible_ranks). Each opponent pays base LP once (by their stars) and every won
GAME pays the average bonus (a best-of-3 = 2 won games). Prints the total for a low / average / high bonus player
and the rank each lands on, plus the rank-up points along the way (opponents ordered by stars).

Target (user, 2026-11-22): a full clear with an average bonus sits COMFORTABLY in rank 5 (the top visible rank)
and NOT in rank 6. Re-run whenever opponents are added or League_Config numbers change:

    python Scripts/Utilities/league_rank_check.py            (bonus averages 8 / 11 / 15 - autotest range)
    python Scripts/Utilities/league_rank_check.py 6 11 20
    python Scripts/Utilities/league_rank_check.py --no-planned   (live roster only)

The user's planned new decks (PLANNED below) are counted as one opponent each until a live opponent uses that deck.
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "NPC_and_Opponent_Data")

# The user's planned new decks (2026-11-20 list), each becoming one new opponent. Their STARS come from
# NPC_and_Opponent_Data/Deck_Ratings.json (the user's own ratings, 2026-11-23). Any deck already on a live
# opponent is skipped, so this list shrinks to nothing on its own as the opponents go in.
PLANNED = (
    "Conversion 4", "Big Fish Small Fish", "Wildfires", "Transform", "Boyfriend and Girlfriend", "Bait and Switch",
    "Promotional Flight", "Hay Maker Lite", "Fancy Footwork", "Outstall the Wall", "Jungle Migraine",
    "Dragotoise", "Lot Of Char", "Confusing Petals", "Calm and Fury", "Tentacle Retreat", "Make the Ground Shake",
    "Rapid Photosynthesis", "Neuron Connection", "Erika's Kind Strength", "Energy Recoupling",
    "Energy Energy Energy", "Weedsprayer", "Just all Flips", "OTK", "Trapped",
    "Guaranteed Infliction", "Some Birds Some Stones", "Cerulean Coin Flips", "Psilocybin", "Night Spirits",
    "Brock Collection", "All or nothing", "ESP Foresight", "Incinerator", "Dragon Rage",
)


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)


def rank_for(xp, th):
    r = 1
    for i, t in enumerate(th):
        if xp >= t:
            r = i + 1
    return r


def main():
    avgs = [float(a) for a in sys.argv[1:] if not a.startswith("--")] or [8.0, 11.0, 15.0]
    cfg = load("League_Config.json")
    opps = load("All_NPC_Constant_Data.json")["opponents"]
    base = cfg["base_lp_by_opponent_rank"]
    th = cfg["rank_xp"]
    vis = int(cfg.get("visible_ranks", len(th)))

    roster = []
    for name, e in opps.items():
        stars = min(8, max(1, int(e.get("stars", 1) or 1)))
        games = 2 if e.get("match_format") == "best_of_3" else 1
        roster.append((stars, name, games))
    used_decks = {e.get("deck") for e in opps.values()}
    ratings = load("Deck_Ratings.json")["decks"]
    planned = [(int(ratings.get(n, {}).get("stars", 3)), "(planned) " + n, 1) for n in PLANNED if n not in used_decks]
    if planned and "--no-planned" not in sys.argv:
        print("%d live opponents + %d planned new decks (--no-planned to leave them out)" % (len(roster), len(planned)))
        roster += planned
    roster.sort()
    base_total = sum(base[s - 1] for s, _, _ in roster)
    games = sum(g for _, _, g in roster)
    print("%d opponents, %d won games, base LP %d" % (len(roster), games, base_total))
    print("rank_xp %s   (visible ranks 1-%d)" % (th, vis))
    for a in avgs:
        total = base_total + games * a
        r = rank_for(total, th)
        nxt = th[r] if r < len(th) else None
        print("  avg bonus %5.1f -> %6d LP  rank %d  (%+d past rank %d%s)" % (
            a, total, r, total - th[r - 1], r,
            "" if nxt is None else ", %d short of rank %d" % (nxt - total, r + 1)))
    a = avgs[len(avgs) // 2]
    print("rank-ups along the way at avg %.1f (opponents easiest first):" % a)
    xp, r = 0, 1
    for i, (s, name, g) in enumerate(roster, 1):
        xp += base[s - 1] + g * a
        nr = rank_for(xp, th)
        if nr > r:
            print("  rank %d after %3d/%d opponents (%s, %d stars)" % (nr, i, len(roster), name, s))
            r = nr


if __name__ == "__main__":
    main()
