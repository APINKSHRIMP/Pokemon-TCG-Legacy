"""Medal art + definitions builder.

    python Scripts/Utilities/medal_art_build.py --init-json   # (re)write NPC_and_Opponent_Data/Medals.json
    python Scripts/Utilities/medal_art_build.py               # render Image_Assets/Medals/*.png from Medals.json

Medals.json is the single list the game reads (Scripts/Global_Scripts/Medal_Data.gd). Add a medal = add one entry.
The PNGs rendered here are pixel-art coins (32x32, one metal each, symbol engraved). Every symbol is a hand-drawn
20x20 pixel grid in medal_emblems.py (2026-11-22) - edit the grid, not this file. Drop a hand-drawn 32x32 PNG with
the same file name into Image_Assets/Medals/ to replace a whole coin instead - no code change. Naming:
    single-grade medal      <id>.png
    tiered medal            <id>_<n>.png   (n = 1 .. number of tiers; the game shades the locked slot itself)
Re-running this script overwrites EVERY png - copy your own art elsewhere first or pass --only-missing.
"""
import json, math, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from medal_emblems import E as EMBLEMS

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
JSON_PATH = os.path.join(ROOT, "NPC_and_Opponent_Data", "Medals.json")
OUT_DIR = os.path.join(ROOT, "Image_Assets", "Medals")
SET_ICONS = os.path.join(ROOT, "Image_Assets", "Icons", "Set_Icons")
ENERGY_ICONS = os.path.join(ROOT, "Image_Assets", "Icons", "Energy_Icons")
S = 32

METALS = {
    "slate":    ["#2a313a", "#46505c", "#657282", "#8996a6", "#b6c1cd"],
    "bronze":   ["#3f230f", "#74401d", "#a5642c", "#cb8847", "#ebb680"],
    "silver":   ["#434850", "#747a84", "#a2a8b1", "#c9ced5", "#f0f3f6"],
    "gold":     ["#4a3708", "#7a5f12", "#b08a1f", "#dcb934", "#f8e785"],
    "platinum": ["#34545b", "#638a92", "#93b9c0", "#c2dfe3", "#f0fbfc"],
}


def _boost(h, sat=1.1, val=1.1):
    import colorsys
    r, g, b = [int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    hh, ss, vv = colorsys.rgb_to_hsv(r, g, b)
    r, g, b = colorsys.hsv_to_rgb(hh, min(1.0, ss * sat), min(1.0, vv * val))
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


# +10% saturation and brightness on every medal (2026-11-20 pass). MedalSparkle.gd's colours match these.
METALS = {k: [_boost(c) for c in v] for k, v in METALS.items()}
TIER_METALS = {
    1: ["gold"],
    4: ["bronze", "silver", "gold", "platinum"],
    5: ["slate", "bronze", "silver", "gold", "platinum"],
    6: ["slate", "bronze", "silver", "gold", "platinum", "platinum+"],   # + = studded rim
}

SETS = [
    ("base1", "Base Set"), ("base2", "Jungle"), ("base3", "Fossil"), ("base5", "Team Rocket"), ("basep", "Wizards Promos"),
    ("gym1", "Gym Heroes"), ("gym2", "Gym Challenge"),
    ("neo1", "Neo Genesis"), ("neo2", "Neo Discovery"), ("neo3", "Neo Revelation"), ("neo4", "Neo Destiny"), ("np", "Neo Promos"),
    ("ecard1", "Expedition"), ("ecard2", "Aquapolis"), ("ecard3", "Skyridge"), ("si1", "Southern Islands"),
    ("ex1", "Ruby & Sapphire"), ("ex2", "Sandstorm"), ("ex3", "Dragon"), ("ex4", "Team Magma vs Team Aqua"), ("ex5", "Hidden Legends"),
    ("ex6", "FireRed & LeafGreen"), ("ex7", "Team Rocket Returns"), ("ex8", "Deoxys"), ("ex9", "Emerald"), ("ex10", "Unseen Forces"),
    ("ex11", "Delta Species"), ("ex12", "Legend Maker"), ("ex13", "Holon Phantoms"), ("ex14", "Crystal Guardians"),
    ("ex15", "Dragon Frontiers"), ("ex16", "Power Keepers"),
    ("pop1", "POP Series 1"), ("pop2", "POP Series 2"), ("pop3", "POP Series 3"), ("pop4", "POP Series 4"), ("pop5", "POP Series 5"),
]
TYPES = ["Grass", "Fire", "Water", "Lightning", "Psychic", "Fighting", "Darkness", "Metal", "Colorless"]
LEADERS = [  # (name as it prefixes the Pokemon, display, badge) - in Kanto gym order, Rocket last
    ("Brock", "Brock", "boulder"), ("Misty", "Misty", "cascade"), ("Lt. Surge", "Lt. Surge", "thunder"),
    ("Erika", "Erika", "rainbow"), ("Koga", "Koga", "soul"), ("Sabrina", "Sabrina", "marsh"),
    ("Blaine", "Blaine", "volcano"), ("Giovanni", "Giovanni", "earth"), ("Rocket", "Team Rocket", "letter_r"),
]


MIN_NAMES = 6   # a type / leader deck needs at least this many DIFFERENT named Pokemon


def definitions():
    d = []
    for sid, name in SETS:
        d.append({"id": "set_" + sid, "name": name, "group": "Sets", "kind": "set", "set_id": sid,
                  "desc": "Collect every card in %s." % name, "emblem": "set:" + sid, "metal": "gold"})
    # tiers: numbers, or "all" = every one that exists (MedalData resolves it live)
    mil = [
        ("cards", "Collector", "cards_owned", [100, 500, 1000, 2000, 5000], "Own %d cards.", "glyph:cards"),
        ("cash", "Money Bags", "cash_earned", [1000, 5000, 9999, 99999], "Earn $%d in total.", "glyph:moneybag"),
        ("packs", "Pack Ripper", "packs_opened", [10, 25, 50, 100, 200, 500], "Open %d packs.", "glyph:packs"),
        ("wins", "Winner Winner Chicken Dinner", "matches_won", [10, 25, 50, 100, 200, 500], "Win %d matches.", "glyph:trophy"),
        ("coins", "Coin Collector", "coins_owned", [10, 50, 100, 200, "all"], "Collect %d coins.", "glyph:coin"),
        ("costumes", "Wardrobe", "costumes_owned", [5, 20, 50, 100, "all"], "Collect %d costumes.", "glyph:costume"),
        ("sleeves", "Sleeve Collector", "sleeves_owned", [10, 25, 75, 150, "all"], "Collect %d sleeves.", "glyph:sleeve"),
        ("fish_total", "Angler", "fish_caught", [10, 50, 100, 250, 500], "Catch %d fish.", "glyph:fish"),
        ("fish_species", "Marine Biologist", "fish_species", [5, 10, 20, 50, "all"], "Catch %d different species of fish.", "glyph:fish_school"),
    ]
    for mid, name, stat, tiers, desc, emb in mil:
        d.append({"id": mid, "name": name, "group": "Milestones", "kind": "stat", "stat": stat, "tiers": tiers,
                  "desc": desc, "emblem": emb})
    # MATCH FEATS (2026-11-22): earned in battle, like the League bonuses - every bonus has a medal. Match medals only
    # count in games the player WINS (GameState.record_medal_match). "bonus:<id>:<tier>" = that League bonus reached
    # that tier in one game (League_Config.json ids, tier 1-based); "best:" = best single game; "total:" = running total.
    won = "\n• Only counts in matches you win"
    feats_tiered = [
        ("prizes", "Prize Hunter", "prizes_taken", [50, 200, 500, 1000], "Take %d Prize cards.", "glyph:prizes"),
        ("flips", "Gambler", "coin_flips", [25, 100, 200, 500, 1000], "Flip %d coins in matches.", "glyph:flips"),
        ("flawless", "Flawless Victories", "flawless_wins", [10, 25, 100, 200, 400],
         "Win %d matches without your opponent taking a single Prize card.\n• Only counts in matches where both players start with at least 4 Prize cards", "glyph:crown"),
        ("deckout", "Deck Out Wins", "deckout_wins", [5, 20, 50, 100, 250],
         "Win %d matches because your opponent ran out of cards to draw.", "glyph:deckout"),
        ("multi_ko", "Multi Knockout", "total:multi_ko_points", [10, 50, 100, 250, 500],
         "Score %d Multi Knockout points.\n• +1 for every extra Pokemon you Knock Out in a single turn (a Double Knockout is +1, a Triple Knockout +2)" + won, "glyph:multi_ko"),
        ("sniper", "Sniper", "total:sniper_kos", [10, 50, 100, 250, 500], "Knock Out %d Benched Pokemon." + won, "glyph:crosshair"),
        ("healer", "Healer", "total:healed", [250, 1000, 2000, 4000, 10000], "Heal %d damage in total." + won, "glyph:healer"),
        ("evolution", "Evolution Master", "total:evolutions", [20, 100, 250, 1000, 2500], "Evolve your Pokemon %d times." + won, "glyph:evolution"),
        ("poison_master", "Poison Master", "total:poison_kos", [5, 20, 50, 100, 250], "Knock Out %d Pokemon with Poison." + won, "glyph:poison"),
        ("burn_master", "Burn Master", "total:burn_kos", [5, 20, 50, 100, 250], "Knock Out %d Pokemon with a Burn." + won, "glyph:burn"),
        ("inflictor", "Inflictor", "total:inflicts", [25, 100, 250, 500, 1000],
         "Give your opponent's Pokemon %d Special Conditions.\n• Asleep, Confused, Paralyzed and Poisoned all count" + won, "glyph:inflictor"),
    ]
    for mid, name, stat, tiers, desc, emb in feats_tiered:
        d.append({"id": mid, "name": name, "group": "Match Feats", "kind": "stat", "stat": stat, "tiers": tiers,
                  "desc": desc, "emblem": emb})
    feats_once = [
        ("board_wipe", "Board Wipe", "bonus:board_wipe:1", "Knock Out 6 of your opponent's Pokemon in a single turn and win the match.", "glyph:board_wipe"),
        ("crazy_damage", "Crazy Damage", "bonus:damage:5", "Do 500 or more damage with a single attack and win the match.", "glyph:burst"),
        ("ultra_healer", "Ultra Healer", "bonus:healer:4", "Heal 1,000 or more damage in a single match and win it.", "glyph:heart_plus"),
        ("super_comeback", "Super Comeback", "bonus:comeback:2", "Win a match after falling 5 Prize cards behind your opponent.", "glyph:comeback"),
        ("only_one", "Only One", "bonus:only_one:1", "Win a match with only one Pokemon ever played.\n• Never put a Pokemon on your Bench (evolving it is fine)", "glyph:one"),
        ("last_resort", "Last Resort", "bonus:last_resort:1", "Win a match with your Active Pokemon on 10 HP or less and nothing on your Bench.", "glyph:last_resort"),
        ("empty_deck", "Empty Deck", "bonus:empty_deck:1", "Win a match with no cards left in your deck.", "glyph:empty_deck"),
        ("speedrun", "Speedrun", "bonus:speedrun:1", "Win a match within 6 turns (3 each).", "glyph:bolt"),
        ("marathon", "Marathon", "bonus:marathon:1", "Win a match that lasts more than 49 turns.\n• Both players' turns count", "glyph:hourglass"),
        ("hitting_yourself", "Why are you hitting yourself?", "bonus:confusion_master:1",
         "Win a match in which one of your opponent's Pokemon Knocks itself Out with Confusion.", "glyph:dizzy"),
        ("no_way", "There's no way...", "best:flips_heads", "Flip 25 heads in a single match." + won, "glyph:coin_h"),
        ("rigged", "This game is rigged...", "best:flips_tails", "Flip 25 tails in a single match." + won, "glyph:coin_t"),
    ]
    for mid, name, stat, desc, emb in feats_once:
        tiers = [25] if stat.startswith("best:") else [1]
        d.append({"id": mid, "name": name, "group": "Match Feats", "kind": "stat", "stat": stat, "tiers": tiers,
                  "desc": desc, "emblem": emb, "metal": "platinum"})
    for t in TYPES:
        other = ("Deck CANNOT contain any other Pokemon types" + (" (including Colorless Pokemon)" if t != "Colorless" else ""))
        d.append({"id": "type_" + t.lower(), "name": t + " Master", "group": "Type Mastery", "kind": "archetype",
                  "key": "type:" + t, "tiers": [5, 10, 25, 50],
                  "desc": "Win %d matches with a deck of only " + t + " type Pokemon\n"
                          "• Deck MUST contain at least " + str(MIN_NAMES) + " different Pokemon (with different names)\n"
                          "• " + other + "\n"
                          "• Deck CAN contain any Energy cards\n"
                          "• Pokemon attack requirements do not matter",
                  "emblem": ("glyph:fist" if t == "Fighting" else "glyph:moon" if t == "Darkness" else "energy:" + t.lower())})
    for prefix, disp, badge in LEADERS:
        d.append({"id": "leader_" + prefix.lower().replace(". ", "_").replace(" ", "_"), "name": disp + " Master",
                  "group": "Gym Leaders", "kind": "archetype", "key": "leader:" + prefix, "tiers": [1, 5, 10, 20],
                  "desc": "Win %d matches with a deck of ONLY " + prefix + "'s Pokemon\n"
                          "• Deck MUST contain at least " + str(MIN_NAMES) + " different Pokemon (with different names)\n"
                          "• Deck CANNOT contain any Pokemon without " + prefix + " in its name\n"
                          "• Pokemon and Energy types do not matter\n"
                          "• Trainer card names do not matter",
                  "emblem": "badge:" + badge})
    one = [
        ("elders", "Elder Challenge Champion", "elders", "Beat all three Card Elders.", "glyph:three"),
        ("gym_challenge", "Gym Hero Challenge Champion", "gym_challenge", "Complete the Gym Hero Challenge.", "glyph:pokeball_crown"),
        ("nemesis", "Nemesis", "nemesis", "Beat the same opponent 10 times.", "glyph:fists"),
    ]
    for mid, name, stat, desc, emb in one:
        d.append({"id": mid, "name": name, "group": "Feats", "kind": "stat", "stat": stat, "tiers": [1],
                  "desc": desc, "emblem": emb, "metal": "platinum"})
    # SECRET: not on the chart (or counted in its total) until earned - god packs stay a rumour
    d.append({"id": "super_lucky", "name": "It's real!", "group": "Feats", "kind": "stat", "stat": "god_packs", "tiers": [1],
              "desc": "Opened a pack of cards containing all rare cards!", "emblem": "glyph:godpack", "metal": "platinum", "hidden": True})
    return d


# ───────────────────────────── rendering ─────────────────────────────

def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def ink_from_image(path, box=18, dark_only=False):
    im = Image.open(path).convert("RGBA")
    a, lum = im.getchannel("A"), im.convert("L")
    w, h = im.size
    pa, pl = a.load(), lum.load()
    ink = Image.new("L", (w, h))
    pi = ink.load()
    for y in range(h):
        for x in range(w):
            if dark_only:
                pi[x, y] = 255 if (pa[x, y] > 128 and pl[x, y] < 50) else 0
            else:
                pi[x, y] = int(255 * (pa[x, y] / 255.0) * (1 - pl[x, y] / 255.0))
    bb = ink.point(lambda v: 255 if v > 90 else 0).getbbox()
    if bb:
        ink = ink.crop(bb)
    w, h = ink.size
    k = box / max(w, h)
    nw, nh = max(1, round(w * k)), max(1, round(h * k))
    ink = ink.resize((nw, nh), Image.LANCZOS)
    m = Image.new("L", (S, S), 0)
    m.paste(ink, ((S - nw) // 2, (S - nh) // 2 + 1))
    return m.point(lambda v: 255 if v > 105 else 0)


def grid_mask(rows):
    """A hand-drawn medal_emblems.E grid ("#" = engraved) placed in the middle of the 32x32 coin."""
    h, w = len(rows), len(rows[0])
    ox, oy = (S - w) // 2, (S - h) // 2
    m = Image.new("L", (S, S), 0)
    px = m.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "#":
                px[ox + x, oy + y] = 255
    return m


def emblem_mask(spec):
    """Every emblem is a hand-drawn pixel grid in medal_emblems.py. Only a NEW set / energy that has no grid yet
    falls back to tracing its icon (rough - draw it a grid)."""
    if spec in EMBLEMS:
        return grid_mask(EMBLEMS[spec])
    kind, _, name = spec.partition(":")
    print("  ! no hand-drawn grid for %s in medal_emblems.py - %s" % (spec, "tracing its icon" if kind in ("set", "energy") else "cannot draw it"))
    if kind == "set":
        return ink_from_image(os.path.join(SET_ICONS, "icon_%s.png" % name))
    if kind == "energy":
        return ink_from_image(os.path.join(ENERGY_ICONS, "icon_%s.png" % name), box=19, dark_only=True)
    raise ValueError("medal emblem %s needs a grid in Scripts/Utilities/medal_emblems.py" % spec)


def render(metal, mask):
    studs = metal.endswith("+")
    r = [rgb(c) for c in METALS[metal.rstrip("+")]]
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px, mp = im.load(), mask.load()
    for y in range(S):
        for x in range(S):
            dx, dy = x - 15.5, y - 15.5
            d = math.hypot(dx, dy)
            if d > 15.3 or abs(dx) + abs(dy) > 21.5:
                continue
            nd = (-dx - dy) / (d * 1.414) if d else 0
            if d > 14.2:
                c = r[0]
            elif d > 12.9:
                c = r[4] if nd > 0.15 else (r[1] if nd < -0.2 else r[3])
            elif d > 11.8:
                c = r[1]
            else:
                t = (-dx - dy) / 24
                c = r[2]
                if t > 0.28 or (t > 0.18 and (x + y) % 2 == 0):
                    c = r[3]
                if t < -0.38 or (t < -0.28 and (x + y) % 2 == 0):
                    c = r[1]
                if mp[x, y]:
                    c = r[0]
                elif x > 0 and y > 0 and mp[x - 1, y - 1]:
                    c = r[4]
            if studs and 12.9 < d <= 14.2:
                ang = math.degrees(math.atan2(dy, dx)) % 360
                if int(ang / 22.5) % 2 == 0:
                    c = r[0]
            px[x, y] = c + (255,)
    return im


def build(only_missing=False):
    with open(JSON_PATH, encoding="utf8") as f:
        defs = json.load(f)
    os.makedirs(OUT_DIR, exist_ok=True)
    n = 0
    for m in defs:
        tiers = m.get("tiers", [])
        mask = emblem_mask(m["emblem"])
        if len(tiers) <= 1:
            files = [(m["id"] + ".png", m.get("metal", "gold"))]
        else:
            metals = TIER_METALS[len(tiers)]
            files = [("%s_%d.png" % (m["id"], i + 1), metals[i]) for i in range(len(tiers))]
        for fname, metal in files:
            path = os.path.join(OUT_DIR, fname)
            if only_missing and os.path.exists(path):
                continue
            render(metal, mask).save(path)
            n += 1
    print("rendered", n, "medal PNGs into", OUT_DIR)


if __name__ == "__main__":
    if "--init-json" in sys.argv:
        with open(JSON_PATH, "w", encoding="utf8") as f:
            json.dump(definitions(), f, indent=1, ensure_ascii=False)
        print("wrote", JSON_PATH, len(definitions()), "medals")
    else:
        build("--only-missing" in sys.argv)
