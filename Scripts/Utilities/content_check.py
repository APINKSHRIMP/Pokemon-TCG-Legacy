"""
content_check.py  --  "check my content"

One command that checks everything written BY HAND for the overworld: opponents,
NPCs, shops, decks, rewards, schedule rules and dialogue. Run it after every
authoring session:

    py -3 -I Scripts/Utilities/content_check.py            (from the project folder)
    py -3 -I Scripts/Utilities/content_check.py --todo     (also print the full TO-DO list)

It only READS. Nothing in the data is changed.

Output sections (also written to audit_out/content_check.txt):
  ERRORS   something that will break, or silently fail, in the game. Fix these.
  WARNINGS legal but probably not what you meant (mixed-era deck, a coin given twice...).
  TO-DO    placeholders still to fill (REPLACEMUSIC, missing coin art, decks with no
           opponent, empty rank rewards...). Counts always; the full list with --todo.

Every rule below mirrors the code that reads the field -- the file/function is named
next to each check, so if the game changes, update the check beside it.

Exit code: 0 = no errors, 1 = errors found.
"""
import difflib
import json
import os
import re
import sys
from collections import Counter, defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "NPC_and_Opponent_Data")
CHAR_DIR = os.path.join(DATA, "Characters")
DECK_DIR = os.path.join(DATA, "Opponent_Deck_Data")
CARD_DIR = os.path.join(ROOT, "Card_Set_Data")
IMG = os.path.join(ROOT, "Image_Assets")
COIN_DIR = os.path.join(IMG, "Coins")
BATTLE_SPRITE_DIR = os.path.join(IMG, "Character_Sprites", "In_Battle_Sprites")
OVERWORLD_SPRITE_DIR = os.path.join(IMG, "Character_Sprites", "Overworld_Sprites")
TALKING_SPRITE_DIR = os.path.join(IMG, "Character_Sprites", "Talking_Sprites")
SLEEVE_SMALL_DIR = os.path.join(IMG, "Sleeves", "small")
PACK_DIR = os.path.join(IMG, "Packs")
ITEM_DIR = os.path.join(IMG, "Assorted_Extras")
BGM_DIR = os.path.join(ROOT, "Audio", "BGM")
OUT_DIR = os.path.join(ROOT, "audit_out")

# The seven rated decks the user decided (2026-11-23) will NEVER get an opponent.
NEVER_OPPONENT_DECKS = {"Conversion 2", "Conversion 3", "Dark Cuties", "Cuties Twoties",
                        "Sleepy Time", "Beach Pals", "Gigashock"}

# Doors that point at a scene that doesn't exist ON PURPOSE (inert until a later area).
INERT_DOOR_TARGETS = {("TrainStation", "Aurum_Town"), ("TrainStation", "Town_3"),
                      ("Fish_Shop", "Fish_Shop_Upstairs")}

# Characters deliberately defined on more than one map (same person, different place).
MULTI_MAP_OK = {"Card Elder Hamish", "Card Elder Rayne", "Card Elder Waverly", "Old Guy Neighbour"}

# Card set -> generation (memory: deck era rules). Bridging sets mix with anything.
ERA = {}
for s in ["base1", "base2", "base3", "base5", "gym1", "gym2"]:
    ERA[s] = "base"
for s in ["neo1", "neo2", "neo3", "neo4"]:
    ERA[s] = "neo"
for s in ["ecard1", "ecard2", "ecard3"]:
    ERA[s] = "e-card"
for i in range(1, 17):
    ERA["ex%d" % i] = "ex"
ERA["np"] = "ex"
BRIDGE_SETS = {"basep", "si1", "pop1", "pop2", "pop3", "pop4", "pop5"}

# Dialogue tokens DynamicMessageBox.set_body_text() substitutes (Dynamic_Message_Box.gd).
DIALOGUE_TOKENS = {"[TIME]", "[time]", "[NAME]"}
# Speech emotes, only at the very start/end of a line (MapManager.split_emote_tags).
EMOTE_TAGS = {"[!]", "[?]"}
# Movement patterns World_Object_Base.gd understands.
MOVE_PATTERNS = {"idle_random", "idle_cycle", "route", "random_wander"}
for d in ("down", "up", "left", "right"):
    MOVE_PATTERNS.add("idle_" + d)
    MOVE_PATTERNS.add("idle_" + d + "_random")
# Gift types MapManager._give_gift() handles ("pack_of_cards" only warns -> not usable).
GIFT_TYPES = {"card", "coin", "cash", "energy_style", "costume", "sleeve", "available_pack", "pack"}
SAYS_KEYS = {"meet", "repeat", "first_win", "rematch_win", "loss"}
TIME_LETTERS = set("MAENB")


# ----------------------------------------------------------------------------------------
class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.todo = defaultdict(list)

    def err(self, where, msg):
        self.errors.append("%s: %s" % (where, msg))

    def warn(self, where, msg):
        self.warnings.append("%s: %s" % (where, msg))

    def td(self, group, item):
        self.todo[group].append(item)


R = Report()


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def files_in(folder, exts):
    """name-without-extension -> exact file name, for files in folder with one of exts.
    .import / .remap siblings are ignored (they are Godot's bookkeeping)."""
    out = {}
    if not os.path.isdir(folder):
        return out
    for fn in os.listdir(folder):
        base, ext = os.path.splitext(fn)
        if ext.lower() in exts:
            out[base] = fn
    return out


def suggest(name, pool, cutoff=0.8):
    """' (did you mean 'X'?)' for the closest name in pool, or ''."""
    hits = difflib.get_close_matches(str(name), list(pool), n=1, cutoff=cutoff)
    return " (did you mean '%s'?)" % hits[0] if hits else ""


def lower_map(d):
    return {k.lower(): k for k in d}


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


# ---------------------------------------------------------------------- reference data
def load_cards():
    cards = {}
    for fn in os.listdir(CARD_DIR):
        if not fn.endswith(".json") or fn == "pack_prices.json":
            continue
        data = load_json(os.path.join(CARD_DIR, fn))
        if not isinstance(data, list):
            continue
        for c in data:
            if isinstance(c, dict) and "id" in c:
                cards[c["id"]] = c
    return cards


CARDS = load_cards()
CONST = load_json(os.path.join(DATA, "All_NPC_Constant_Data.json"))
C_OPP = CONST.get("opponents", {})
C_NPC = CONST.get("npcs", {})
COINS = files_in(COIN_DIR, {".png"})
BATTLE_SPRITES = files_in(BATTLE_SPRITE_DIR, {".png"})
BATTLE_SPRITES_LC = lower_map(BATTLE_SPRITES)
OVERWORLD_SPRITES = files_in(OVERWORLD_SPRITE_DIR, {".png"})
SLEEVES_SMALL = files_in(SLEEVE_SMALL_DIR, {".jpg"})
PACKS = files_in(PACK_DIR, {".png"})
ITEMS = files_in(ITEM_DIR, {".png"})
BGM = files_in(BGM_DIR, {".ogg", ".mp3", ".wav"})
DECKS = files_in(DECK_DIR, {".json"})
DECKS_LC = lower_map(DECKS)

_mbt = read(os.path.join(ROOT, "Scripts", "Global_Scripts", "Message_Box_Theme.gd"))
_themes_block = _mbt[_mbt.find("const THEMES"):]
_themes_block = _themes_block[:_themes_block.find("\n}")]
MESSAGE_COLOURS = set(re.findall(r'^\s*"([a-z_]+)"\s*:', _themes_block, re.M))

_me = read(os.path.join(ROOT, "Scripts", "Main_Match_Gameplay_Scripts", "Match_Effects.gd"))
_kt = _me[_me.find("const KNOWN_TYPES"):]
_kt = _kt[:_kt.find("]")]
MATCH_EFFECT_TYPES = set(re.findall(r'"([a-z_]+)"', _kt))

_dvh = read(os.path.join(ROOT, "Scripts", "Global_Scripts", "Deck_Validation_Helper.gd"))
RESTRICTION_KEYS = set(re.findall(r'restrictions\.get\("([a-z_0-9]+)"', _dvh)) | \
    set(re.findall(r'^#\s+"([a-z_0-9]+)":', _dvh, re.M))

# Every flag the game can set: GameState.set_flag(...) with a literal or a *FLAG* constant.
KNOWN_FLAGS = set()
_flag_consts = {}
for dp, _dn, fns in os.walk(os.path.join(ROOT, "Scripts")):
    for fn in fns:
        if fn.endswith(".gd"):
            t = read(os.path.join(dp, fn))
            for name, val in re.findall(r'const\s+(\w*FLAG\w*)\s*(?::\s*\w+\s*)?:?=\s*"([^"]+)"', t):
                _flag_consts[name] = val
            KNOWN_FLAGS.update(re.findall(r'set_flag\(\s*"([^"]+)"', t))
            for name in re.findall(r'set_flag\(\s*(?:[\w]+\.)*(\w*FLAG\w*)', t):
                KNOWN_FLAGS.add(("CONST", name))
KNOWN_FLAGS = {(_flag_consts.get(f[1], None) if isinstance(f, tuple) else f) for f in KNOWN_FLAGS}
# GameState.OPPONENT_FLAG_UNLOCKS: {"Opponent": FLAG_CONST or "flag"} raised by mark_opponent_beaten().
_gs = read(os.path.join(ROOT, "Scripts", "Global_Scripts", "Game_State_Script.gd"))
_ofu = _gs[_gs.find("const OPPONENT_FLAG_UNLOCKS"):]
_ofu = _ofu[:_ofu.find("}")]
for _v in re.findall(r':\s*([A-Z_][A-Z0-9_]*|"[^"]+")', _ofu):
    KNOWN_FLAGS.add(_v.strip('"') if _v.startswith('"') else _flag_consts.get(_v))
KNOWN_FLAGS.discard(None)


# ---------------------------------------------------------------------- helpers
def card_list(raw):
    return [p.strip() for p in str(raw).split(",") if p.strip()]


def check_card_id(where, cid):
    """Game_State.give_cards() lowercases the set prefix itself, but an id that doesn't
    exist after that is a card the player never receives."""
    if cid in CARDS:
        return True
    prefix, _, num = cid.partition("-")
    fixed = prefix.lower() + "-" + num
    if fixed in CARDS:
        R.warn(where, "card id '%s' has a capitalised set prefix (works, but write '%s')" % (cid, fixed))
        return True
    R.err(where, "card id '%s' does not exist in Card_Set_Data" % cid)
    return False


def check_coin(where, name, todo_group="Coin rewards with no art"):
    if name == "REPLACECOIN":
        R.td("REPLACECOIN placeholders", where)
        return
    if name in COINS:
        return
    near = [c for c in COINS if c.lower() == name.lower()]
    if near:
        R.err(where, "coin '%s' differs only in capitals from the file '%s.png' (fails in an exported build)" % (name, near[0]))
    elif suggest(name, COINS, 0.85):
        R.err(where, "coin '%s' has no art%s" % (name, suggest(name, COINS, 0.85)))
    else:
        R.td(todo_group, "%s -> '%s' (no Image_Assets/Coins/%s.png%s)" % (where, name, name, suggest(name, COINS, 0.6)))


def check_costume(where, name):
    # GameState lowercases both sides when matching costumes (add_costume_to_collection).
    base = name[:-4] if name.lower().endswith(".png") else name
    if base.lower() not in BATTLE_SPRITES_LC:
        R.err(where, "costume '%s' has no In_Battle_Sprites image%s" % (name, suggest(base, BATTLE_SPRITES)))


def check_sleeve(where, name):
    if name not in SLEEVES_SMALL:
        near = [s for s in SLEEVES_SMALL if s.lower() == name.lower()]
        if near:
            R.err(where, "sleeve '%s' differs in capitals from '%s'" % (name, near[0]))
        else:
            R.err(where, "sleeve '%s' has no Image_Assets/Sleeves/small/%s.jpg%s" % (name, name, suggest(name, SLEEVES_SMALL)))


def check_pack(where, art):
    if art not in PACKS:
        R.err(where, "pack '%s' has no Image_Assets/Packs/%s.png (the outro skips it)%s" % (art, art, suggest(art, PACKS, 0.6)))


def check_bgm(where, track):
    track = str(track).strip()
    if track in ("", "REPLACEMUSIC", "TEST"):
        R.td("Opponents with no real music (REPLACEMUSIC)", where)
        return
    if track not in BGM:
        R.err(where, "music '%s' is not a file in Audio/BGM (plays the normal battle theme instead)%s" % (track, suggest(track, BGM, 0.6)))


def check_text(where, text):
    if not isinstance(text, str):
        if isinstance(text, list):
            for i, t in enumerate(text):
                check_text("%s[%d]" % (where, i), t)
        return
    if text.strip() == "":
        R.warn(where, "empty line of dialogue")
        return
    body = text.strip()
    # Emotes are legal only at the very start or end (MapManager.split_emote_tags).
    for tag in EMOTE_TAGS:
        if body.startswith(tag):
            body = body[len(tag):].strip()
        if body.endswith(tag):
            body = body[:-len(tag)].strip()
    for tag in EMOTE_TAGS:
        if tag in body:
            R.err(where, "speech emote %s in the middle of a line (only works at the very start or end)" % tag)
    for tok in re.findall(r"\[[A-Za-z]+\]", body):
        if tok in DIALOGUE_TOKENS:
            continue
        if tok.lower() in ("[b]", "[i]", "[u]", "[s]", "[center]", "[right]", "[left]", "[wave]", "[shake]", "[rainbow]", "[code]"):
            continue
        R.err(where, "unknown token %s (only [TIME], [time] and [NAME] are substituted; it will show as typed)" % tok)
    # bbcode balance for the simple paired tags
    for tag in ("b", "i", "u", "s", "center", "wave", "shake", "rainbow", "color"):
        opens = len(re.findall(r"\[%s(=[^\]]*)?\]" % tag, body))
        closes = body.count("[/%s]" % tag)
        if opens != closes:
            R.err(where, "unbalanced [%s] bbcode (%d open, %d close)" % (tag, opens, closes))
    if "  " in body.replace("\n", " ").strip():
        R.warn(where, "double space in dialogue: ...%s..." % body[max(0, body.find("  ") - 20):body.find("  ") + 20])


# ---------------------------------------------------------------------- decks
DECK_USERS = defaultdict(list)


def deck_era_and_legality(deck_name, live=True):
    """Opponent_Deck_Data/<name>.json = [{count, id}]. Mirrors the deck builder
    (_get_name_group / _get_max_for_card): 60 cards, 4 per name group, δ shares the
    plain name's pool, ex is its own pool, all ★ cards share ONE copy, basic Energy free."""
    where = "deck '%s'" % deck_name
    if not live:
        where += " (used by no opponent)"
    bad = R.err if live else R.warn
    path = os.path.join(DECK_DIR, DECKS[deck_name])
    try:
        entries = load_json(path)
    except Exception as e:
        bad(where, "is not valid JSON (%s)" % e)
        return
    if not isinstance(entries, list):
        bad(where, "is not a list of {count, id}")
        return
    total = 0
    groups = Counter()
    eras = Counter()
    for e in entries:
        if not isinstance(e, dict) or "id" not in e or "count" not in e:
            bad(where, "entry %r is not {count, id}" % (e,))
            continue
        cid, n = str(e["id"]), int(e["count"])
        total += n
        if not check_card_id(where, cid):
            continue
        c = CARDS.get(cid) or CARDS.get(cid.split("-")[0].lower() + "-" + cid.split("-", 1)[1])
        sup = c.get("supertype", "")
        subs = [str(s) for s in (c.get("subtypes") or [])]
        name = c.get("name", cid)
        set_id = cid.split("-")[0].lower()
        if set_id in ERA and not (sup == "Energy" and "Basic" in subs):
            eras[ERA[set_id]] += n
        if sup == "Energy" and "Basic" in subs:
            continue
        if sup != "Pokémon":
            groups[name] += n
        elif "★" in name or name.endswith(" Star"):
            groups["__star__"] += n
        elif any(s.lower() == "ex" for s in subs):
            groups[name] += n
        else:
            groups[name[:-2] if name.endswith(" δ") else name] += n
    if total != 60:
        bad(where, "has %d cards (must be 60)" % total)
    for g, n in groups.items():
        if g == "__star__" and n > 1:
            bad(where, "has %d Pokémon ★ cards (only 1 ★ in total is allowed)" % n)
        elif g != "__star__" and n > 4:
            bad(where, "has %d copies of '%s' (max 4)" % (n, g))
    if len(eras) > 1:
        R.warn(where, "mixes generations %s (fine only for a deliberate 'fun' deck)" % dict(eras))


# ---------------------------------------------------------------------- characters
def iter_rules(body):
    yield "defaults", body
    rules = body.get("when")
    if isinstance(rules, list):
        for i, r in enumerate(rules):
            if isinstance(r, dict):
                yield "when[%d]" % i, r


def check_days(where, spec):
    if spec is None:
        return
    text = str(spec).strip()
    if text in ("", "*"):
        return
    for part in text.split(","):
        part = part.strip()
        if not re.fullmatch(r"-?\d+(-\d+)?(/\d+)?", part):
            R.err(where, "days '%s': can't read '%s' (use 3-6, 1,3,5, 2-8/2 or 4)" % (text, part))


def check_times(where, spec):
    if spec is None:
        return
    text = str(spec).strip()
    if text in ("", "*"):
        return
    letters = text.replace(",", "").replace(" ", "")
    bad = [ch for ch in letters if ch not in TIME_LETTERS]
    if bad:
        R.err(where, "times '%s': '%s' is not one of M A E N B" % (text, "".join(bad)))


ALL_OPP_NAMES = {}   # lowercase -> name (every opponent anywhere: constants + maps)
ALL_NPC_NAMES = {}


def check_requires(where, req, maps_flags_used):
    if req is None:
        return
    if isinstance(req, dict):
        for key, typ in (("all_beaten", "opp"), ("any_beaten", "opp"), ("not_all_beaten", "opp")):
            if key in req:
                for t in req[key]:
                    if str(t).lower() not in ALL_OPP_NAMES:
                        R.err(where, "requires %s names '%s', which is no opponent" % (key, t))
                return
        check_condition_dict(where, req, maps_flags_used)
        return
    text = str(req).strip()
    neg = text.startswith("not ")
    if neg:
        text = text[4:].strip()
    if ":" not in text:
        R.err(where, "requires '%s' can't be read (use 'beaten: X', 'met: X' or 'flag: x')" % req)
        return
    head, arg = [s.strip() for s in text.split(":", 1)]
    if head == "beaten":
        if arg.lower() not in ALL_OPP_NAMES:
            R.err(where, "requires 'beaten: %s' — no opponent has that name%s" % (arg, suggest(arg, ALL_OPP_NAMES.values())))
    elif head == "met":
        if arg.lower() not in ALL_NPC_NAMES and arg.lower() not in ALL_OPP_NAMES:
            R.err(where, "requires 'met: %s' — no NPC has that name%s" % (arg, suggest(arg, list(ALL_NPC_NAMES.values()) + list(ALL_OPP_NAMES.values()))))
    elif head == "flag":
        maps_flags_used.append((where, arg))
    else:
        R.err(where, "requires head '%s' is unknown (beaten / met / flag)" % head)


CONDITION_TYPES = {"opponent_defeated", "opponent_not_defeated", "all_opponents_defeated",
                   "not_all_opponents_defeated", "any_opponent_defeated", "all", "any",
                   "npc_met", "npc_not_met", "flag_set", "flag_not_set"}


def check_condition_dict(where, cond, maps_flags_used):
    """MapManager._evaluate_condition(): an unknown type is warned and treated as TRUE."""
    t = cond.get("type", "")
    if t not in CONDITION_TYPES:
        R.err(where, "condition type '%s' is unknown (MapManager treats it as always true)" % t)
        return
    if t in ("all", "any"):
        for sub in cond.get("conditions", []):
            if isinstance(sub, dict):
                check_condition_dict(where, sub, maps_flags_used)
    elif t in ("opponent_defeated", "opponent_not_defeated"):
        if str(cond.get("target", "")).lower() not in ALL_OPP_NAMES:
            R.err(where, "condition target '%s' is no opponent" % cond.get("target"))
    elif t.endswith("opponents_defeated") or t == "any_opponent_defeated":
        for x in cond.get("targets", []):
            if str(x).lower() not in ALL_OPP_NAMES:
                R.err(where, "condition target '%s' is no opponent" % x)
    elif t in ("npc_met", "npc_not_met"):
        x = str(cond.get("target", "")).lower()
        if x not in ALL_NPC_NAMES and x not in ALL_OPP_NAMES:
            R.err(where, "condition target '%s' is no NPC" % cond.get("target"))
    elif t in ("flag_set", "flag_not_set"):
        maps_flags_used.append((where, cond.get("flag", "")))


def main():
    show_todo = "--todo" in sys.argv
    maps = {}
    for fn in sorted(os.listdir(CHAR_DIR)):
        if fn.endswith(".json"):
            try:
                maps[fn[:-5]] = load_json(os.path.join(CHAR_DIR, fn))
            except Exception as e:
                R.err("Characters/" + fn, "is not valid JSON (%s)" % e)

    # Name registries first (gates may point at characters on other maps).
    placed = defaultdict(list)   # name -> [map]
    for m, doc in maps.items():
        for sec in ("npcs", "opponents"):
            for name in (doc.get(sec) or {}):
                placed[name].append(m)
                (ALL_OPP_NAMES if sec == "opponents" else ALL_NPC_NAMES)[name.lower()] = name
    for name in C_OPP:
        ALL_OPP_NAMES[name.lower()] = name
    for name in C_NPC:
        ALL_NPC_NAMES[name.lower()] = name

    for name, ms in placed.items():
        if len(ms) > 1 and name not in MULTI_MAP_OK:
            R.warn("character '%s'" % name, "is defined on %d maps (%s) — beaten/met/gift progress is shared by name"
                   % (len(ms), ", ".join(ms)))

    flags_used = []
    coin_givers = defaultdict(list)

    # ---------------------------------------------------------------- opponents
    for m, doc in maps.items():
        for name, body in (doc.get("opponents") or {}).items():
            where = "%s / opponent '%s'" % (m, name)
            key = next((k for k in C_OPP if k.lower() == name.lower()), None)
            const = C_OPP.get(key, {}) if key else {}
            if key is None and not body.get("deck"):
                R.err(where, "has no entry in All_NPC_Constant_Data.json 'opponents' (no deck, sprite or rewards)")
            elif key is not None and key != name:
                R.warn(where, "constants key is spelled '%s' (case differs)" % key)
            check_character(where, name, body, const, True, flags_used, coin_givers)
        for name, body in (doc.get("npcs") or {}).items():
            where = "%s / npc '%s'" % (m, name)
            key = next((k for k in C_NPC if k.lower() == name.lower()), None)
            const = C_NPC.get(key, {}) if key else {}
            becomes_opp = any(isinstance(r, dict) and r.get("kind") == "opponent" for _, r in iter_rules(body))
            if becomes_opp:
                okey = next((k for k in C_OPP if k.lower() == name.lower()), None)
                if okey is None and not body.get("deck"):
                    R.err(where, "a rule makes them an opponent but there is no opponent constants entry")
                else:
                    check_character(where + " (as opponent)", name, body, C_OPP.get(okey, {}), True, flags_used, coin_givers)
            check_character(where, name, body, const, False, flags_used, coin_givers)

    # Constants never placed on a map.
    for name in C_OPP:
        if name not in placed and name.lower() not in {p.lower() for p in placed}:
            R.td("Opponents defined but not placed on any map (fine if a cutscene fights them)", name)
    for name in C_NPC:
        if name.lower() not in {p.lower() for p in placed}:
            R.td("NPCs defined but not placed on any map (fine if a cutscene uses them)", name)

    # Opponent stars (League LP is paid by stars).
    for name, c in C_OPP.items():
        if "stars" not in c:
            R.err("opponent '%s'" % name, "has no 'stars' (League Points use it)")

    # Flags.
    for where, flag in flags_used:
        if flag not in KNOWN_FLAGS:
            R.err(where, "flag '%s' is never set by any script (the gate can never open / never close)" % flag)

    # Coins handed out twice.
    shop_coins = set()
    try:
        for row in load_json(os.path.join(DATA, "coin_shop_inventory.json")).get("coins", []):
            fn = row.get("filename", "")
            shop_coins.add(fn[:-4] if fn.endswith(".png") else fn)
            if (fn[:-4] if fn.endswith(".png") else fn) not in COINS:
                R.err("coin_shop_inventory.json", "coin '%s' has no art" % fn)
    except FileNotFoundError:
        pass
    for coin, who in coin_givers.items():
        if coin in ("REPLACECOIN", ""):
            continue
        if len(set(who)) > 1:
            R.warn("coin '%s'" % coin, "is given by %d characters: %s (each coin is meant to come from one place)"
                   % (len(set(who)), ", ".join(sorted(set(who)))))
        if coin in shop_coins:
            R.warn("coin '%s'" % coin, "is a reward AND sold in the coin shop")

    # ---------------------------------------------------------------- decks
    ratings = load_json(os.path.join(DATA, "Deck_Ratings.json")).get("decks", {})
    for d in sorted(DECKS):
        # A deck nobody fights with and that isn't rated (the user's TEST deck, scratch decks)
        # only gets warnings: it can't reach a player.
        live = d in DECK_USERS or d in ratings
        deck_era_and_legality(d, live)
    used = {u.lower() for u in DECK_USERS}
    for deck in ratings:
        if deck.lower() not in DECKS_LC:
            R.err("Deck_Ratings.json", "rates deck '%s' but there is no such deck file" % deck)
        if deck.lower() not in used and deck not in NEVER_OPPONENT_DECKS:
            R.td("Rated decks with no opponent yet", "%s (%s★)" % (deck, ratings[deck].get("stars", "?")))

    # ---------------------------------------------------------------- shops
    check_shops()

    # ---------------------------------------------------------------- league rank rewards
    lc = load_json(os.path.join(DATA, "League_Config.json"))
    for rank, rew in (lc.get("rank_rewards") or {}).items():
        if rank.startswith("_"):
            continue
        if not rew:
            R.td("League rank rewards still empty", "rank %s" % rank)
            continue
        kind, rid = rew.get("kind"), str(rew.get("id", ""))
        w = "League_Config rank_rewards[%s]" % rank
        if kind == "coin":
            check_coin(w, rid)
        elif kind == "sleeve":
            check_sleeve(w, rid)
        elif kind == "costume":
            check_costume(w, rid)
        else:
            R.err(w, "kind '%s' is not coin / sleeve / costume" % kind)

    # ---------------------------------------------------------------- phone calls
    pc_path = os.path.join(DATA, "Phone_Calls.json")
    if os.path.exists(pc_path):
        walk_text("Phone_Calls.json", load_json(pc_path))

    # ---------------------------------------------------------------- every card id string in data
    for dp, _dn, fns in os.walk(DATA):
        for fn in fns:
            if not fn.endswith(".json") or os.path.basename(dp) == "Opponent_Deck_Data":
                continue
            text = read(os.path.join(dp, fn))
            for cid in set(re.findall(r'"((?:base|gym|neo|ecard|ex|np|si|pop|basep)\d*-[0-9A-Za-z?]+)"', text, re.I)):
                for part in card_list(cid):
                    if part not in CARDS and (part.split("-")[0].lower() + "-" + part.split("-", 1)[1]) not in CARDS:
                        R.err(os.path.relpath(os.path.join(dp, fn), ROOT), "names card id '%s', which doesn't exist" % part)

    # ---------------------------------------------------------------- doors
    check_doors()

    write_report(show_todo)
    return 1 if R.errors else 0


def walk_text(where, node):
    """Phone_Calls.json: any 'text'/'line'/'says' string. A line that is exactly
    "[UNLOCK]" is FishShopCalls' marker for where the item reveal plays."""
    if isinstance(node, str):
        if node.strip() != "[UNLOCK]":
            check_text(where, node)
        return
    if isinstance(node, dict):
        for k, v in node.items():
            if k.startswith("_"):
                continue
            if k in ("text", "line", "lines", "says") or k in SAYS_KEYS:
                walk_text("%s.%s" % (where, k), v)
                continue
            if isinstance(v, (dict, list)):
                walk_text("%s.%s" % (where, k), v)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk_text("%s[%d]" % (where, i), v)


def check_character(where, name, body, const, is_opp, flags_used, coin_givers):
    merged = dict(const)
    merged.update({k: v for k, v in body.items() if k != "when"})
    # sprite / colour
    sprite = merged.get("sprite", "")
    if not sprite and not merged.get("placeholder"):
        R.err(where, "has no sprite")
    elif sprite and sprite not in OVERWORLD_SPRITES:
        near = [s for s in OVERWORLD_SPRITES if s.lower() == str(sprite).lower()]
        if near:
            R.err(where, "sprite '%s' differs in capitals from Overworld_Sprites/%s.png" % (sprite, near[0]))
        else:
            R.err(where, "sprite '%s' has no Overworld_Sprites/%s.png%s" % (sprite, sprite, suggest(sprite, OVERWORLD_SPRITES)))
    if is_opp and sprite and str(sprite).lower() not in BATTLE_SPRITES_LC:
        R.err(where, "sprite '%s' has no In_Battle_Sprites portrait (the match shows no trainer)" % sprite)
    col = merged.get("message_colour", "")
    if col and col not in MESSAGE_COLOURS:
        R.err(where, "message_colour '%s' is not a Message_Box_Theme colour%s" % (col, suggest(col, MESSAGE_COLOURS, 0.5)))

    # schedule rules
    inherited_req = body.get("requires")
    for rname, rule in iter_rules(body):
        w = "%s %s" % (where, rname) if rname != "defaults" else where
        check_days(w, rule.get("days"))
        check_times(w, rule.get("times"))
        if rule.get("requires") is not None:
            check_requires(w, rule.get("requires"), flags_used)
        mv = rule.get("move")
        if mv is not None:
            pat = mv if isinstance(mv, str) else (mv.get("pattern") if isinstance(mv, dict) else None)
            if pat is not None and pat not in MOVE_PATTERNS:
                R.err(w, "move pattern '%s' is unknown%s" % (pat, suggest(pat, MOVE_PATTERNS)))
        kind = rule.get("kind")
        if kind is not None and kind not in ("npc", "opponent"):
            R.err(w, "kind '%s' must be npc or opponent" % kind)
        says = rule.get("says")
        if says is not None:
            if not isinstance(says, dict):
                R.err(w, "'says' must be an object of meet/repeat/... lines")
            else:
                for k, v in says.items():
                    if k not in SAYS_KEYS:
                        R.err(w, "says key '%s' is never read (use %s)" % (k, ", ".join(sorted(SAYS_KEYS))))
                    check_text("%s says.%s" % (w, k), v)
        for k in ("meet_text", "repeat_text", "costume_match_text"):
            if k in rule:
                check_text("%s %s" % (w, k), rule[k])
        for k in ("match_effects", "restrictions"):
            if k in rule:
                check_rules_block(w, k, rule[k])
        if "sleeve_reward" in rule and rule["sleeve_reward"]:
            check_sleeve(w, str(rule["sleeve_reward"]))
    for k in ("meet_text", "repeat_text", "costume_match_text"):
        if k in const:
            check_text("%s (constants) %s" % (where, k), const[k])
    for k in ("match_effects", "restrictions"):
        if k in const:
            check_rules_block(where + " (constants)", k, const[k])

    # gifts / service NPCs
    gt = merged.get("gift_type", "")
    gv = str(merged.get("gift_value", ""))
    if gt:
        if gt not in GIFT_TYPES:
            R.err(where, "gift_type '%s' is not handled (MapManager._give_gift: %s)" % (gt, ", ".join(sorted(GIFT_TYPES))))
        elif gt == "card":
            for cid in card_list(gv):
                check_card_id(where + " gift", cid)
        elif gt == "coin":
            check_coin(where + " gift", gv)
            coin_givers[gv].append(name)
        elif gt == "costume":
            check_costume(where + " gift", gv)
        elif gt == "sleeve":
            check_sleeve(where + " gift", gv)
        elif gt == "pack":
            for art in card_list(gv):
                check_pack(where + " gift", art)
        elif gt == "cash":
            if not re.fullmatch(r"\d+", gv.strip()):
                R.err(where, "cash gift '%s' is not a whole number" % gv)
        elif gt == "available_pack":
            sets = {p.rsplit("_", 1)[0] for p in PACKS}
            if gv not in sets and gv + ".json" not in os.listdir(CARD_DIR):
                R.err(where, "available_pack '%s' is no pack set" % gv)
    rc = merged.get("required_costume", "")
    if rc:
        check_costume(where + " required_costume", rc)

    if not is_opp:
        return

    # ---- opponent-only fields (Main.load_opponent_data_by_name + Match_End_Outro rewards)
    deck = merged.get("deck", "")
    if not deck:
        R.err(where, "has no deck")
    elif str(deck).lower() not in DECKS_LC:
        R.err(where, "deck '%s' has no file in Opponent_Deck_Data%s" % (deck, suggest(deck, DECKS, 0.6)))
    else:
        if DECKS_LC[str(deck).lower()] != deck:
            R.warn(where, "deck '%s' is spelled '%s' on disk (found anyway)" % (deck, DECKS_LC[str(deck).lower()]))
        DECK_USERS[DECKS_LC[str(deck).lower()]].append(name)
    check_bgm(where, merged.get("music", ""))
    for k in ("cash_reward",):
        v = merged.get(k)
        if v not in (None, "") and not re.fullmatch(r"\d+", str(v).strip()):
            R.err(where, "%s '%s' is not a whole number" % (k, v))
    pz = merged.get("prize_cards", 6)
    if not isinstance(pz, int) or not 1 <= pz <= 6:
        R.err(where, "prize_cards %r must be 1-6" % (pz,))
    cr = merged.get("coin_reward", "")
    if cr:
        check_coin(where + " coin_reward", cr)
        coin_givers[cr].append(name)
    for cid in card_list(merged.get("card_reward", "")):
        check_card_id(where + " card_reward", cid)
    for art in card_list(merged.get("pack_reward", "")):
        check_pack(where + " pack_reward", art)
    for cos in card_list(merged.get("costume_reward", "")):   # comma list (Match_End_Outro_Script)
        check_costume(where + " costume_reward", cos)
    st = merged.get("stars")
    if st is not None and not (isinstance(st, (int, float)) and 1 <= st <= 8):
        R.err(where, "stars %r must be 1-8" % (st,))
    mf = merged.get("match_format")
    if mf not in (None, "", "single", "bo3", "best_of_3"):
        R.warn(where, "match_format '%s' — check it is a format the game knows" % mf)


def check_rules_block(where, kind, block):
    if kind == "match_effects":
        if not isinstance(block, list):
            R.err(where, "match_effects must be a list")
            return
        for e in block:
            if not isinstance(e, dict) or "type" not in e:
                R.err(where, "match_effects entry %r has no 'type'" % (e,))
            elif e["type"] not in MATCH_EFFECT_TYPES:
                R.err(where, "match_effects type '%s' is unknown (ignored by Match_Effects.gd)%s" % (e["type"], suggest(e["type"], MATCH_EFFECT_TYPES)))
            elif e.get("applies_to", "both") not in ("both", "player", "opponent"):
                R.err(where, "match_effects applies_to '%s' must be both / player / opponent" % e.get("applies_to"))
    else:
        if not isinstance(block, dict):
            R.err(where, "restrictions must be an object")
            return
        for k, v in block.items():
            if k.startswith("_"):
                continue
            if k not in RESTRICTION_KEYS:
                R.err(where, "restrictions key '%s' is unknown to Deck_Validation_Helper (ignored)%s" % (k, suggest(k, RESTRICTION_KEYS)))
        for cid in block.get("banned_card_ids", []) + [r.get("id") for r in block.get("required_card_ids", []) if isinstance(r, dict)]:
            if cid:
                check_card_id(where + " restrictions", str(cid))
        for sid in block.get("allowed_set_ids", []):
            if not os.path.exists(os.path.join(CARD_DIR, sid + ".json")):
                R.err(where, "allowed_set_ids '%s' is no card set" % sid)


def check_shops():
    shops = load_json(os.path.join(DATA, "Shop_Config", "shops.json"))
    for sid, cfg in shops.items():
        for k in ("menu_scene", "return_scene"):
            p = cfg.get(k)
            if p and not os.path.exists(os.path.join(ROOT, p.replace("res://", ""))):
                R.err("shops.json '%s'" % sid, "%s '%s' does not exist" % (k, p))
    inv = load_json(os.path.join(DATA, "cosmetic_shop_inventory.json"))
    for sid, block in inv.items():
        if sid.startswith("_") or not isinstance(block, dict):
            continue
        rows = []
        bkind = block.get("kind", "")
        for it in block.get("items", []):
            rows.append((bkind, it))
        for page in block.get("pages", []):
            pk = page.get("kind", bkind)
            for it in page.get("items", []):
                rows.append((pk, it))
        for kind, it in rows:
            if not isinstance(it, dict):
                continue
            k = it.get("kind", kind)
            n = str(it.get("name", ""))
            w = "shop '%s'" % sid
            if k == "sleeve":
                check_sleeve(w, n)
            elif k == "costume":
                check_costume(w, n)
            elif k == "coin":
                if n not in COINS:
                    R.err(w, "coin '%s' has no art" % n)
            elif k == "pack":
                check_pack(w, n)
            elif k == "item":
                if n not in ITEMS and not it.get("label"):
                    R.err(w, "item '%s' has no art and no label" % n)
                elif n not in ITEMS:
                    R.td("Shop items still showing a text label (no art yet)", "%s: %s" % (sid, n))
            else:
                R.err(w, "row '%s' has unknown kind '%s'" % (n, k))
            if block.get("league_points"):
                if "lp_cost" not in it and "cost" not in it:
                    R.err(w, "row '%s' has no lp_cost" % n)
            elif "cost" not in it and "fish_cost" not in it:
                R.err(w, "row '%s' has no cost" % n)
    # NPC shop_ids -> a shops.json block (npc_type shop) or an inventory block (sellers).
    for src, pool in (("constants", C_NPC),):
        for name, c in pool.items():
            t = c.get("npc_type", "")
            sid = c.get("shop_id", name.lower().replace(" ", "_"))
            if t == "shop" and sid not in shops:
                R.err("npc '%s'" % name, "npc_type shop but shop_id '%s' is not in shops.json" % sid)
            if t in ("sleeve_seller", "costume_seller") and sid not in inv:
                R.err("npc '%s'" % name, "%s but shop_id '%s' has no block in cosmetic_shop_inventory.json" % (t, sid))


def check_doors():
    scenes_dir = os.path.join(ROOT, "Scenes", "Map_Scenes")
    if not os.path.isdir(scenes_dir):
        return
    links = defaultdict(list)   # scene -> [target basename]
    for fn in os.listdir(scenes_dir):
        if not fn.endswith(".tscn"):
            continue
        scene = fn[:-5]
        text = read(os.path.join(scenes_dir, fn))
        for tgt in re.findall(r'metadata/target_scene\s*=\s*"([^"]+)"', text):
            base = os.path.splitext(os.path.basename(tgt))[0]
            links[scene].append(base)
            if not os.path.exists(os.path.join(ROOT, tgt.replace("res://", ""))):
                if (scene, base) not in INERT_DOOR_TARGETS:
                    R.err("door in %s" % scene, "leads to '%s', which doesn't exist" % tgt)
        for t, n in Counter(links[scene]).items():
            if n > 1:
                R.err("doors in %s" % scene, "%d doors lead to %s (arrival is ambiguous)" % (n, t))
    for scene, targets in links.items():
        for t in targets:
            if (scene, t) in INERT_DOOR_TARGETS or t not in links:
                continue
            if scene not in links[t]:
                R.err("door %s -> %s" % (scene, t), "has no door back from %s (you arrive at the default spawn)" % t)


def write_report(show_todo):
    lines = []
    lines.append("CONTENT CHECK — %d error(s), %d warning(s), %d to-do item(s)"
                 % (len(R.errors), len(R.warnings), sum(len(v) for v in R.todo.values())))
    lines.append("=" * 78)
    lines.append("")
    lines.append("ERRORS (will break or silently fail in the game)")
    lines += ["  - " + e for e in sorted(set(R.errors))] or ["  none"]
    lines.append("")
    lines.append("WARNINGS (legal, but check you meant it)")
    lines += ["  - " + w for w in sorted(set(R.warnings))] or ["  none"]
    lines.append("")
    lines.append("TO-DO (placeholders still to fill)")
    full = list(lines)
    for group in sorted(R.todo):
        items = sorted(set(R.todo[group]))
        lines.append("  %-70s %d" % (group, len(items)))
        full.append("  %s: %d" % (group, len(items)))
        full += ["      " + i for i in items]
    if not R.todo:
        lines.append("  none")
        full.append("  none")
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "content_check.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(full) + "\n")
    out = "\n".join(full if show_todo else lines)
    try:
        print(out)
    except UnicodeEncodeError:
        print(out.encode("ascii", "replace").decode())
    print("\n(full report with every TO-DO item: audit_out/content_check.txt)")


if __name__ == "__main__":
    sys.exit(main())
