"""Medal art + definitions builder.

    python Scripts/Utilities/medal_art_build.py --init-json   # (re)write NPC_and_Opponent_Data/Medals.json
    python Scripts/Utilities/medal_art_build.py               # render Image_Assets/Medals/*.png from Medals.json

Medals.json is the single list the game reads (Scripts/Global_Scripts/Medal_Data.gd). Add a medal = add one entry.
The PNGs rendered here are PLACEHOLDERS: pixel-art coins (32x32, one metal each, symbol engraved). Drop a hand-drawn
32x32 PNG with the same file name into Image_Assets/Medals/ to replace one - no code change. Naming:
    single-grade medal      <id>.png
    tiered medal            <id>_<n>.png   (n = 1 .. number of tiers; the game shades the locked slot itself)
Re-running this script overwrites EVERY png - copy your own art elsewhere first or pass --only-missing.
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont

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


MIN_NAMES = 4   # a type / leader deck needs at least this many DIFFERENT named Pokemon


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
        ("flips", "Gambler", "coin_flips", [25, 100, 200, 500, 1000], "Flip %d coins in matches.", "glyph:flips"),
        ("prizes", "Prize Hunter", "prizes_taken", [50, 200, 500, 1000], "Take %d Prize cards.", "glyph:prizes"),
        ("flawless", "Flawless Victories", "flawless_wins", [5, 20, 50, 100, 250],
         "Win %d matches without your opponent taking a single Prize card.\n• Only counts in matches where both players start with 6 Prize cards", "glyph:crown"),
        ("deckout", "Deck Out Wins", "deckout_wins", [5, 20, 50, 100, 250],
         "Win %d matches because your opponent ran out of cards to draw.", "glyph:deckout"),
        ("coins", "Coin Collector", "coins_owned", [10, 50, 100, 200, "all"], "Collect %d coins.", "glyph:coin"),
        ("costumes", "Wardrobe", "costumes_owned", [5, 20, 50, 100, "all"], "Collect %d costumes.", "glyph:costume"),
        ("sleeves", "Sleeve Collector", "sleeves_owned", [10, 25, 75, 150, "all"], "Collect %d sleeves.", "glyph:sleeve"),
        ("fish_total", "Angler", "fish_caught", [10, 50, 100, 250, 500], "Catch %d fish.", "glyph:fish"),
        ("fish_species", "Marine Biologist", "fish_species", [5, 10, 20, 50, "all"], "Catch %d different species of fish.", "glyph:fish_school"),
    ]
    for mid, name, stat, tiers, desc, emb in mil:
        d.append({"id": mid, "name": name, "group": "Milestones", "kind": "stat", "stat": stat, "tiers": tiers,
                  "desc": desc, "emblem": emb})
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
    d.append({"id": "super_lucky", "name": "Super Lucky!", "group": "Feats", "kind": "stat", "stat": "god_packs", "tiers": [1],
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


def draw_mask(fn, ss=8):
    big = Image.new("L", (S * ss, S * ss), 0)
    fn(ImageDraw.Draw(big), ss)
    return big.resize((S, S), Image.LANCZOS).point(lambda v: 255 if v > 110 else 0)


def poly(d, ss, pts, fill=255):
    d.polygon([(x * ss, y * ss) for x, y in pts], fill=fill)


def circ(d, ss, cx, cy, r, fill=255):
    d.ellipse([(cx - r) * ss, (cy - r) * ss, (cx + r) * ss, (cy + r) * ss], fill=fill)


def rect(d, ss, x0, y0, x1, y1, fill=255):
    d.rectangle([x0 * ss, y0 * ss, x1 * ss, y1 * ss], fill=fill)


def octagon(cx, cy, r):
    return [(cx + r * math.cos(math.radians(22.5 + 45 * i)), cy + r * math.sin(math.radians(22.5 + 45 * i))) for i in range(8)]


def star(cx, cy, ro, ri):
    pts = []
    for i in range(10):
        a = math.radians(-90 + 36 * i)
        r = ro if i % 2 == 0 else ri
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def letter(ch, size):
    def fn(d, ss):
        f = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", int(size * ss))
        d.text((16 * ss, 16.5 * ss), ch, font=f, fill=255, anchor="mm")
    return fn


def badge_cascade(d, ss):
    poly(d, ss, [(16, 6), (22, 15), (22, 18), (10, 18), (10, 15)]); circ(d, ss, 16, 18, 6.2)
    d.line([(13.5 * ss, 17 * ss), (14.5 * ss, 21 * ss)], fill=0, width=int(1.1 * ss))


def badge_rainbow(d, ss):
    for i in range(6):
        a = math.radians(60 * i - 90)
        circ(d, ss, 16 + 6.2 * math.cos(a), 16 + 6.2 * math.sin(a), 3.6)
    circ(d, ss, 16, 16, 2.7, 0); circ(d, ss, 16, 16, 1.3)


def badge_soul(d, ss):
    circ(d, ss, 12.7, 13, 4.4); circ(d, ss, 19.3, 13, 4.4)
    poly(d, ss, [(8.6, 14.6), (23.4, 14.6), (16, 24.5)])
    d.line([(16 * ss, 14 * ss), (16 * ss, 24 * ss)], fill=0, width=int(1.1 * ss))


def badge_volcano(d, ss):
    poly(d, ss, [(6, 6), (11, 11), (13.5, 6), (16, 11), (18.5, 6), (21, 11), (26, 6), (24.5, 15), (22, 24), (16, 27), (10, 24), (7.5, 15)])
    poly(d, ss, [(16, 15), (19, 19.5), (16, 24), (13, 19.5)], 0)


def badge_earth(d, ss):
    rect(d, ss, 15, 13, 17, 27)
    d.ellipse([7 * ss, 17 * ss, 16 * ss, 23 * ss], fill=255)
    d.ellipse([16 * ss, 17 * ss, 25 * ss, 23 * ss], fill=255)
    for cx, cy in [(16, 8), (12.5, 11), (19.5, 11), (16, 12.5), (22.5, 13.5)]:
        poly(d, ss, [(cx + 3 * math.cos(math.radians(60 * i)), cy + 3 * math.sin(math.radians(60 * i))) for i in range(6)])


def g_crown(d, ss):
    poly(d, ss, [(7, 22), (6, 11), (12, 16), (16, 8), (20, 16), (26, 11), (25, 22)]); rect(d, ss, 7, 23.5, 25, 26)


def g_trophy(d, ss):
    poly(d, ss, [(9, 7), (23, 7), (23, 14), (16, 20), (9, 14)])
    d.arc([3 * ss, 8 * ss, 11 * ss, 16 * ss], 90, 270, fill=255, width=int(1.6 * ss))
    d.arc([21 * ss, 8 * ss, 29 * ss, 16 * ss], 270, 90, fill=255, width=int(1.6 * ss))
    rect(d, ss, 14.5, 19, 17.5, 23); rect(d, ss, 11, 23.5, 21, 26)


def g_cards(d, ss):
    rect(d, ss, 9, 11, 20, 26); d.rectangle([13 * ss, 6 * ss, 24 * ss, 21 * ss], outline=255, width=int(1.6 * ss))


def g_cash(d, ss):
    d.ellipse([7 * ss, 7 * ss, 25 * ss, 25 * ss], outline=255, width=int(1.8 * ss))
    f = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", int(14 * ss))
    d.text((16 * ss, 16.5 * ss), "$", font=f, fill=255, anchor="mm")


def g_packs(d, ss):
    rect(d, ss, 9, 6, 23, 26)
    for i in range(7):
        x = 9 + i * 2.2
        poly(d, ss, [(x, 6), (x + 1.1, 4.5), (x + 2.2, 6)])
    rect(d, ss, 12, 12, 20, 21, 0); circ(d, ss, 16, 16.5, 2.2)


def g_flips(d, ss):
    d.ellipse([7 * ss, 7 * ss, 25 * ss, 25 * ss], outline=255, width=int(1.8 * ss))
    poly(d, ss, star(16, 16, 5.5, 2.4))


def g_prizes(d, ss):
    rect(d, ss, 9, 5, 23, 27); poly(d, ss, star(16, 16, 5.5, 2.4), 0)


def g_godpack(d, ss):       # a booster with a star burst cut into it
    rect(d, ss, 8, 5, 24, 27)
    for i in range(8):
        x = 8 + i * 2.0
        poly(d, ss, [(x, 5), (x + 1.0, 3.5), (x + 2.0, 5)])
    poly(d, ss, star(16, 16.5, 6.2, 2.6), 0)
    poly(d, ss, star(16, 16.5, 3.6, 1.5))


def g_sleeve(d, ss):
    rect(d, ss, 9, 5, 23, 27); rect(d, ss, 11, 8, 21, 20, 0); rect(d, ss, 11, 22, 21, 24)


def g_costume(d, ss):
    poly(d, ss, [(11, 6), (5, 11), (8.5, 14.5), (11, 13), (11, 26), (21, 26), (21, 13), (23.5, 14.5), (27, 11), (21, 6), (19, 8.5), (13, 8.5)])


def g_coin(d, ss):
    circ(d, ss, 16, 16, 10); circ(d, ss, 16, 16, 6.2, 0); circ(d, ss, 16, 16, 3.4)


def g_swords(d, ss):
    d.line([(7 * ss, 7 * ss), (25 * ss, 25 * ss)], fill=255, width=int(3 * ss))
    d.line([(25 * ss, 7 * ss), (7 * ss, 25 * ss)], fill=255, width=int(3 * ss))
    rect(d, ss, 5, 5, 10, 8); rect(d, ss, 22, 5, 27, 8)


def g_zero(d, ss):
    d.ellipse([10 * ss, 5 * ss, 22 * ss, 27 * ss], outline=255, width=int(3.4 * ss))


def g_deckout(d, ss):
    d.rectangle([9 * ss, 5 * ss, 23 * ss, 27 * ss], outline=255, width=int(2 * ss))
    d.line([(12 * ss, 11 * ss), (20 * ss, 21 * ss)], fill=255, width=int(2.2 * ss))
    d.line([(20 * ss, 11 * ss), (12 * ss, 21 * ss)], fill=255, width=int(2.2 * ss))


def badge_boulder(d, ss):   # grey faceted octagon: outer ring, inner octagon, diagonal facet cuts
    poly(d, ss, octagon(16, 16, 11)); poly(d, ss, octagon(16, 16, 7.8), 0); poly(d, ss, octagon(16, 16, 5.6))
    for i in range(8):
        a = math.radians(22.5 + 45 * i)
        d.line([((16 + 5.6 * math.cos(a)) * ss, (16 + 5.6 * math.sin(a)) * ss), ((16 + 9.4 * math.cos(a)) * ss, (16 + 9.4 * math.sin(a)) * ss)], fill=255, width=int(1.4 * ss))


def badge_thunder(d, ss):   # sunburst: 12 spikes round a ring and a hub
    pts = []
    for i in range(24):
        a = math.radians(-90 + 15 * i)
        r = 11.5 if i % 2 == 0 else 8.2
        pts.append((16 + r * math.cos(a), 16 + r * math.sin(a)))
    poly(d, ss, pts); circ(d, ss, 16, 16, 5.6, 0); circ(d, ss, 16, 16, 3.2)


def badge_marsh(d, ss):     # a disc with a carved spiral
    circ(d, ss, 16, 16, 10.5)
    pts = []
    for i in range(0, 120):
        t = i / 119.0
        a = 3.2 * math.pi * 2 * t
        r = 1.2 + 7.6 * t
        pts.append(((16 + r * math.cos(a)) * ss, (16 + r * math.sin(a)) * ss))
    d.line(pts, fill=0, width=int(1.7 * ss))


def g_fist(d, ss):          # raised fist: four knuckles with short finger slits, a thumb across the front
    d.rounded_rectangle([6.5 * ss, 11.5 * ss, 25.5 * ss, 27 * ss], radius=int(3.5 * ss), fill=255)
    for cx in (9.8, 14.6, 19.4, 23.8):
        circ(d, ss, cx, 11.4, 2.9)
    for x in (12.2, 17.0, 21.6):
        d.line([(x * ss, 10.5 * ss), (x * ss, 16.5 * ss)], fill=0, width=int(1.4 * ss))
    d.arc([6.5 * ss, 14 * ss, 22 * ss, 26 * ss], 90, 270, fill=0, width=int(1.5 * ss))
    d.line([(14 * ss, 19 * ss), (21 * ss, 19 * ss)], fill=0, width=int(1.4 * ss))


def g_moon(d, ss):          # clean crescent
    circ(d, ss, 15, 16, 10.5); circ(d, ss, 20, 13.5, 8.6, 0)
    poly(d, ss, star(23.5, 20.5, 2.6, 1.1))


def g_drumstick(d, ss):     # round meat, thin bone, two knobs
    circ(d, ss, 19.5, 12, 8.4)
    d.line([(14.5 * ss, 17.5 * ss), (7.5 * ss, 24.5 * ss)], fill=255, width=int(2.6 * ss))
    circ(d, ss, 6.2, 24.2, 2.4); circ(d, ss, 8.4, 26.8, 2.4)


def g_three(d, ss):         # the three Card Elders: three triangles
    poly(d, ss, [(16, 5.5), (21.2, 14.5), (10.8, 14.5)])
    poly(d, ss, [(9, 16.5), (14.2, 25.5), (3.8, 25.5)])
    poly(d, ss, [(23, 16.5), (28.2, 25.5), (17.8, 25.5)])


def g_pokeball_crown(d, ss):
    d.ellipse([7 * ss, 11 * ss, 25 * ss, 29 * ss], outline=255, width=int(2.2 * ss))
    d.line([(7.5 * ss, 20 * ss), (24.5 * ss, 20 * ss)], fill=255, width=int(2.2 * ss))
    circ(d, ss, 16, 20, 3.2); circ(d, ss, 16, 20, 1.4, 0)
    poly(d, ss, [(9.5, 11), (8.5, 3.5), (12.8, 7), (16, 2.5), (19.2, 7), (23.5, 3.5), (22.5, 11)])


def g_fists(d, ss):         # two small fighters squaring up: arms reach in but never touch
    k = 0.78
    def P(x, y, m):
        return ((16 + (x - 16) * k) if m == 1 else (16 - (x - 16) * k), 16 + (y - 16) * k)
    def fighter(m):
        hx, hy = P(8.5, 8.5, m)
        circ(d, ss, hx, hy, 2.8 * k)
        for (x0, y0, x1, y1, w) in ((8.5, 11.5, 9.5, 19.5, 2.6), (9, 13.5, 13.0, 12.8, 2.2), (9.5, 19.5, 6, 27, 2.4), (9.5, 19.5, 13, 27, 2.4)):
            a = P(x0, y0, m); b = P(x1, y1, m)
            d.line([(a[0] * ss, a[1] * ss), (b[0] * ss, b[1] * ss)], fill=255, width=int(w * k * ss))
    fighter(1); fighter(-1)


def _fish(d, ss, cx, cy, s):
    d.ellipse([(cx - 8 * s) * ss, (cy - 5 * s) * ss, (cx + 5 * s) * ss, (cy + 5 * s) * ss], fill=255)
    poly(d, ss, [(cx + 3.5 * s, cy), (cx + 10 * s, cy - 5 * s), (cx + 10 * s, cy + 5 * s)])
    circ(d, ss, cx - 4.2 * s, cy - 1.4 * s, 1.1 * s, 0)


def g_fish(d, ss):
    _fish(d, ss, 14, 16, 1.2)


def g_fish_school(d, ss):
    _fish(d, ss, 12, 11, 0.8); _fish(d, ss, 17, 21, 0.8); _fish(d, ss, 22, 10.5, 0.55)


def g_moneybag(d, ss):
    circ(d, ss, 16, 20, 8.2)
    poly(d, ss, [(11.5, 12.5), (20.5, 12.5), (18.5, 15), (13.5, 15)])
    d.rectangle([12 * ss, 8.5 * ss, 20 * ss, 11.5 * ss], fill=255)
    f = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", int(11 * ss))
    d.text((16 * ss, 20.5 * ss), "$", font=f, fill=0, anchor="mm")


BADGES = {"boulder": badge_boulder, "cascade": badge_cascade, "thunder": badge_thunder, "rainbow": badge_rainbow,
          "marsh": badge_marsh, "volcano": badge_volcano, "earth": badge_earth, "soul": badge_soul, "letter_r": letter("R", 22)}
GLYPHS = {"fist": g_fist, "moon": g_moon, "drumstick": g_drumstick, "three": g_three, "pokeball_crown": g_pokeball_crown,
          "fists": g_fists, "godpack": g_godpack, "fish": g_fish, "fish_school": g_fish_school, "moneybag": g_moneybag, "crown": g_crown, "trophy": g_trophy, "cards": g_cards, "cash": g_cash, "packs": g_packs, "flips": g_flips,
          "prizes": g_prizes, "sleeve": g_sleeve, "costume": g_costume, "coin": g_coin, "swords": g_swords, "zero": g_zero,
          "deckout": g_deckout}


def emblem_mask(spec):
    kind, _, name = spec.partition(":")
    if kind == "set":
        return ink_from_image(os.path.join(SET_ICONS, "icon_%s.png" % name))
    if kind == "energy":
        return ink_from_image(os.path.join(ENERGY_ICONS, "icon_%s.png" % name), box=19, dark_only=True)
    if kind == "badge":
        return draw_mask(BADGES[name])
    if kind == "glyph":
        return draw_mask(GLYPHS[name])
    raise ValueError(spec)


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
