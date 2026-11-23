"""Card effect tagger — builds the EFFECTS filter data for the deck builder's card search.

Reads every set in Card_Set_Data/ and sorts each piece of effect text (attack text, Pokemon
Power / Poke-Power / Poke-Body text, Trainer rules, Special Energy rules, and the few non-boilerplate
Pokemon rule boxes) into one or more EFFECT CATEGORIES. Writes:

    Card_Set_Data/Effect_Tags/Card_Effect_Tags.json
        {
          "categories": [ {key, label, group, desc}, ... ]   <- the search screen builds from this
          "cards":      { card_id: { category_key: source_bits } }
        }

source_bits says WHERE on the card the effect lives, so the search can scope to one of them:
    1 = an attack      2 = a Power / Poke-Power / Poke-Body (or a Pokemon rule box)
    4 = Trainer or Special Energy card text

The folder is a SUBFOLDER on purpose: several loaders enumerate Card_Set_Data/*.json as sets.

RE-RUN THIS WHENEVER A SET IS ADDED OR CARD TEXT CHANGES:
    python Scripts/Utilities/card_effect_tags_build.py            (build + coverage report)
    python Scripts/Utilities/card_effect_tags_build.py --check    (report only, no write)
    python Scripts/Utilities/card_effect_tags_build.py --show KEY (list every text tagged KEY)

The coverage report must end with "0 untagged" — every effect text has to land in at least one
category. There is no catch-all "unique" bucket: a one-off effect gets a rule or a real category.
"""
import glob
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SET_DIR = os.path.join(ROOT, "Card_Set_Data")
OUT_DIR = os.path.join(SET_DIR, "Effect_Tags")
OUT_FILE = os.path.join(OUT_DIR, "Card_Effect_Tags.json")

SRC_ATTACK, SRC_POWER, SRC_CARD = 1, 2, 4
SRC_ALL = 7

# ════════════════════════════════════════════════════════════════════════════════════════════
# CATEGORIES — order here is the order on screen, grouped by `group`.
# key = icon file stem (Image_Assets/Icons/Effect_Icons/effect_<key>.png)
# ════════════════════════════════════════════════════════════════════════════════════════════
CATEGORIES = [
    # ── ATTACK DAMAGE ──
    ("bonus_damage",    "Bonus Damage",        "DAMAGE",  "Does more damage when a condition is met"),
    ("scaling_damage",  "Variable Damage",     "DAMAGE",  "Damage depends on Energy, counters, cards or HP"),
    ("damage_boost",    "Boost Damage",        "DAMAGE",  "Makes attacks do more damage (PlusPower, Darkness Energy...)"),
    ("setup_boost",     "Power Up Next Turn",  "DAMAGE",  "Sets up more damage for your NEXT turn (Swords Dance, Extra Comet Punch...)"),
    ("flip_bonus",      "Flip: More Damage",   "DAMAGE",  "Flip coins for extra damage on heads"),
    ("flip_multiply",   "Flip: Multiply",      "DAMAGE",  "Damage times the number of heads"),
    ("risky",           "Risky Attack",        "DAMAGE",  "If tails, the attack does nothing"),
    ("bench_snipe",     "Snipe & Spread",      "DAMAGE",  "Damages Benched or several of your opponent's Pokemon"),
    ("bench_own",       "Hit Own Bench",       "DAMAGE",  "Damages your own Benched Pokemon"),
    ("recoil",          "Self Damage",         "DAMAGE",  "Damages the Pokemon using it"),
    ("recoil_cond",     "Avoidable Recoil",    "DAMAGE",  "Self damage you choose, or a condition switches off"),
    ("place_counters",  "Place Counters",      "DAMAGE",  "Puts damage counters straight onto Pokemon"),
    ("move_counters",   "Move Counters",       "DAMAGE",  "Moves damage counters between Pokemon"),
    ("pierce",          "Ignore Defences",     "DAMAGE",  "Ignores Weakness, Resistance or effects"),
    ("instant_ko",      "Instant KO",          "DAMAGE",  "Knocks the opponent's Pokemon Out outright (Shock-wave, Perish Song, Destiny Bond...)"),
    ("self_ko",         "Self Knock Out",      "DAMAGE",  "Knocks itself Out on purpose (Buzzap, Final Sting, Selfdestruct / Explosion)"),
    ("counter_damage",  "Counter Attack",      "DAMAGE",  "Hurts the attacker when this Pokemon is hit"),
    ("copy_attack",     "Metronome",           "DAMAGE",  "Picks an attack from another card to use (Metronome, Genetic Memory, Psylink...)"),
    ("extra_attack",    "Bonus Attack",        "DAMAGE",  "A Trainer that gives a set attack of its own (Technical Machines, Cubes, Plates, Holon Lake)"),
    ("attack_condition","Conditional Attack",  "DAMAGE",  "The attack only works when a condition is met"),
    # ── DEFENCE ──
    ("heal",            "Heal",                "DEFENCE", "Removes damage counters"),
    ("damage_reduce",   "Reduce Damage",       "DEFENCE", "Takes less damage, or weakens the attacker"),
    ("prevent_damage",  "Prevent Damage",      "DEFENCE", "Prevents damage done to a Pokemon (Withdraw, Agility...)"),
    ("block_effects",   "Block Effects",       "DEFENCE", "Stops the EFFECTS of attacks or Trainers on a Pokemon (Crystal Body, Agility, 'except damage')"),
    ("ko_prevent",      "Survive Knock Out",   "DEFENCE", "Stops a Knock Out and stays in play (Focus Band, Hoppip, Giovanni's Machamp...)"),
    ("hp_boost",        "HP Boost",            "DEFENCE", "Raises a Pokemon's HP"),
    ("weak_resist",     "Weakness & Resist",   "DEFENCE", "Removes, changes or ignores Weakness / Resistance as a lasting effect (Conversion, Weakness Guard, Ancient Tomb...)"),
    ("status_cure",     "Cure Conditions",     "DEFENCE", "Removes Special Conditions (Full Heal, Lum Berry...)"),
    # ── SPECIAL CONDITIONS ──
    ("poison",          "Poison",              "STATUS",  "Can Poison a Pokemon"),
    ("burn",            "Burn",                "STATUS",  "Can Burn a Pokemon"),
    ("sleep",           "Sleep",               "STATUS",  "Can put a Pokemon to Sleep"),
    ("paralyze",        "Paralyze",            "STATUS",  "Can Paralyze a Pokemon"),
    ("confuse",         "Confuse",             "STATUS",  "Can Confuse a Pokemon"),
    ("self_status",     "Self Condition",      "STATUS",  "The user falls Asleep, Confused, etc."),
    ("status_immune",   "Condition Immunity",  "STATUS",  "Can't be Poisoned / Asleep / affected by Special Conditions (Snorlax, Roselia, Zangoose...)"),
    # ── ENERGY ──
    ("energy_attach",   "Energy Gain",         "ENERGY",  "Attaches extra Energy"),
    ("energy_remove",   "Energy Removal",      "ENERGY",  "Discards or removes your opponent's Energy"),
    ("energy_discard",  "Energy Discard",      "ENERGY",  "Discards or returns your own attached Energy"),
    ("energy_move",     "Energy Move",         "ENERGY",  "Moves Energy between Pokemon"),
    ("energy_supply",   "Energy Supply",       "ENERGY",  "Provides extra Energy, or Energy of other types"),
    ("cost_change",     "Cost Change",         "ENERGY",  "Changes attack or retreat costs"),
    # ── CARDS ──
    ("draw",            "Draw Cards",          "CARDS",   "Draws cards"),
    ("search_deck",     "Search Deck",         "CARDS",   "Searches a deck for cards"),
    ("bench_call",      "Fill the Bench",      "CARDS",   "Puts Pokemon straight onto the Bench"),
    ("recover",         "Recover Discards",    "CARDS",   "Gets cards back from the discard pile"),
    ("discard_hand",    "Discard Cards",       "CARDS",   "Discards cards from your own hand"),
    ("hand_disrupt",    "Hand Disruption",     "CARDS",   "Messes with your opponent's hand"),
    ("mill",            "Mill Deck",           "CARDS",   "Discards cards from the top of a deck"),
    ("deck_disrupt",    "Deck Disruption",     "CARDS",   "Shuffles or reorders a deck, or slips cards into it"),
    ("peek",            "Look at Cards",       "CARDS",   "Looks at or rearranges hidden cards"),
    ("prize",           "Prize Cards",         "CARDS",   "Takes extra Prizes or uses Prize cards"),
    ("bounce",          "Return to Hand/Deck", "CARDS",   "Returns Pokemon in play to the hand or deck"),
    ("trainer_manip",   "Trainer Tricks",      "CARDS",   "Counts, finds, discards or borrows Trainer cards (Lass, Milotic δ...)"),
    # ── BOARD ──
    ("switch",          "Switch",              "BOARD",   "Switches your Active Pokemon"),
    ("gust",            "Pull Opponent",       "BOARD",   "Switches your opponent's Active Pokemon"),
    ("retreat_aid",     "Easy Retreat",        "BOARD",   "Lowers or removes retreat costs"),
    ("retreat_lock",    "Block Retreat",       "BOARD",   "Stops or slows retreating"),
    ("attack_lock",     "Block Attacks",       "BOARD",   "Stops the Defending Pokemon attacking"),
    ("self_lock",       "Cooldown",            "BOARD",   "The user can't attack next turn"),
    ("evolve",          "Fast Evolution",      "BOARD",   "Evolves early or straight from the deck"),
    ("devolve",         "Devolve",             "BOARD",   "Removes Evolution cards from play"),
    ("evo_block",       "Block Evolution",     "BOARD",   "Stops Pokemon evolving"),
    ("form_change",     "Change Form",         "BOARD",   "Swaps a Pokemon for another form or card"),
    ("type_change",     "Type Change",         "BOARD",   "Changes a Pokemon's own type, yours or your opponent's (Venomoth Shift, 'is both Fire and Fighting type')"),
    ("bench_size",      "Bench Size",          "BOARD",   "Changes how many Pokemon a Bench can hold"),
    ("play_as_pokemon", "Plays as Pokemon",    "BOARD",   "A Trainer played as if it were a Pokemon"),
    # ── RULES & LOCKS ──
    ("trainer_lock",    "Block Trainers",      "RULES",   "Stops Trainer cards being played"),
    ("power_block",     "Block Abilities",     "RULES",   "Shuts off Pokemon Powers / Poke-Bodies"),
    ("energy_lock",     "Block Energy",        "RULES",   "Stops or weakens your opponent's Energy"),
    ("markers",         "Markers",             "RULES",   "Places marker tokens on Pokemon"),
    ("ko_on",           "On Knock Out",        "RULES",   "Something happens when a Pokemon is Knocked Out (Final Beam, Lanturn, Time Shard...)"),
    ("prize_count",     "Prize Count",         "RULES",   "Changes with how many Prize cards are left (comeback attacks, Pokemon Star last-Prize attacks)"),
    ("drawback",        "Drawback",            "RULES",   "A downside its owner has to live with"),
    ("coin_flip",       "Coin Flip",           "RULES",   "Flips one or more coins"),
    # ── SYNERGY: text that rewards or needs a particular card family ──
    ("syn_species",     "Species",             "SYNERGY", "Needs or boosts named Pokemon (Nidoking, Omanyte, Latias...)"),
    ("syn_named",       "Named Trainers",      "SYNERGY", "Gym Leaders, Team Aqua / Magma, named Stadiums and Trainers"),
    ("syn_type",        "Type",                "SYNERGY", "Works with your Pokemon of a type (Metal, Fire, Darkness...)"),
    ("syn_dark_light",  "Dark & Light",        "SYNERGY", "Works with Dark, Light or Shining Pokemon"),
    ("syn_react",       "React Energy",        "SYNERGY", "React Energy cards and the Pokemon that use them"),
    ("syn_holon",       "Holon",               "SYNERGY", "Holon Energy and Holon Trainers"),
    ("syn_delta",       "Delta Species",       "SYNERGY", "Works with Pokemon that have δ on the card"),
    ("unown",           "Unown",               "SYNERGY", "Every Unown card, and cards that use them"),
    ("syn_special",     "Special Energy",      "SYNERGY", "Uses, needs, discards or blocks Special Energy (not React / Holon)"),
    ("syn_status",      "Condition Synergy",   "SYNERGY", "Only works, or works harder, when a Pokemon is Asleep / Poisoned / Burned / Confused (Dream Eater, Frenzy...)"),
    ("syn_tool",        "Tool Synergy",        "SYNERGY", "Finds, attaches, moves, recovers or powers up with Pokemon Tools / Technical Machines"),
    ("syn_stadium",     "Stadium Synergy",     "SYNERGY", "Finds or plays Stadiums, or does more while a Stadium is in play"),
    ("syn_supporter",   "Supporters",          "SYNERGY", "Finds, recovers, counts or borrows Supporter cards"),
    ("syn_damaged",     "Own Damage",          "SYNERGY", "Changes with the damage counters on itself (Rage, Flail, Take Down...) - pairs with damage movers"),
    ("syn_ex",          "Pokemon-ex",          "SYNERGY", "Works with, or only on non-, your Pokemon-ex (Protective Orb, Swellow, Holon Energy...)"),
    ("syn_stage",       "Stage",               "SYNERGY", "Works with your Basic / Evolved / Stage 2 Pokemon (Boost Energy, 'as long as @ is Evolved')"),
    # ── VS OPPONENT: the reverse of synergy - more / less damage or an effect because of what the
    #    OPPONENT'S Pokemon is ──
    ("vs_ex",           "Vs Pokemon-ex",       "VERSUS",  "Changes when the opponent's Pokemon is a Pokemon-ex"),
    ("vs_stage",        "Vs Stage",            "VERSUS",  "Changes for the opponent's Baby, Basic, Stage 1, Stage 2 or Evolved Pokemon"),
    ("vs_dark_light",   "Vs Dark & Light",     "VERSUS",  "Changes when the opponent's Pokemon is Dark, Light or Shining"),
    ("anti_tool",       "Anti-Tool",           "VERSUS",  "Discards or blocks the opponent's Tools / attached Trainers, or punishes having one"),
    ("anti_stadium",    "Anti-Stadium",        "VERSUS",  "Discards Stadiums or stops them being played"),
    ("vs_damaged",      "Vs Damaged",          "VERSUS",  "Stronger against a Pokemon that already has damage counters - pairs with snipers"),
    ("vs_type",         "Vs Type",             "VERSUS",  "Changes when the opponent's Pokemon is a certain type"),
]
CAT_KEYS = [c[0] for c in CATEGORIES]

# ════════════════════════════════════════════════════════════════════════════════════════════
# Text clean-up
# ════════════════════════════════════════════════════════════════════════════════════════════

# Sentences that are reminder text / boilerplate rather than an effect. Removed BEFORE tagging, so
# "This power can't be used if X is Asleep, Confused, or Paralyzed" never counts as a status effect.
BOILERPLATE = [
    r"this power can'?t be used if .*",
    r"this power stops working (if|while|when) .*",
    r"(this )?power can'?t be used (more than|if) .*",
    r"you can'?t use more than 1 .* each turn",
    r"you can play only one supporter card each turn",
    r"when you play this card, put it next to your active pokemon",
    r"when your turn ends, discard this card",
    r"this card stays in play when you play it",
    r"discard this card if another stadium card comes into play",
    r"if another card with the same name is in play, you can'?t play this card",
    r"attach .+ to 1 of your .*pokemon .*that (doesn'?t|does not) (already )?have a pokemon tool (card )?attached( to it)?",
    r"if that pokemon is knocked out, discard this card",
    r"if .+ is knocked out, it doesn'?t count as a knocked out pokemon",
    r".+ has no attacks.*",
    r"at any time during your turn before your attack, you may discard .+",
    r"you can'?t have more than \d+ .* in your deck",
    r"doesn'?t count as a basic energy card.*",
    r"has no effect other than providing energy",
    r".+ provides (1 )?colorless energy",
    r"attach (?!.*\bfrom\b)(?!.*\bcards?\b).+ to 1 of your (\w+ )?pokemon",
    r"shuffle your deck afterward",
    r"you may play as many .* as you like .*",
    r"you can play this card only .* (first|any) turn",
    r"(at the end of your turn|when your turn ends), discard .*(technical machine|secret machine).*",
]
BOILER_RE = [re.compile("^" + b + "$") for b in BOILERPLATE]

# Pokemon rule boxes that are deck rules / prize rules rather than effects.
POKEMON_RULE_SKIP = [
    r"when pokemon-ex has been knocked out",
    r"you can'?t have more than 1",
    r"you may have up to 4 basic pokemon cards",
    r"this pokemon is both",
    r"evolves into",
    r"baby pokemon",          # the Baby rule — the POKEMON STAGE row already finds Babies
]


# Bracketed REMINDER text that would only confuse the rules (status words in "this power works even
# if X is Asleep", "Knocked Out" in "even if X is Knocked Out", Weakness/Resistance in the Bench
# reminder...). Every OTHER bracket is kept and simply un-bracketed, because plenty carry the effect
# itself: "(both yours and your opponent's)", "(This counts as evolving X.)", "(Discard all cards
# attached to that card.)".
DROP_PARENS = [
    r"before your attack", r"before attacking", r"after doing damage", r"color",
    r"(don'?t|do not) apply weakness (and|or) resistance for benched pokemon\.?",
    r"(after|before) applying weakness and resistance", r"apply weakness and resistance\.?",
    r"even if .*knock.*", r"benching .* ends this effect\.?", r"benching or evolving .*",
    r"any other effects .*still happen\.?", r"doesn'?t count as a basic .*", r"has no (other )?effect.*",
    r"you must still do anything else.*", r"no matter what type .*", r"discard it anyway\.?",
    r"you can'?t (use this attack|play .*) if your bench is full\.?", r"this power works even if .*",
    r"excluding .*", r"rounded .*", r"you still (have|need) .*", r"\d+ if .*", r"all if .*",
    r"or \d+ if .*", r"remove \d+ .*if .*", r"choose \d+ if .*", r"as long as there'?s room",
    r"or if .*bench.* full", r"your choice", r"like .*", r"if an effect of this attack is prevented.*",
]
DROP_PARENS_RE = [re.compile("^" + p + "$") for p in DROP_PARENS]


def _paren(m):
    inner = m.group(1).strip()
    if any(r.match(inner) for r in DROP_PARENS_RE):
        return " "
    return " " + inner + " "


def clean(text, name, is_pokemon):
    t = text.replace("é", "e").replace("É", "E").replace("’", "'")
    n = name.replace("é", "e")
    # A Pokemon's own name becomes @ so the self-tests ("@ does 20 damage to itself") read the same on
    # every card. NOT for Trainers / Energy: "Switch", "Defender", "Potion" are ordinary words in their
    # own text ("Switch your Active Pokemon...") and turning them into @ breaks the sentence.
    if is_pokemon:
        t = t.replace(n, "@")
    t = t.lower()
    t = re.sub(r"\(([^()]*)\)", _paren, t)
    t = re.sub(r"\s+", " ", t).strip()
    t = re.sub(r"\s+([.,])", r"\1", t)
    return t


def sentences(t, keep_boiler=False):
    parts = re.split(r"(?<=[.!?])\s+|\s*\|\s*|\n", t)
    out = []
    for p in parts:
        p = p.strip().rstrip(".").strip()
        if not p:
            continue
        if not keep_boiler and any(b.match(p) for b in BOILER_RE):
            continue
        out.append(p)
    return out


# ════════════════════════════════════════════════════════════════════════════════════════════
# Rules
# ════════════════════════════════════════════════════════════════════════════════════════════
STATUS_WORDS = {
    "poison":   r"poison(ed)?",
    "burn":     r"burn(ed)?",
    "sleep":    r"asleep",
    "paralyze": r"paralyzed",
    "confuse":  r"confused",
}
COND_RE = re.compile(r"\b(asleep|confused|paralyzed|poisoned|burned)\b")
OPP = r"(opponent|defending|his or her|their)"


def has(p, s):
    return re.search(p, s) is not None


def tag_text(sents, src, is_attack, damage_str, card):
    tags = set()
    whole = " ".join(sents)

    # ── coins (whole text) ────────────────────────────────────────────────────────
    if has(r"\bflips? (a|\d+|\w+|that many|a number of) coins?\b|\bflip a coin\b|\bcoin flips?\b|\bheads\b|\btails\b", whole):
        tags.add("coin_flip")
    # per SENTENCE: `whole` has no full stops, so [^.]* would run across sentences
    if any(has(r"tails[^.]*this attack does nothing|if (either|any|all|both|one) [^.]*tails, this attack does nothing", s) for s in sents):
        tags.add("risky")
    # x-damage that multiplies by the COINS (heads, or the tails your opponent flips). "If heads, this
    # attack does 10 damage times the number of damage counters on @" multiplies by counters - that is
    # scaling damage that can whiff, not a coin multiplier.
    coin_mult = has(r"(number of|for each|times) (heads|tails)\b", whole)
    if is_attack and damage_str[-1:] in ("×", "x") and coin_mult:
        tags.add("flip_multiply")
    if any(has(r"times the number of (heads|tails)", s) and not has(r"\bremove|to itself|to @", s) for s in sents):
        tags.add("flip_multiply")
    if is_attack and has(r"if (heads|either (of them )?is heads|both (of them )?are heads), this attack does \d+ damage times", whole) \
            and not coin_mult:
        tags.add("risky")

    # Digging through YOUR deck ("look at the top 7 cards... put 1 into your hand", "reveal cards from
    # your deck until you reveal a Basic") is a deck search. It only counts as PEEK when the cards go
    # back in an order you choose.
    deck_dig = has(r"(look at|reveal|show) [^.]*\b(top|bottom) (\d+|\w+|that many) cards (of|from) your deck|look at (\d+|that many) cards from the top of your deck|reveal cards from your deck until", whole) \
        and has(r"into your hand|attach (it|them)|put (it|them) onto", whole)
    chose_opp = chose_own = False     # "choose 1 of your opponent's Pokemon." ...damage in a LATER sentence
    prev = ""
    for s in sents:
        ctx = (prev + " . " + s) if prev else s
        prev_s = prev
        prev = s
        heads = has(r"\bheads\b", s)
        coin = has(r"\b(heads|tails)\b", s)
        # "if heads, the defending pokemon is knocked out" reads as an IF but is an outright effect
        core = re.sub(r"^(if (heads|tails)|if (both|all|either|any) (of them )?(are|is) (heads|tails)|if you get \d+ or more heads),\s*", "", s)
        if has(r"\bchoose (1|2|up to \d+) of (your opponent'?s|his or her|the defending)|(opponent|he or she) has any benched pokemon[^.]*\bchoose (1|2|up to \d+) of (them|those)", s):
            chose_opp = True
        elif has(r"\bchoose (1|2|up to \d+) of your (own )?(benched )?pokemon|you have any benched pokemon[^.]*choose (1|2|up to \d+) of them", s):
            chose_own = True

        # ── damage maths (attacks) ────────────────────────────────────────────────
        if is_attack and has(r"^(if|unless) (?![^,]*\b(tails|heads)\b)[^,]*, this attack does nothing", s) \
                and not has(r"bench|can'?t discard|doesn'?t have|no cards in your deck|only 1 defending", s):
            tags.add("attack_condition")
        if is_attack:
            base_swap = re.search(r"base damage is (\d+) instead of (\d+)", s)
            if base_swap and has(r"(?<!this )attack'?s base damage", s):
                # another attack's base damage changed: "Pound's base damage is 30 instead of 10" is a
                # boost, "next turn ... base damage is 50 instead of 70" is the price of this attack
                tags.add("damage_boost" if int(base_swap.group(1)) > int(base_swap.group(2)) else "drawback")
            elif coin and (has(r"more damage|plus \d+|damage plus|damage instead|damage is \d+ instead", s)
                           or (has(r"this attack does \d+ damage$", s) and len(set(re.findall(r"does (\d+) damage", whole))) > 1)
                           or (has(r"for each heads", s) and has(r"damage", s) and not has(r"\bremove", s))) \
                    and not has(r"times the number", s):
                # a coin decides the extra damage ("if tails, base damage is 20 instead of 60",
                # "if both are heads, this attack does 50 damage")
                tags.add("flip_bonus")
            elif has(r"for each|times the (number|amount|total amount)|\d+ times that number|equal to (the number|\d+ times|that|half)|x the number of|\bhalf\b[^.]*remaining hp|damage equal to|damage minus|minus the (number|remaining)", s) \
                    and has(r"damage", s) and (not heads or has(r"times the number of (?!heads|tails)", s)) and not has(r"^(put|remove|move)|^@ does|for each (tails|heads)|number of (heads|tails)|\bremove", s):
                tags.add("scaling_damage")
            elif not has(r"\d+ or more damage(?! counter)", s) and has(r"more damage|damage plus|does \d+ damage instead|base damage (is|of)|is doubled|damage[^.]* doubled|(if|unless) [^.]*this attack does \d+ damage|damage counters?[^.]*this attack does \d+ damage", s) \
                    and has(r"more damage|instead|base damage|doubled|damage plus|this attack does \d+ damage$", s) \
                    and not has(r"for each|times the number|can'?t use this attack", s) \
                    and (not coin or has(r"next turn", s)):
                if has(r"during your next turn|next turn", s):
                    tags.add("damage_boost")
                else:
                    tags.add("bonus_damage")
            if not has(r"bench is (full|empty)|bench if full", s) and has(r"can'?t (be )?used? (this attack )?unless|this attack can'?t be used unless|does nothing (if|unless) (?!@ doesn'?t have the energy)|can (only )?(be )?used? (this attack )?only if|can only use this attack|can'?t use this attack (unless|if)", s):
                tags.add("attack_condition")
        else:
            if has(r"(\d+|that much) more damage|damage done by [^.]*is increased|does \d+ damage plus|attacks? do(es)? \d+ (more )?damage|base damage|more damage", s) \
                    and not has(r"damage done to [^.]*(is increased|more damage)|done to @[^.]*increased|or more damage", s):
                tags.add("damage_boost")

        # ── self damage ──────────────────────────────────────────────────────────
        is_recoil = has(r"damage to itself|@ does [^.]*to itself|(put|place)s? (up to )?(\d+|a|that many|\w+) damage counters? on @(?![\w'])|\b\d+ damage (times the number of \w+ )?to @(?![\w'])|damage to each active pokemon|(damage|counters?) (to|on) each active pokemon both yours", s) \
            and not has(r"even to itself|\bremove|damage done to @", s)
        if is_recoil:
            tags.add("recoil")
            # recoil you CHOOSE ("you may do 50 damage plus 30 more. if you do, @ does 30 damage to
            # itself") or only take on a condition ("if that pokemon is knocked out...") - never a coin
            if has(r"^if you do\b|^if (that|the defending) pokemon is knocked out|^unless|^if you (choose|discard|have)|^you may put", s) \
                    and not has(r"\b(heads|tails)\b", ctx):
                tags.add("recoil_cond")
        # a Poke-Body that switches off the user's own recoil (Rayquaza delta's Delta Guard)
        if has(r"ignore the effects? of @'?s [\w' -]+ attack", s):
            tags.add("recoil_cond")

        # ── snipe / spread / own bench ───────────────────────────────────────────
        deal = has(r"\bdamage\b|\bcounters?\b", s) and has(r"\b(does|do|put|puts|place|places)\b|damage to|counters? on", s) \
            and not has(r"^prevent|prevent all|reduced? |for each damage counter|isn'?t affected|don'?t take|not take|\bremove|more damage to(?![^.]*\band \d+ damage to)|only does half|instead of \d+|(with|has|have) no damage counters", s)
        target = has(r"(damage|counters?) to (that pokemon|those pokemon|each|it\b|them\b|1 of|2 of|3 of|any|your opponent'?s|his or her|the benched|1 benched|benched|1 of your)|(damage )?counters? on (each|1 of|2 of|that pokemon|those|it\b|them|your opponent'?s|any|the benched|your benched)|does \d+ damage to (each|1|2|3|that|those|it|them|your)|this (power|attack) does \d+ damage to (that|each|it|them)|\bon (your opponent'?s|his or her) benched pokemon", s)
        # damage to an opponent's ACTIVE Pokemon only (a Power punishing a retreat, Pichu's Power
        # zapping the Active) is not a Bench snipe
        active_only = (has(r"(opponent'?s|his or her) active pokemon", ctx) and not has(r"bench|\beach\b|\bany\b|(1|2|3) of", ctx)) \
            or (has(r"between turns", s) and not has(r"bench|pokemon-ex|poke-bod|each of your opponent'?s pokemon", s))
        if deal and target and active_only:
            if not is_attack:
                tags.add("place_counters")
        elif deal and target:
            own_bench_them = has(r"\byou have (any )?benched pokemon.*\b(1|2|3|each) of them", ctx) and not has(r"opponent", s)
            if has(r"(opponent'?s|his or her) (\w+ )?pokemon|your opponent'?s bench|each benched pokemon|each player'?s|both yours|yours and your opponent|your own or your opponent|either player'?s|each pokemon\b|each non-\w+ pokemon|any (1 )?pokemon|each defending pokemon|(1|each|2) of (the )?defending|each active pokemon", ctx) \
                    or (has(r"(1|2|3|each) of them", ctx) and not own_bench_them):
                if not has(r"^(choose|count) [^.]*\byour (benched )?pokemon\b(?! [^.]*opponent)", ctx):
                    tags.add("bench_snipe")
            if (has(r"(damage|counters?) (to|on) (each of |1 of |2 of )?your (own )?(benched )?pokemon|each benched pokemon|each player'?s|both yours|yours and your opponent|your own or your opponent|including your own|even your own|each pokemon\b|each non-\w+ pokemon|each active pokemon|either player'?s", ctx)
                    or own_bench_them) \
                    and not has(r"^your opponent'?s", s) \
                    and not (has(r"each active pokemon", s) and not has(r"bench", s)):
                tags.add("bench_own")
        if not is_attack and has(r"\bthis power does \d+ damage to (?!the attacking)", s):
            tags.add("place_counters")    # a Power's own damage (Dark Ampharos, Dark Magcargo)
        if deal and target:
            pass
        if deal and "bench_snipe" not in tags and "bench_own" not in tags \
                and has(r"\bto (that|the|those|each of those) pokemon\b|\bto (it|them|each of them)\b", s):
            if chose_opp:
                tags.add("bench_snipe")
            elif chose_own:
                tags.add("bench_own")

        # ── damage counters ──────────────────────────────────────────────────────
        if has(r"\b(put|place|puts|places)\b[^.]*\bcounters?\b[^.]*\bon\b", s) and not has(r"\b(put|place)s? an? (coloring|char) counter", s):
            if has(r"counters?( on \w+)? instead of \d+|(burned|poisoned) pokemon[^.]*between turns", s):
                # stronger Burn / Poison between turns, not counters placed by the card
                hit = False
                for k in ("burn", "poison"):
                    if has(r"\b" + STATUS_WORDS[k] + r"\b", ctx):
                        tags.add(k)
                        hit = True
                if not hit:
                    tags.add("poison")
            elif src == SRC_CARD and has(r"energy is attached to|when you attach this card|attached to it", s):
                tags.add("drawback")      # a Special Energy hurting the Pokemon wearing it
            elif has(r"counters? on @(?![\w'])", s) and not has(r"\bon the defending|counters?,? on (each|1 of|2 of|that pokemon|those|it\b|them|your opponent|the defending|any)", s):
                pass                      # counters on itself only = recoil (tagged above)
            elif has(r"counters? on (that|the new benched|the) pokemon\b", s) and not has(r"opponent|defending|his or her", ctx) \
                    and has(r"(1 of|to) your (\w+ )?pokemon|your active pokemon|onto (your|that player'?s) bench|the new benched pokemon", ctx):
                tags.add("drawback")      # the price of a power / Trainer: counters on YOUR Pokemon it helped
            else:
                tags.add("place_counters")
        if has(r"\bmoves? (\w+ ){0,4}damage counters?|damage counters? [^.]*\bmove\b|switch (all )?(the )?damage counters|switch the number of damage counters", s):
            tags.add("move_counters")

        # ── ignore defences ──────────────────────────────────────────────────────
        # Only ATTACK damage ignoring defences. A Power's / Energy's own damage carries "(Don't apply
        # Weakness and Resistance.)" as plain reminder text, and so does bench / spread damage.
        bare_wr = has(r"^(don'?t|do not) apply weakness and resistance$", s)
        if has(r"(isn'?t|is not|aren'?t|not) affected by (weakness|resistance|any effects|effects)|ignor(e|ing) (weakness|resistance|any effects|all effects|the effects)|(don'?t|do not) apply (weakness|resistance)|resistance [^.]*only reduces", s) \
                and not has(r"itself|for benched|benched pokemon|weakness for all of your|\w+ weakness for|(aren'?t|isn'?t) affected by effects from", s) \
                and not (bare_wr and (not is_attack or has(r"benched pokemon|even your own|\bmoves? [^.]*damage counter", whole))):
            tags.add("pierce")

        # ── knock outs ───────────────────────────────────────────────────────────
        if has(r"knocked out|knock out|knocks out|knocking out", s) and not has(r"as long as you don'?t knock out|hp away from being knocked out|^unless this attack knocks out|(isn'?t|doesn'?t|not) (be )?(knocked|knock) out|unless (that|this) attack knocks out|unless that pokemon gets knocked out|even if @ is knocked out|discarded when that pokemon is knocked out", s):
            if has(r"^(that pokemon|the defending pokemon|it|@|each of them|the chosen pokemon) (is|are) (now )?knocked out|knock (it|that pokemon|out the defending|out that|out 1)|^knock out|then (that pokemon|the defending pokemon) is knocked out|(defending pokemon|that pokemon) is knocked out$|are now knocked out", core) \
                    and not has(r"^(when|whenever|unless|if)\b", core):
                tags.add("instant_ko")
            elif has(r", knock out that pokemon", s):
                tags.add("instant_ko")
                tags.add("ko_on")
            elif has(r", it is knocked out$", s):
                tags.add("instant_ko")
            elif has(r"(you may |^)knock out @(?![\w'])|^@ is (now )?knocked out|both @ and [^.]*knocked out|counts as knocking out @", s):
                tags.add("self_ko")
            else:
                tags.add("ko_on")
            if has(r"both @ and the defending pokemon are now knocked out", s):
                tags.add("self_ko")           # a sacrifice: your own Pokemon goes down with it
        # survives a Knock Out ("...is not Knocked Out and its remaining HP becomes 10")
        if has(r"(isn'?t|is not) knocked out|remaining hp becomes? 10", s):
            tags.add("ko_prevent")
        if has(r"counts as knocking out @", s):
            tags.add("self_ko")

        # ── counter attack ───────────────────────────────────────────────────────
        if has(r"(damage|damage counters?) (to|on) the attacking pokemon|attacking pokemon[^.]*damage counter|(put|does) [^.]*on the attacking pokemon|attacks the defending pokemon for an equal|attacks your opponent'?s active pokemon for|if the defending pokemon tries to retreat, do \d+ damage|to the pokemon that knocked out @|the attacking pokemon (is now|becomes)|by the defending pokemon'?s attack[^.]*the defending pokemon becomes", s):
            tags.add("counter_damage")
        # retaliation spread over two sentences / clauses: "if an attack does damage to @ ... flip a
        # coin. if heads, your opponent's active pokemon is now confused"
        elif has(r"(attack|attacks) (does damage to|damages) (@|it\b)|@ is damaged by an? (opponent'?s )?attack|whenever your opponent'?s attack damages @", ctx) \
                and has(r"(opponent'?s active pokemon|defending pokemon|attacking pokemon) (is now|becomes)|put \d+ damage counters? on the (defending|attacking) pokemon", s):
            tags.add("counter_damage")

        # ── copied / borrowed attacks ────────────────────────────────────────────
        if has(r"copies? (that|this|the|an|every|a|all) (of )?(the )?(\w+ )?attack|copy of every attack|(use|uses) [^.]*attacks? (on this card|of|from)|(may|my) us(e)? this card'?s attack|can use attacks on this card|as (this|its) attack|use (any|that|1) of [^.]*attacks|use the attacks? of|final result of that attack|use the effect (on|of) that card|use the effect of a supporter card|use that card as if it were in your hand|copies all of|same card as the defending", s):
            tags.add("copy_attack")

        # ── heal ─────────────────────────────────────────────────────────────────
        if (has(r"\bremoves?\b[^.]*\bdamage counters?\b|\bdamage counters?\b[^.]*\bremoves? them\b|\bdamage counters?\b[^.]*\bremove (\d+|all|1|2|them|it|of them)|\bheal(s|ed)?\b|damage counters? (are|is) removed", s)
                and not has(r"^for each (?!heads)|for each damage counter you", s)
                and not (has(r"remove [^.]*from the defending pokemon", s) and not has(r"\byour\b", s))):
            tags.add("heal")
        elif has(r"remove [^.]*damage counters? from the defending pokemon|defending pokemon (was|is) asleep, it is no longer|^your opponent may draw", s):
            tags.add("drawback")      # helps the opponent: heals / wakes / feeds the other side

        # ── defence ──────────────────────────────────────────────────────────────
        if has(r"reduced by|reduce [^.]*damage|damage[^.]*reduce|\b\d+ less damage|less damage|-\d+ damage|damage[^.]* minus|half (the|of the|that) damage|in half|of that damage to @ instead", s) \
                and not has(r"resistance [^.]*only reduces|damage minus|minus the (number|remaining)|damage from this attack is reduced|resistance is reduced|half (the|that) damage done[^.]*remove|remove[^.]*half (the|that) damage", s):
            if has(r"damage done to your opponent'?s pokemon by [^.]*is reduced", s):
                tags.add("drawback")      # the card's own Pokemon hit softer
            else:
                tags.add("damage_reduce")
        if has(r"prevent all (damage|effects)|prevent [^.]*damage|no damage is done|can'?t be damaged|is not damaged|does no damage to @|doesn'?t take any damage|do not take damage|don'?t take damage|that attack does no damage|not affected by attacks", s):
            tags.add("prevent_damage")
        if has(r"\+\d+ hp|hp (is|gets|by) \d+ (more|higher)|\d+ more hp|maximum hp [^.]*(is now|becomes|by \d+)|gets? \+", s):
            tags.add("hp_boost")
        # TYPE CHANGE = the Pokemon's own type changes (not its Weakness, not its Energy's type)
        if has(r"(change|changes|changed)[^.]*\btype\b(?! of your choice)|is now (a |an )?\w+ (type|pokemon)|\btype (\(color\) )?(is|becomes) |becomes? (a |an )?\w+ type|counts? as \w+ type|@ is the same type as|is \w+, [^.]*and \w+ type|is (both )?\w+ and \w+ type|is now the type", s) \
                and not has(r"isn'?t affected by|energy (card )?counts as every type", s):
            tags.add("type_change")
        # WEAKNESS / RESISTANCE as a lasting change (an attack that just ignores Resistance for itself
        # is Ignore Defences only)
        if has(r"(has|have) no (weakness|resistance)|(change|changes|changed)[^.]*(weakness|resistance)|(weakness|resistance) (is|becomes) (now )?|(weakness|resistance) to \w+ (instead|is)|(gets|has) weakness|weakness of|resistance is reduced|resistance [^.]*only reduces|weakness, [^.]*change it", s) \
                and not has(r"isn'?t affected by", s):
            tags.add("weak_resist")
        elif not is_attack and has(r"(don'?t|do not|ignore) (apply )?(\w+ )?(weakness|resistance)\b[^.]*\b(for all|to any|when|on each)|by your [^.]*isn'?t affected by (weakness|resistance)|(any|all) damage done by attacks from [^.]*(weakness|resistance)", s):
            tags.add("weak_resist")
        if has(r"special conditions?, remove all of them|can'?t become affected by|remove all (of )?those effects|no longer (asleep|confused|paralyzed|poisoned|burned|affected)|remove (all |any )?special conditions?|removes? [^.]*special conditions?|recovers? from (all |any )?special conditions?|can'?t (be|become) (affected by (any )?special|asleep|confused|paralyzed|poisoned|burned)|isn'?t affected by (any )?special conditions?|special conditions? [^.]*(removed|recover)|is not affected by special|retreat even (when|if) it is (asleep|paralyzed)", s) \
                and not has(r"can'?t be removed by evolving|defending pokemon (was|is no longer)|just as if you had evolved", s):
            tags.add("status_cure")

        # ── special conditions ───────────────────────────────────────────────────
        if has(r"choose 1 special condition|affected by that special condition|any special condition of your choice|special condition of your choice", s):
            tags.update(STATUS_WORDS.keys())
        # Wobbuffet: "...the Defending Pokemon becomes affected by the same Special Condition"
        if has(r"affected by the same special condition", s):
            for k, w in STATUS_WORDS.items():
                if re.search(r"\b" + w + r"\b", s):
                    tags.add(k)
        found = COND_RE.findall(s)
        if found:
            # a condition being CURED / CHECKED / BLOCKED is not an inflict
            inflict = has(r"\bis now\b|\bare now\b|\bis then\b|make [^.]*\b(asleep|confused|paralyzed|poisoned|burned)|\bbecomes?\b|now (asleep|confused|paralyzed|poisoned|burned)|\bchoose\b[^.]*(asleep|confused|paralyzed|poisoned|burned)|(asleep|confused|paralyzed|poisoned|burned) (and|or) (asleep|confused|paralyzed|poisoned|burned)$", s) \
                and not has(r"no longer|can'?t (be|become) (asleep|confused|paralyzed|poisoned|burned)|isn'?t (asleep|confused|paralyzed|poisoned|burned)|if @ becomes|even when it is", s)
            if inflict:
                both = has(r"both (the defending pokemon and @|@ and the defending pokemon)|@ and the defending pokemon are now|the defending pokemon and @ are now", s)
                own_only = has(r"(one|1) of your active pokemon is now|@ and your other active pokemon", s)
                self_hit = both or own_only or has(r"(^|, |then |and )@ (is|are) now|^@ is now", s)
                other_hit = not own_only and has(r"(defending|opponent'?s|each of your opponent|that pokemon|1 of your opponent|attacking pokemon|his or her|the pokemon|each pokemon|chosen|either|it is now|they are now|each active|both)", s.replace("@ is now", ""))
                if self_hit:
                    tags.add("self_status")
                if other_hit or not self_hit:
                    # only the words after the target, so "@ is now asleep. ...defending is now confused" stays right
                    seg = s
                    if both:
                        seg = s
                    elif self_hit and has(r"defending pokemon is now", s):
                        seg = s[s.index("defending pokemon is now"):]
                    elif self_hit:
                        seg = ""
                    for k, w in STATUS_WORDS.items():
                        if re.search(r"\b" + w + r"\b", seg):
                            tags.add(k)
        # Sleep made harder to wake from ("flips 2 coins ... if either coin is tails, that pokemon is
        # still asleep") is a Sleep card
        if has(r"\bis still asleep", s):
            tags.add("sleep")

        # ── energy ───────────────────────────────────────────────────────────────
        if has(r"energy", s):
            # Read the Energy rules WITHOUT a leading energy condition: "if @ has water energy attached
            # to it, remove 2 damage counters" is a heal, not Energy being discarded.
            s_full = s
            s = re.sub(r"^(if @ has [^,]*energy[^,]*attached to it|as long as [^,]*attached[^,]*), ", "", s)
            from_hand = has(r"\bdiscard [^.]*from your hand|energy cards? from your hand", s)
            # "remove 1 Fire Energy from @ and attach it to your new Active Pokemon" - a move
            remove_move = has(r"\bremove (\w+ ){0,4}energy[^.]*\b(from|attached to) @[^.]*\battach (it|them)\b", s)
            if remove_move or ((has(r"\bmove|attached to [^.]*(and )?(attach|move) (it|them|that|those)|take [^.]*energy[^.]*attached to [^.]*attach|switch [^.]*energy|energy[^.]*attached [^.]*switch them|take (1|\d+|all) of those (\w+ )?energy cards and attach|energy [^.]*from 1 of your pokemon to another|(attach|move)[^.]*energy[^.]*attached to[^.]* to (another|1 of your|1 of his)", s)
                    and not has(r"\bremove", s)) or has(r"\bmove (\w+ ){0,4}energy", s)) \
                    and not has(r"moves? copies", s) \
                    and not (has(r"search your (deck|discard)", s) and not has(r"\bmove", s)):
                tags.add("energy_move")
            # Energy picked off one Pokemon in one sentence and attached elsewhere in the next is a
            # MOVE, not new Energy (Dark Magneton's Magnetic Lines).
            if remove_move:
                pass
            elif has(r"attach (that|the chosen|those) energy( cards?)? to", s) and has(r"energy[^.]*attached to|choose 1 of them", prev_s):
                tags.add("energy_move")
            elif has(r"\battach(es|ed)?\b", s) and not has(r"when you attach (this|@)|when you play this|^attach (@|this card|rainbow|multi|dark metal|miracle)|can be attached only|attached to it$|can'?t attach|^if [^,]*\battach(es)?\b|this doesn'?t use up|take (1|\d+|all) of those (\w+ )?energy cards and attach|whenever (you|your opponent) attach|when you attach|each time [^,]*attach|^attach the \w+ energy, and then discard|for each [^.]*attached|energy attached to[^.]*(is|are|provides|becomes|counts)", s) \
                    and not has(r"(take|move|choose) [^.]*energy[^.]*attached to[^.]*attach|when your opponent attaches|whenever (a|any) player attaches|when that player attaches|^to attach", s) \
                    and has(r"energy[^.]*\battached it to|attach(es)? (\w+ ){0,6}energy|energy[^.]*\battach (it|them|that|those|the|up to)|attach (it|them) to|and attach|attach (\d+|1|2|all|up to \d+) of them", s):
                tags.add("energy_attach")
            # "Return @ and all Energy cards attached to it to your hand" - the Pokemon itself goes home
            self_bounce = has(r"(return|shuffle|put)s? @ and all (\w+ )?(energy )?cards attached to it (to|into) your (hand|deck)", s)
            if self_bounce:
                tags.add("bounce")
            # Energy discarded off @ as the first step of an attack that then hits the opponent
            # ("discard 2 fire energy attached to @ and then choose 1 of your opponent's pokemon")
            if has(r"(^|, |\band |\bthen )discard [^.]*?energy( cards?)? attached to @(?![\w'])", s):
                tags.add("energy_discard")
            elif has(r"\bdiscard (1|\d+|all|any) of those energy cards\b|\bdiscard (1|\d+|all) of those cards\b", s) and has(r"energy[^.]*attached to @(?![\w'])", whole):
                tags.add("energy_discard")
            if self_bounce or remove_move:
                pass
            elif has(r"\bdiscard|\bremove|return[^.]*hand|shuffle[^.]*(into|in) (his or her|your|their)[^.]*deck|put [^.]*energy[^.]*(into|on|in|at) [^.]*(hand|deck)|bottom of", s) \
                    and not has(r"^if [^,]*\bdiscard|for each energy|discarded this way|for each [^.]*discarded|discard pile[^.]*(attach|into your hand|on top)|from your discard pile|in your discard pile|^attach|^whenever you attach|can'?t (be )?(removed|discard)|(up to|equal to) the number of [^.]*energy", s):
                opp_side = has(r"(defending pokemon|opponent'?s|his or her|1 of your opponent|each of your opponent|the attacking pokemon|your opponent discards|your opponent returns)", s)
                if opp_side and not has(r"to your hand", s) and has(r"energy[^.]*attached to (the defending|1 of (your )?opponent'?s|each of your opponent|your opponent'?s|the attacking|that pokemon|it)|(defending pokemon'?s|opponent'?s) [^.]*energy|your opponent (discards|returns) [^.]*energy|choose [^.]*energy[^.]*(defending|opponent'?s)|defending pokemon has [^.]*energy[^.]*(discard|choose)", s):
                    tags.add("energy_remove")
                if not from_hand and has(r"energy[^.]*attached to (@|it\b|your|1 of your( own)?|each of your|any (number )?of your|all of your|that pokemon|the pokemon)|discard (all|\d+|a|an|that many|each|any|up to \d+)? ?(\w+ )?(\w+ )?energy( cards?)?( attached)?( to @| from @| from it)?$|in order to use this attack|discard (all|\d+) energy|energy [^.]*from @", s) \
                        and not has(r"defending pokemon|opponent'?s pokemon|attached to 1 of your opponent|attached to your opponent|attached to the defending|your opponent (discards|returns)|doesn'?t discard", s) \
                        and not (has(r"remove[^.]*damage counters?", s) and not has(r"\bdiscard", s)):
                    if src == SRC_CARD and has(r"^(at the end of (your|each) turn|when your turn ends|(if|when) the pokemon [^,]*energy is attached to (isn'?t|is not|doesn'?t|is no longer)|if [^,]*is attached to [^,]*(isn'?t|is not)),? [^.]*discard", s):
                        tags.add("drawback")   # a Special Energy that falls off by itself
                    else:
                        tags.add("energy_discard")
            if has(r"\bdiscard [^.]*from your hand", s) and not has(r"attach", s):
                tags.add("discard_hand")
            # Saffron City Gym: "that player may return 1 basic Energy card attached to 1 of his or
            # her Pokemon ... to his or her hand" - each player's OWN Energy.
            if has(r"that player may (return|discard) [^.]*energy[^.]*attached to 1 of his or her", s):
                tags.add("energy_discard")
            # A Stadium / Power that DOWNGRADES Special Energy ("now provides only 1 Colorless Energy",
            # "Special Energy cards provide Colorless Energy instead") stops Energy - not a supply
            downgrade = has(r"special energy[^.]*\bprovides? (only )?(1 )?colorless energy|now provides? only 1 colorless", s)
            if downgrade:
                tags.add("energy_lock")
            elif has(r"^if [^,]*\bprovides?\b", s):
                pass      # "if all Energy attached to @ provide 2 Fire Energy, discard all of them"
            elif has(r"\bprovides? (\w+ ){0,3}(every type|\d energy|2 energy|two|all types|both|any type|\w+ and \w+ energy|darkness and metal)|\bcount(s)? as (every|2)|\b(provides?|counts? as) (\d|2|3) |energy (cards? )?(you have attached )?[^.]*\bprovides? (\d|2|every|both|\w+ energy instead)|instead provides|\bprovides (\w+)\2\b|\bprovides (darkness|fire|water|grass|lightning|psychic|fighting|metal|colorless){2,} energy|\bas an? (\w+ )?energy card|this card is a special energy|energy of all types|provides every type|\b(turn|turns) [^.]*energy[^.]*into \w+ energy|\bbecomes? \w+ energy|treat [^.]*energy[^.]*as (that|any|every) type|all energy [^.]*\b(is|are|provides?) \w+", s):
                tags.add("energy_supply")
            s = s_full
        # Energy chosen off the Defending Pokemon in one sentence, sent back in the next (Minun's
        # Minus Energy: "Your opponent returns that card to his or her hand").
        if has(r"returns? that (card|energy)[^.]*\b(hand|deck)\b|shuffles (those|that) cards? into his or her deck|choose (1|\d+) of those (energy )?cards and discard (it|them)", s) \
                and has(r"energy (cards? )?attached to (the defending|1 of your opponent)|defending pokemon has any energy|energy cards? attached to the defending", prev_s):
            tags.add("energy_remove")
        if has(r"\bdiscard an? energy card from (each|the) defending pokemon", s):
            tags.add("energy_remove")
        # "your opponent moves that card to 1 of his or her other pokemon" (the Energy chosen before)
        if has(r"\bmoves? that card to", s) and has(r"energy", prev_s):
            tags.add("energy_move")
        # "if there are any lightning energy cards in your discard pile, flip a coin. if heads, attach
        # 1 of them to @" - the Energy is named only in the sentence before
        if not has(r"energy", s) and has(r"\battach (\d+ |all )?(of )?(them|those|it)\b", s) and has(r"energy", prev_s) \
                and not has(r"pokemon tool|technical machine", prev_s):
            tags.add("energy_attach")
            if has(r"discard pile", prev_s):
                tags.add("recover")
        # ATTACK costs only — retreat costs have their own two categories (retreat_aid / retreat_lock)
        if has(r"attacks? costs?[^.]*(more|less|\+|-|\d+ (more|less))|(attack|attacks|to use|to attack)[^.]*costs? (\w+ ){0,4}(more|less|additional)|(more|less|additional|extra) energy (to use|in order to use|to attack)|(attack'?s?|attacks'?) energy cost[^.]* (more|less|is reduced|is increased|is now)|doesn'?t have to pay (for )?(that|the|its) attack'?s? energy cost|without paying [^.]*energy cost|ignore [^.]*energy necessary to use|costs? (\w+ ){0,3}(more|less) (\w+ )?(energy )?to use", s) \
                and not has(r"retreat", s):
            tags.add("cost_change")

        # ── cards ────────────────────────────────────────────────────────────────
        # Draws for the OPPONENT alone ("your opponent draws 3 cards") are not card draw for you.
        if has(r"\bdraws? (a|an|\d+|up to|cards?|that many|\w+ cards?|until|the|1|2|3|4|5|6|7)\b|\bdraw (a )?number of cards|\bdraw cards|\bdraw (twice|\w+ times) that many", s) and not has(r"can'?t draw|doesn'?t draw|instead of draw|skip", s) \
                and not (has(r"your opponent (may |then )?draws?|he or she draws|that player draws|opponent shuffles his or her hand[^.]*draws", s)
                         and not has(r"\byou (may )?draw\b|each player|then draw\b|and draw\b", s)
                         and not (has(r"that player draws", s) and has(r"each player'?s turn|each of his or her turns", whole))):
            tags.add("draw")
        if has(r"\bsearch(es)? (your|his or her|their|the|either|each|that player'?s|your opponent'?s) deck|\bsearch(es)? [^.]*\bdeck\b|look at the top \d+ cards[^.]*(choose|put [^.]*into your hand)|look (through|at) your deck|(card|cards) (from|in) your deck (and|for|into)|(any|1|2) cards? from your deck|from your deck[^.]*(into your hand|onto)|trade [^.]*from your deck", s) \
                and not has(r"put them back|your opponent may search|opponent searches|and switch it with", s) \
                and not (has(r"search(es)? (your|his or her) discard pile", s) and not has(r"search(es)? (your|his or her|your opponent'?s) deck", s)):
            tags.add("search_deck")
        if has(r"^you do the same", s) and has(r"top \d+ cards[^.]*|into his or her hand", prev_s):
            tags.add("search_deck")
        if has(r"(put|puts|place|places)\b[^.]*\bonto (your|his or her|their) bench|(put|place)s? [^.]*basic pokemon[^.]*on(to)? (your|his or her|their) bench|onto (your|his or her) bench|(on|to) your bench as|put it on your bench|play [^.]*onto your bench", s) \
                and not has(r"^(if [^,]*\bbench\b|whenever|when you put|once during your turn, when you put)|^(once during your turn, )?when you (play|put) @ (from your hand )?(onto|on|to) your bench(?![^.]*\bputs? (it|them)\b)|(?<!onto )(?<!on )his or her bench|old active|whenever a player puts", s):
            tags.add("bench_call")
        elif has(r"\bonto your benches\b|\bonto that player'?s bench", s):
            tags.add("bench_call")
        if has(r"discard pile", s) and has(r"(into|to|in) (your|his or her|their|that player'?s|the owner'?s|its owner'?s) hand|on top of (your|his or her) deck|(into|in) (your|his or her|their) deck|onto (your|his or her) bench|(put|return|shuffle|take|search|attach)[^.]*(from|in|into) (your|his or her) discard pile|on (your|his or her) bench|recover|from (your|his or her) discard pile|in your discard pile, attach|search your discard pile", s) \
                and not has(r"discard [^.]*(from your hand|your hand) [^.]*discard pile$|for each (?!heads\b)[^.,]*discard pile|^if [^,]*discard pile, this attack|^treat|put (it|them) into (his or her|your opponent'?s) discard pile|your opponent may|stays in that discard pile", s) \
                and not has(r"^if [^,]*in your discard pile, (?![^.]*\b(attach|into your hand|put it)\b)", s) \
                and not (has(r"(his or her|your opponent'?s) discard pile", s) and not has(r"your discard pile|each player|\b(a|that|the) player\b|\bhe or she\b", s)):
            tags.add("recover")
        if has(r"^if there are any [^,]*in your discard pile, (choose|search)[^.]*\b(attach|into your hand)", s) \
                or has(r"any player'?s discard pile", s):
            tags.add("recover")
        if has(r"you may do the same", s) and has(r"discard pile", whole):
            tags.add("recover")
        if has(r"\bdiscards [^.]*return that [^.]*card to its owner'?s hand", s):
            tags.add("recover")       # Energy knocked off comes back to its owner's hand
        # "flip a coin. if tails, discard 1 of those cards" - the Energy named sentences earlier
        if not has(r"energy", s) and has(r"\bdiscard (1|\d+|all) of those cards\b", s) and has(r"energy[^.]*attached to @(?![\w'])", whole):
            tags.add("energy_discard")
        if has(r"stays in that discard pile", s):
            tags.add("recover")       # a Stadium that stops cards coming back out of the discard pile
        if has(r"discard pile from play, return it to your hand|is put into your discard pile[^.]*return", s):
            tags.add("recover")
        # a Stadium's "a player may discard ... from his or her hand" is that player's OWN hand
        own_hand = has(r"\b(a|that|the) player (may|must|does|chooses|reveals|shows)\b|\bif (that|the) player does, he or she|\bhe or she (may|must) search his or her", s) \
            and not has(r"\byour opponent\b", s)
        if has(r"\bdiscard\b[^.]*\bfrom your hand|discard your hand|discard (\d+|a|an|any|1|2|3|up to \d+|that many|all)? ?(other )?(\w+ )?(\w+ )?cards? in your hand|discard \d+ of the (other )?cards in your hand|each player discards (cards|\d+ cards?|[^.]*\bhand\b)", s) \
                or (own_hand and has(r"\bdiscards? [^.]*from his or her hand", s)):
            tags.add("discard_hand")
        if own_hand and has(r"must discard [^.]*in order to play", s):
            tags.add("trainer_lock")      # a tax on playing certain Trainers
        if has(r"^your opponent does the same", s) and has(r"\bhand\b", prev_s):
            tags.add("hand_disrupt")
        if has(r"opponent'?s hand|look at his or her hand", whole) and has(r"(shuffles?|puts?) (that|those|the|it|them)( cards?)? (into|at the bottom of|on the bottom of|on top of) his or her deck|\bput them into his or her deck|discard (it|them|that card|those cards)\b|discards the card you chose|choose from it|you find there and put it onto|you find there into his or her deck|(put|puts) (it|them|any number of them) (on|onto) (his or her|your opponent'?s) bench", s):
            tags.add("hand_disrupt")
        # just LOOKING at the opponent's hand is peek; disruption needs a card to leave it
        if not own_hand and has(r"cards? (from|in) your opponent'?s hand|(choose[^.]*from|discard[^.]*from|random[^.]*from) (his or her|your opponent'?s) hand|your opponent (discards (a card|\d+ cards?|cards|a number of cards|[^.]*from his or her hand)|shuffles his or her hand|sets aside)|(opponent|each player|that player)[^.]*shuffles? (his or her|their) hand|each player discards cards until|have your opponent (discard|shuffle (?!those|it into)(his or her hand|the cards you chose))|(each player|both players) (shuffles?|discards?) [^.]*hand|show each other your hands|discards? a number of cards until", s) \
                and not has(r"count the number of cards in|number of cards in your opponent'?s hand(?![^.]*discards)|if your opponent has \d+ or more cards in(?![^.]*discards)|whenever your opponent (attaches|plays)|when your opponent attaches|draw cards until you have the same|(to|into) (your opponent'?s|his or her) hand$|for each card in your opponent'?s hand|^count|can'?t attach|(active|benched|defending) pokemon and all cards|look at (one of the following|a random card)|you find there as the effect", s):
            tags.add("hand_disrupt")
        if has(r"^if it'?s an? \w+ card, (discard it|put it (in|into) (your opponent'?s|his or her) discard pile)", s) and has(r"top card of", prev_s):
            tags.add("mill")
        if has(r"discard (\w+ ){0,3}cards? from the top of|discard the top (\d+ |\w+ |that many |)cards?|discard (the )?top \w+ cards?|top card of [^.]*deck[^.]*discard|discards? the top|top (\d+|\w+) cards? of (your|your opponent'?s|his or her|either|each|their) deck[^.]*discard", s) \
                and not has(r"top evolution card|remove up to", s):
            tags.add("mill")
        if has(r"\blook at\b|\brearrange|in any order|\breveals?\b|\bshows?\b (it|them|your|his|that|those|the)|turn [^.]*(prize|face up)|face up|put them back", s) \
                and not has(r"^look at the top \d+ cards[^.]*put [^.]*into your hand$|without looking|don'?t look|show that card to you|show (it|them) to the opponent|reveals? his or her hand|turn those cards face up", s) \
                and not (has(r"show (it|them|that card|those cards|the cards?|your hand) to (your opponent|all players)|shows? (it |them )?(to )?his or her opponent|without showing|don'?t look|nobody may look|search your (deck|discard pile)|reveal cards from your deck until", s)
                         and not has(r"show the top \d+ cards|\blook at\b", s)):
            tags.add("peek")
        # Prize MANIPULATION only - "if you have more Prize cards left" is a condition, not an effect
        if has(r"prize", s) and not has(r"\blook at\b(?![^.]*\b(take|switch|swap|shuffle|put)\b)", s) and not has(r"if (you|your opponent) (has|have) (more|less|fewer|only|exactly|\d+ or (more|fewer|less)|the same number of)[^.]*prize|prize cards? (left|your opponent has taken|you have taken)|count[^.]*prize|number of (your )?prize|as many prize", s):
            tags.add("prize")
        if has(r"(return|put|shuffle|puts|returns|shuffles|take|takes)s?\b[^.]*\b(and all|and any|all|with all) cards attached[^.]*\b(hand|deck)|return (\w+ ){0,3}(basic pokemon|pokemon) card [^.]*hand|(return|shuffle|put)s? (@|the defending pokemon|that pokemon|1 of your (benched )?pokemon|it) and all cards attached|(return|shuffle|put)s? [^.]*(defending pokemon|benched pokemon|@|pokemon in play)[^.]*(into|to|on) (your|his or her|its owner'?s|that player'?s|their) (hand|deck)|scoop|pick up|put @ on the bottom of your deck", s) \
                and not has(r"discard pile|energy (cards? )?attached to|^return \d+ energy|put @ onto your bench", s):
            tags.add("bounce")
        # Deck order / cards slipped INTO a deck - no cards gained (Mankey, Unown [L], Slowking...)
        if (len(sents) == 1 and has(r"^shuffle (your|your opponent'?s) deck$", s)) \
                or has(r"(put|puts|place|return)s? [^.]*\b(on top of|at the bottom of|on the bottom of|to the bottom of) (your opponent'?s|his or her|their) deck|in any order[^.]*(your opponent'?s|his or her) deck|(your opponent'?s|his or her) deck in any order|each player shuffles his or her deck|you may shuffle his or her deck|have your opponent shuffle his or her deck|switch 1 of your prizes with the top card|prize cards?[^.]*shuffle them into his or her deck|shuffle them into his or her deck", s) \
                and not has(r"from (his or her|your opponent'?s) hand|in (his or her|your opponent'?s) hand|\bhand\b[^.]*\bdeck|attached|energy", s) \
                and not has(r"opponent'?s hand", prev_s) \
                and not has(r"^(then|either way), each player shuffles|from his or her discard pile|evolved pokemon|evolution card", s):
            tags.add("deck_disrupt")

        # ── board ───────────────────────────────────────────────────────────────
        # SWITCH = your own Active changes. PULL (gust) = your opponent's Active changes. "Switch" alone
        # says nothing about whose Pokemon: Gust of Wind is "switch 1 of your opponent's Benched Pokemon
        # with his or her Active Pokemon", Whirlwind is "your opponent switches the Defending Pokemon
        # with 1 of his or her Benched Pokemon" - both PULL only.
        if has(r"\bswitch", s) and not has(r"switch the number of damage counters|switch (all )?(the )?damage counters|switch 1 of your prizes|switch it with the top card|search your (deck|discard pile)[^.]*switch it with|switch that card with", s):
            if has(r"your opponent switches|(switch|switches) [^.]*(defending pokemon|opponent'?s active|his or her active|with 1 of (your opponent'?s|his or her|their) benched)|(opponent'?s|his or her) (\w+ )?benched pokemon[^.]*switch|switch 1 of (your opponent'?s|the defending)|opponent chooses [^.]*switch|each player switches", s) \
                    and not has(r"opponent chooses 1 of your benched|switches it with your active", s):
                tags.add("gust")
            if has(r"(switch|switches) (@|your active|1 of your active|this pokemon|the attacking pokemon)\b|with 1 of your (own )?benched|with your active|\byou switch|switch [^.]*@ with|switches it with your active|each player switches|switch the active pokemon you|switch [^.]*with 1 of your benched|chooses 1 of your benched", s) \
                    and not (has(r"your opponent switches (his|the defending)", s) and not has(r"\byou switch", s)):
                tags.add("switch")
            elif has(r"switch (1|\d+) of them with @(?![\w'])", s):
                tags.add("switch")
        if has(r"into play as your active pokemon", s):
            tags.add("switch")
        if has(r"no retreat cost|retreat cost[^.]*(is 0|less|reduced|zero|for free|is (\w+ )?less)|retreat (for free|without (discarding|paying))|(lower|reduce)s? [^.]*retreat|retreat cost (\w+ ){0,3}-|retreat \w+ (for|without)|doesn'?t have to discard [^.]*retreat|ignore [^.]*retreat cost|retreat cost of [^.]*0|(retreat|retreats) [^.]*free|less to retreat|no energy cost to retreat|can retreat even|instead of discarding energy", s) \
                and not has(r"additional|more to retreat", s):
            tags.add("retreat_aid")
        if has(r"can'?t retreat|retreat cost[^.]*(more|increase|\+)|(raise|increase)s? [^.]*retreat|can'?t be switched|must discard [^.]*to retreat|unable to retreat|more to retreat|additional \w+ to retreat|tries to retreat|whenever the defending pokemon retreats|opponent'?s active pokemon retreats", s) \
                and not has(r"^@ has no attacks|clefairy doll|fossil|can'?t retreat, and can'?t be|has no attacks", s):
            # a Tool / Special Energy that stops ITS OWN wearer retreating is the owner's drawback
            if has(r"pokemon (this card|[\w ]+ energy|[\w ]+ is) (is )?attached to can'?t retreat|you must pay an additional", s):
                tags.add("drawback")
            else:
                tags.add("retreat_lock")
        if has(r"(defending pokemon|that pokemon|pokemon|dunsparce|ex|it|them) can'?t (attack|use)|can'?t use that attack|tries to attack[^.]*(flip|nothing)|attacks?[^.]*(your opponent flips|opponent must flip)|whenever the defending pokemon (attacks|tries)|your opponent can'?t (attack|use)|can'?t attack @|that attack does nothing|has to flip a coin|must flip|can'?t attack or use|opponent'?s @ can'?t attack", s) \
                and not has(r"^@ can'?t|^this attack does nothing|tails, this attack does nothing|^@ (\w+ )?can'?t|can'?t use this attack|this pokemon can'?t|^(this|@) can'?t", s) \
                and not (has(r"can'?t use (any )?(poke|pokemon power)", s) and not has(r"can'?t attack|can'?t use (any )?attacks?|can'?t use that attack", s)):
            # "whenever @ attacks, flip 2 coins. if both are tails, that attack does nothing" - its own
            if has(r"whenever @ attacks", whole):
                tags.add("drawback")
            else:
                tags.add("attack_lock")
        if ((has(r"@ can'?t (attack|use)|can'?t use this attack|^this pokemon can'?t attack|can'?t attack during your next turn|this attack can'?t be used during your next turn", s)
                and not has(r"defending|opponent|unless", s)) or has(r"(^|, |then )@ can'?t (attack|use)", s)) \
                and not has(r"if your bench (is|if) (full|empty)", s):
            tags.add("self_lock")
            if src == SRC_POWER:
                tags.add("drawback")
        if has(r"evolv|evolution", s) and not has(r"no longer asleep|whenever your opponent plays", s):
            if has(r"devolv|remove (the )?highest stage|discard all evolution cards|(return|discard|put|takes?|shuffle)s? (the )?highest stage|highest stage evolution card[^.]*(hand|deck|discard|remove)|remove [^.]*evolution card", s) \
                    and not has(r"can'?t be removed by evolving|can'?t evolve, devolve", s):
                tags.add("devolve")
            elif not has(r"@ can'?t evolve", s) and has(r"can'?t (evolve|be evolved)|no (more )?evolution cards? can be played|can'?t play [^.]*(evolution|to evolve)|cannot evolve|evolution cards? [^.]*can'?t be played|neither player can (play [^.]*(evolution|to evolve)|evolve)", s):
                tags.add("evo_block")
            elif has(r"counts as evolving|(put|attach|play)[^.]*(evolution card|card that evolves|stage 2|stage 1|from your hand onto|on top of)[^.]*(on|onto|to) (@|that pokemon|it|the matching|1 of your)|evolve (it|that pokemon|@|1 of your|your|them)[^.]*(right away|the same|even|during|first turn)|(can|may) evolve [^.]*(the turn|first turn|same turn|right away|even|during)|evolve during (your|the) first turn|evolves? (\w+ ){0,3}(the turn|that turn) (it|they) (was|were|is|are) (played|put)|skip|search your deck for (a|an|up to \d+)? ?cards? that evolves? [^.]*(put|attach)|instead of (the )?(stage 1|basic)", s) \
                    and not has(r"doesn'?t count as evolving|into your hand|onto your bench", s):
                tags.add("evolve")
        if has(r"counts as evolving", s) and not has(r"doesn'?t count as evolving", s):
            tags.add("evolve")
        if has(r"as if (it|this card|@|[\w' ]+) were a basic pokemon", s):
            tags.add("play_as_pokemon")
        # ── change form: one Pokemon swapped for another card in its place (Castform, Deoxys, Ditto,
        # Unown, Swoop! Teleporter, Surprise! Time Machine, Brock's Ninetales...)
        if has(r"search your (deck|discard pile) for [^.]*(and )?switch it with|treat (it|@) as if it were the same card as|treat @ as if it were that pokemon|search your deck for an evolution card that evolves from that pokemon", s) \
                and not has(r"counts as devolving", whole):
            tags.add("form_change")
        # ── bench size (Giant Stump, Narrow Gym)
        if has(r"can'?t have more than \d+ (benched )?pokemon|may have more than \d+ pokemon on (his or her|their|your) bench|more than \d+ pokemon on (his or her|your|their) bench", s):
            tags.add("bench_size")

        # ── rules & locks ───────────────────────────────────────────────────────
        if has(r"you can'?t play (any more )?trainer", s) and not has(r"opponent", s):
            tags.add("drawback")
        elif has(r"can'?t play (any )?(trainer|supporter|stadium|item|pokemon tool|technical machine)|trainer cards?[^.]*can'?t be played|(can'?t|cannot) (be )?play(ed)? [^.]*(trainer|supporter|stadium|pokemon tool)|can'?t play any cards|can'?t attach (any )?(pokemon tools?|technical machines?)|no trainer cards can be played|the player can'?t play that card", s):
            tags.add("trainer_lock")
        if has(r"(pokemon powers?|poke-powers?|poke-bod(y|ies))[^.]*(stop working|can'?t be used|don'?t work|have no effect)|(can'?t|cannot) (\w+ )?(or )?use (any )?(pokemon powers?|poke-powers?|poke-bod)|(has|have) no (pokemon powers?|poke-powers?|poke-bod)|ignore (all )?(poke-powers?|poke-bod|pokemon powers?)|no poke-powers|can'?t use any poke|(poke-powers?|poke-bod(y|ies)) (of|on) [^.]*(don'?t|can'?t|stop)|powers? and poke-bod|all pokemon powers stop|^that power stops working|, that power stops working", s) \
                and not has(r"^@'?s? (power|poke-power|poke-body) (stops|can'?t)", s):
            tags.add("power_block")
        if has(r"\bmarkers?\b|\b(char|coloring) counters?\b", s):
            tags.add("markers")
        # Entei: "...aren't affected by effects from Trainer cards" - protection, not a Trainer lock
        # Pokemon Tower: discards can't be pulled back - same family as Parasect's protected discard piles
        # (also: attached Energy that can't be discarded / removed by the opponent - Unown [M], Brock's Protection)
        if has(r"(isn'?t|aren'?t) affected by effects from trainer|stays in that discard pile|can'?t discard energy cards from your|energy cards attached to that pokemon can'?t be removed", s):
            tags.add("prevent_damage")
        # ── your opponent can't attach Energy (Dusclops, Dewgong, Regice ex...)
        if has(r"(your opponent|that player|each player|players?) can'?t (play or )?attach [^.]*energy|energy cards? can'?t be attached|^your opponent can'?t [^.]*\band can'?t attach [^.]*energy", s) \
                and not has(r"you can'?t attach [^.]*to @", s):
            tags.add("energy_lock")
        # ── drawbacks the card's OWNER pays ────────────────────────────────────
        if has(r"^to attach [^.]*you must discard", s):
            tags.add("drawback")
        if src == SRC_CARD and has(r"when you attach this card[^.]*\bdoes \d+ damage", s):
            tags.add("drawback")      # Rainbow Energy hurting the Pokemon it goes on
        if has(r"you can'?t attach [^.]*to @|damage done to @[^.]*increased|any damage done to @ [^.]*increased|you must pay an additional|attached to can'?t retreat|discard @ at the end of|^at the end of (every|each|your) turn, put \d+ damage counters? on|whenever you attach [^.]*to @, discard", s):
            tags.add("drawback")

    # ── whole-text clean-ups ───────────────────────────────────────────────────
    if deck_dig:
        tags.add("search_deck")
        if not has(r"in any order|rearrange|opponent'?s hand|his or her deck|prize", whole):
            tags.discard("peek")
        if has(r"discard the (rest|other cards)", whole):
            tags.add("mill")
    if "form_change" in tags and has(r"treat @ as if it were", whole):
        tags -= {"evolve", "evo_block", "devolve"}   # Ditto-style copying of an attached card
    return tags


# ════════════════════════════════════════════════════════════════════════════════════════════
# SYNERGY — text that rewards or needs a SPECIFIC card family. The line drawn:
#   IN:  a named card (another Pokemon, a named Trainer / Special Energy such as Holon Energy or
#        Mysterious Fossil), a name group ("with Dark / Rocket's / Team Magma / Brock in its name"),
#        delta Pokemon ("has δ on its card"), and the card's OWN name when it counts or calls its
#        copies (Magneton per Magneton, Call for Family "for a card named Oddish").
#   OUT: types, stages, Basic / Evolution / "evolves from", Pokemon-ex, generic Trainer kinds, and
#        anything about the OPPONENT's cards ("if the Defending Pokemon is Seviper").
# ════════════════════════════════════════════════════════════════════════════════════════════
_NAME_PREFIX = r"^(dark|light|shining|rocket'?s|team aqua'?s|team magma'?s|holon'?s|[a-z.]+'s|rain|sunny|snow-cloud|imposter|impostor) "
_NAME_SUFFIX = r"( ex| δ| ★| ☆| star| lv\.x| \[[^\]]*\]| [a-z]-?forme?| (attack|defense|speed|normal) forme?)+$"
_BASIC_ENERGY = {"grass energy", "fire energy", "water energy", "lightning energy", "psychic energy",
                 "fighting energy", "darkness energy", "metal energy", "colorless energy"}
_GENERIC_TRAINERS = {"energy removal", "super energy removal", "energy search", "energy retrieval",
                     "super energy retrieval", "pokemon center", "pokemon trader", "pokemon breeder",
                     "pokemon flute", "full heal", "super potion", "max potion", "energy switch",
                     "pokemon catcher", "energy restore", "double colorless energy", "pokemon reversal",
                     "energy recycle system", "pokemon retriever", "energy charge", "item finder",
                     "warp point", "pokemon march", "energy root", "energy removal 2", "gust of wind",
                     "hyper potion", "lucky stadium", "rainbow energy", "multi energy"}
_SYN_NAMES = None       # (pokemon base names, named trainer/energy names), built once


def _base_name(n):
    n = n.lower().replace("é", "e").replace("’", "'")
    return re.sub(_NAME_SUFFIX, "", re.sub(_NAME_PREFIX, "", n)).strip()


def _syn_names(cards):
    global _SYN_NAMES
    if _SYN_NAMES is not None:
        return _SYN_NAMES
    poke, other = set(), set()
    parent = defaultdict(set)
    for c in cards:
        n = c.get("name", "").lower().replace("é", "e").replace("’", "'")
        if c.get("supertype") == "Pokémon":
            b = _base_name(n)
            if len(b) > 2:
                poke.add(b)
            if c.get("evolvesFrom"):
                parent[b].add(_base_name(c["evolvesFrom"]))
        else:
            b = re.sub(r"\s*\(.*\)$", "", n).strip()
            if " " in b and b not in _BASIC_ENERGY and b not in _GENERIC_TRAINERS:
                other.add(b)

    # evolution LINES: each species -> itself + all its ancestors. Ninjask and Shedinja share Nincada
    # but neither evolves into the other, so Ninjask calling Shedinja still counts as synergy.
    def ancestors(x, seen):
        out = {x}
        for p in parent.get(x, ()):
            if p not in seen:
                out |= ancestors(p, seen | {x})
        return out
    lines = {b: ancestors(b, frozenset()) for b in poke}
    _SYN_NAMES = (poke, other, lines)
    return _SYN_NAMES


# Group / self tests. "your other active pokemon" only where it asks for a partner: Plusle / Minun's
# Cheer On, Victreebel's "if your other Active Pokemon is not a Victreebel".
SYN_NAMEGROUP_RE = re.compile(r"\b((?:[\w.']+ or )?[\w.']+(?: [\w.']+)?) in (?:its|their) names?")
SYN_NAMED_RE = re.compile(r"\b(?:named|called) ([\w.' ♀♂-]+?)(?=,| and| or| onto| from| to| in|$)")
SYN_DELTA_RE = re.compile(r"δ on (its|their) card|\bδ pokemon|has δ|with δ|\bδ rainbow")
SYN_PARTNER_RE = re.compile(r"your other active pokemon[^.]*(attacks, you may use|@)")
SYN_SELF_RE = re.compile(r"@ in (its|their) names?|for each (other )?@( |,|$)|(number|total) of (your )?(other )?@( |,|s|$)|at least \d+ @|search your (deck|discard pile) for (a |an |another |up to \d+ |any number of )?(card named )?@( |,|$)|(other|another) @( |,|$)|named @|called @|each @ you have")
# TYPE synergy: your Fire / Metal / Darkness... Pokemon (the TYPE, never "Dark" names)
_TYPES = r"(grass|fire|water|lightning|psychic|fighting|darkness|metal|colorless|dragon)"
SYN_TYPE_RE = re.compile(r"\b" + _TYPES + r"(?: and \w+)?(?: basic| evolved| benched| active)? pokemon\b(?!-ex| powers?| tool)|\bbasic " + _TYPES + r" pokemon\b|\b" + _TYPES + r" or \w+ pokemon\b")
# Gym Leader / team names that make a card someone's Pokemon
_OWNERS = r"(brock|misty|erika|sabrina|koga|blaine|giovanni|lt\.? surge|team aqua|team magma|rocket'?s|an owner|owner)"
# Text before a name/group that puts it on the OPPONENT's side ("if the Defending Pokemon has Team
# Aqua in its name", "your opponent has Kyogre"): an opponent word with no you / your / @ after it.
# Type words that are locks / penalties / a Fossil's own type, not a type theme
SYN_TYPE_SKIP_RE = re.compile(r"can'?t use any poke|counts as a \w+ pokemon|is reduced by|reduced by \d+")
SYN_OPP_RE = re.compile(r"(defending pokemon|your opponent|his or her|opponent'?s|attacks from)(?:(?!\byou\b|\byour\b(?! opponent)|\byours\b|attacking pokemon|@).)*$")
# Gym Leader possessives name a whole card family: "Sabrina's Gastlys", "Brock's Onix"
SYN_OWNER_POSS_RE = re.compile(r"\b(brock|misty|erika|sabrina|koga|blaine|giovanni|lt\.? surge)'s \w+")
SYN_SKIP_RE = re.compile(r"excluding [^)]*$|not named [^.]*$|guesses [^.]*$")
SYN_EVOLVE_RE = re.compile(r"evolv|evolution card|from your hand onto|onto @|on @|from @")
SYN_ONTO_SELF_RE = re.compile(r"(from your hand onto|put it onto|put it on) @")   # only its own line fits on @


def _side_ok(prefix, s=""):
    if SYN_SKIP_RE.search(prefix):
        return False
    m = SYN_OPP_RE.search(prefix)
    # "(both yours and your opponent's)" makes the whole sentence symmetric
    if m and not re.search(r"both yours|yours and", prefix + " " + s):
        # Stadium wording: "each player ... his or her Pokemon with Erika in its name" is EVERY
        # player's own Pokemon, not the opponent's
        if not (m.group(1) == "his or her" and re.search(r"\b(each|that|a|any) player", s)):
            return False
    return True


def _named_group(word, poke):
    """Which synergy group a "X in its name" / "named X" word belongs to."""
    w = re.sub(r"^(an? |the |with |has )+", "", word.strip().lower())
    if w.startswith("unown"):
        return "unown"
    if w in ("dark", "light", "dark or light", "light or dark"):
        return "syn_dark_light"
    if w.startswith("holon"):
        return "syn_holon"
    if re.match(_OWNERS, w):
        return "syn_named"
    first = re.split(r",| or | and ", w)[0].strip()
    if _base_name(first) in poke or first in poke:
        return "syn_species"
    return "syn_named"


def _other_group(nm):
    if "react energy" in nm:
        return "syn_react"
    if nm.startswith("holon") or "holon energy" in nm:
        return "syn_holon"
    if "δ" in nm:
        return "syn_delta"
    return "syn_named"


def synergy(sents, card, own_name):
    """The SET of synergy groups this text belongs to (empty = none). Unown cards never get one -
    they have their own "unown" filter instead."""
    poke, other, lines = _syn_names(None)
    own = own_name.lower().replace("é", "e")
    groups = set()
    if own.startswith("unown") or own in ("darkness energy", "metal energy"):
        return groups
    own_base = _base_name(own) if card.get("supertype") == "Pokémon" else ""
    own_line = lines.get(own_base, set())
    # a text that evolves anywhere ("choose your Hoppips and Skiploom. ...search for a card that
    # evolves from that Pokemon") names its own line as evolution, not as a partner
    evolving_any = any(SYN_EVOLVE_RE.search(x) for x in sents)
    prev = ""
    for s in sents:
        prev_s, prev = prev, s
        # React Energy is a theme on either side ("reduced by 10 for each React Energy attached")
        if "react energy" in s:
            groups.add("syn_react")
        # a Tool that falls off the wrong Pokemon ("if ... has Dark or an owner in its name, discard
        # Fluffy Berry") is a restriction, not a theme
        if card.get("supertype") != "Pokémon" and ("discard " + own) in s:
            continue
        if re.search(r"\bholon energy|\bholon fossil", s):
            groups.add("syn_holon")
        if re.search(r"\b(shining|light|dark)( or (shining|light|dark))? pokemon\b|\b(dark|light) @s?\b", s):
            groups.add("syn_dark_light")      # Miracle Energy: "your Shining or Light Pokemon"
        for m in SYN_OWNER_POSS_RE.finditer(s):
            if s[m.start():].startswith(own):
                continue              # its own name ("...other than Blaine's Last Resort")
            nb = _base_name(m.group(0))
            if evolving_any and own_base and (nb in own_line or own_base in lines.get(nb, ())):
                continue              # Koga's Kakuna evolving into Koga's Beedrill
            if _side_ok(s[:m.start()], s):
                groups.add("syn_named")
        for m in SYN_NAMEGROUP_RE.finditer(s):
            if _side_ok(s[:m.start()], s):
                for part in re.split(r" or |, ", m.group(1)):
                    groups.add(_named_group(part, poke))
        for m in SYN_NAMED_RE.finditer(s):
            nm = m.group(1).strip()
            if not _side_ok(s[:m.start()], s) or nm.startswith("@") or s[:m.start()].endswith("not "):
                continue
            # its own evolution line by name ("Evolution card named Gyarados" on Magikarp) is evolution
            nb = _base_name(re.split(r",| or | and ", nm)[0])
            if own_base and nb != own_base and (nb in own_line or own_base in lines.get(nb, ())):
                continue
            groups.add(_named_group(nm, poke))
        evolving_s = SYN_EVOLVE_RE.search(s) is not None
        for rx, g in ((SYN_DELTA_RE, "syn_delta"), (SYN_PARTNER_RE, "syn_species"), (SYN_SELF_RE, "syn_species"),
                      (SYN_TYPE_RE, "syn_type")):
            if g == "syn_type" and SYN_TYPE_SKIP_RE.search(s) and "both yours" not in s:
                continue
            for m in rx.finditer(s):
                pre = s[:m.start()]
                if pre.endswith("not "):
                    continue          # "any Basic Pokemon or Evolution card not named @"
                if g == "syn_type" and (re.search(r"non-$", pre) or ("opponent" in s[m.end():m.end() + 25]
                                                                      and "both yours" not in s[m.end():m.end() + 40])):
                    continue          # "each non-Fighting Pokemon", "each Grass Pokemon on your opponent's Bench"
                if g == "syn_species" and evolving_s and m.group(0).startswith("search your deck"):
                    continue          # Ninetales delta searching for Ninetales / Ninetales ex to evolve into
                if g == "syn_delta" and re.search(r"\b(that|the chosen) pokemon (has |is )?$", pre) \
                        and re.search(r"opponent|defending", prev_s):
                    continue          # "put 1 counter on 1 of your opponent's Pokemon. if that Pokemon has delta..."
                if _side_ok(s[:m.start()], s):
                    groups.add(g)
                    break
        if re.search(r"\bunown\b", s):
            groups.add("unown")
        if SYN_ONTO_SELF_RE.search(s):
            continue                  # Cleffa: "put Clefairy from your hand onto Cleffa"
        evolving = evolving_any or re.search(r"discard @ from", s) is not None
        if re.search(r"each player'?s [^.]*can'?t attack", s):
            continue                  # Groudon ex shutting off every Kyogre ex: a lock, not a partner
        for names, kind in ((poke, "poke"), (other, "other")):
            for nm in names:
                if nm not in s or nm == own or nm in own or nm == "unown":
                    continue
                # its OWN evolution line named while evolving (Magikarp -> Gyarados, Dark Pupitar ->
                # Dark Tyranitar) is just evolution
                if evolving and own_base and kind == "poke" and (nm in own_line or own_base in lines.get(nm, ())):
                    continue
                # plurals count: "Poliwags, Poliwhirls", "Sabrina's Gastlys", "your Magnemites"
                for m in re.finditer(r"(?<![\w'])" + re.escape(nm) + r"(?:s|es)?(?![\w'])", s):
                    if s[:m.start()].endswith("not named "):
                        continue
                    if _side_ok(s[:m.start()], s):
                        groups.add("syn_species" if kind == "poke" else _other_group(nm))
                        break
    groups.discard("")
    return groups


# ════════════════════════════════════════════════════════════════════════════════════════════
# VS OPPONENT / SPECIAL ENERGY / TRAINER TRICKS / METRONOME
# ════════════════════════════════════════════════════════════════════════════════════════════
VS_EX_RE = re.compile(r"\bpokemon-ex\b")
VS_STAGE_RE = re.compile(r"\b(baby|basic|stage 1|stage 2|evolved|unevolved|evolution) pokemon\b|\bis (a |an )?(baby|basic|stage 1|stage 2|evolved|evolution) pokemon|\bhas evolved\b|\bis (not )?evolved\b")
VS_DL_RE = re.compile(r"\b(dark|light|shining)( or (dark|light|shining))? pokemon\b|\b(dark|light) (or (dark|light) )?in its name")
VS_TYPE_RE = re.compile(r"\b(non-)?" + _TYPES + r"( (and|or) \w+)?( basic| evolved| benched| active)? pokemon\b(?!-ex| powers?| tool)|\bis(n'?t| not)? (a |an )?" + _TYPES + r"\b(?! energy|'s)|\bis (a |an )?\w+ type\b|\bhas (?!no )\w+ (resistance|weakness)\b")
# where a Stage word is about a CARD MOVING, not the opponent's Pokemon being that Stage
VS_STAGE_SKIP_RE = re.compile(r"highest stage|devolv|evolution card|(from|in) (his or her|your opponent'?s|your) (hand|deck|discard pile)|onto (his or her|your opponent'?s) bench|\bhand\b")


def _opp_side(prefix):
    """The words before a match put it on the OPPONENT's Pokemon ("if the Defending Pokemon is a
    Pokemon-ex", "each of your opponent's Benched Basic Pokemon", "attacks from Pokemon-ex")."""
    if SYN_SKIP_RE.search(prefix):
        return False
    return SYN_OPP_RE.search(prefix) is not None


OWN_TWIN = {"vs_ex": "syn_ex", "vs_stage": "syn_stage"}

STATUS_IMMUNE_RE = r"can'?t (be|become) (affected by (any )?special|asleep|confused|paralyzed|poisoned|burned|asleep)|(isn'?t|is not) affected by (any )?special conditions?|can'?t become affected by"

# Tools: Technical Machines and Rocket's Secret Machines count as Tools for these filters
_TOOL_W = r"(pokemon tools?|technical machines?|rocket'?s secret machines?|\btools?\b|trainer cards? attached|trainer cards (your opponent has )?in play|trainer cards? in play)"
_TOOL_SKIP = r"discard this card if another stadium|another card with the same name|(doesn'?t|does not) (already )?have a pokemon tool|already have a pokemon tool|other than stadium|you can play only|stays in play when you play it|^at the end of your turn, discard|^attach (this card|[\w.' ]+) to 1 of your"


def tool_stadium_tags(sents):
    """Tool / Stadium synergy (yours) vs anti-Tool / anti-Stadium (the opponent's)."""
    g = set()
    prev = ""
    for s in sents:
        prev_s, prev = prev, s
        if re.search(_TOOL_SKIP, s):
            continue
        opp = re.search(r"opponent|defending pokemon|his or her|each player|both yours|any player",
                        re.sub(r"show (it|them|that card|those cards|either [^,.]*) to your opponent", "", s))
        if re.search(_TOOL_W, s):
            if re.search(r"can'?t play [^.]*(tool|technical machine)", s) \
                    or (opp and re.search(r"\b(discard|shuffle|remove|put (it|them|that card|those cards) into|return|choose)", s)
                        and not re.search(r"you may do the same|search (his or her|your) deck for|\byour (discard pile|hand)\b", s)) \
                    or re.search(r"(defending pokemon|opponent'?s [^.]*pokemon) has (a|any) [^.]*(tool|trainer card)", s) \
                    or re.search(r"discard (all|any) [^.]*trainer cards? attached to (the defending|your opponent|his or her|each of your opponent)", s):
                g.add("anti_tool")
            if re.search(r"search your (deck|discard pile)[^.]*(tool|technical machine|secret machine)|search (his or her|your) deck for a pokemon tool|(tool|technical machine)s?[^.]*(to|into) your hand|attach (them|it|that card|any technical machine)|@ has (a|any) [^.]*(tool|technical machine)|for each (pokemon tool|technical machine)|(tool|machine) cards? in your discard pile|from your hand[^.]*(tool|machine)|(tool|machine)[^.]*from your hand|if that card is a pokemon tool|may attach any technical machine|pokemon tool card attached to 1 of your pokemon", s) \
                    and not re.search(r"can'?t play", s):
                g.add("syn_tool")
        if re.search(r"you may do the same", s) and re.search(_TOOL_W, prev_s):
            g.add("syn_tool")       # Light Togetic: your opponent finds a Tool, then so do you
        if re.search(r"\bstadiums?\b", s) and not re.search(r"if there'?s already a stadium|^discard that stadium card", s):
            if re.search(r"stadium card in play, (you may )?discard it$", s):
                g.add("anti_stadium")   # Brock's Primeape / Light Piloswine: just knocks the Stadium away
                continue
            syn = re.search(r"stadium[^.]*is in play|(is|there is) (a |any )?stadium card in play|(have|has) a stadium card in play|search your (deck|discard pile)[^.]*stadium|stadium card[^.]*(into your hand|put it into play|and play it)|stadium cards? from your (hand|discard pile)|stadium cards? in any combination|and/or stadium", s) \
                and (not re.search(r"can'?t play", s) or re.search(r"stadium[^.]*is in play,", s))
            if syn:
                g.add("syn_stadium")
            if re.search(r"discard (a|any|the|that|all)? ?stadium|stadium[^.]*, (you may )?discard it|can'?t play (any )?stadium|stadium cards? (in play )?[^.]*discard them", s):
                g.add("anti_stadium")
    return g


DAMAGED_RE = re.compile(r"(for each|equal to the number of|number of) damage counters? on @(?![\w'])|if @ has (any|\d+ or more) damage counters")
VS_DAMAGED_RE = re.compile(r"for each damage counter on (the defending pokemon|that pokemon)|(defending pokemon|that pokemon) (already )?has (any|\d+ or more) damage counters")
PRIZE_RE = re.compile(r"prize cards? (left|remaining)|(more|fewer|less) prize cards|\d+ or (more|fewer|less) prizes|(have|has) (only |exactly )?\d+ prizes?\b|prizes? (left|remaining)|number of prize cards")


def counter_prize_tags(sents):
    """Own-damage synergy, vs-damaged, and Prize-count conditions."""
    g = set()
    heals = re.search(r"\bremove", " ".join(sents)) is not None
    for s in sents:
        if re.search(r"\bremove", s) or (heals and not re.search(r"for each|number of", s)):
            continue          # healing, not a damage synergy (Erika's Oddish, Lapras)
        if DAMAGED_RE.search(s):
            g.add("syn_damaged")
        if VS_DAMAGED_RE.search(s):
            g.add("vs_damaged")
    for s in sents:
        if PRIZE_RE.search(s):
            g.add("prize_count")
    return g


def supporter_tags(sents):
    """Supporter synergy: find / recover / count / borrow Supporters (Supporter LOCKS are Block Trainers)."""
    for s in sents:
        if "supporter" not in s or re.search(r"you can play only|can'?t play|except for supporter|excluding supporter", s):
            continue
        if re.search(r"search|discard pile|for each|effect (of|on) (a|that|this)|in play|find there|shuffle a supporter|supporter cards? in your", s):
            return {"syn_supporter"}
    return set()
_COND = r"(asleep|confused|paralyzed|poisoned|burned|affected by (a |any )?special conditions?)"
# an effect that only happens / gets stronger WHILE a Pokemon has a Special Condition
SYN_STATUS_RE = re.compile(
    r"\b(if|as long as|for each|unless|while|whenever)\b[^.,]*?\b(is|are|isn'?t|is not|remains|was|it'?s)( still| already)? (\w+ (or|and) )?" + _COND
    + r"|\b(that|which) (is|remains) " + _COND + r"|\bfor each special condition|\b(asleep|confused|paralyzed|poisoned|burned) pokemon\b|\bremains? (asleep|confused|paralyzed|poisoned|burned)\b")
# whether a Power can be USED while affected, cures, and "stronger Poison" inflicts are not synergy
SYN_STATUS_SKIP_RE = re.compile(r"(can'?t|cannot) (be )?use(?! this attack)|can be used even|works even|doesn'?t work|stops working|power can'?t|isn'?t a copy|\bremove|no longer|recover|even if it was already")


def versus(sents, card):
    """Opponent-condition groups + Special Energy + Trainer Tricks for one effect text."""
    groups = set()
    prev = ""
    opp_ctx = False          # an earlier sentence picked an opponent's Pokemon ("choose 1 of your opponent's...")
    whole = " ".join(sents)
    stage_skip = re.search(r"highest stage|devolv|\bhand\b", whole) is not None
    is_trainer = card.get("supertype") == "Trainer"
    for s in sents:
        if re.search(r"\b(defending pokemon|your opponent'?s|his or her) ", prev):
            opp_ctx = True
        prev = s
        for rx, g in ((VS_EX_RE, "vs_ex"), (VS_STAGE_RE, "vs_stage"), (VS_DL_RE, "vs_dark_light"), (VS_TYPE_RE, "vs_type")):
            if g == "vs_stage" and (stage_skip or VS_STAGE_SKIP_RE.search(s)):
                continue
            if g == "vs_type" and re.search(r"type of your choice|is still|for each", s):
                continue
            # a symmetric Stadium ("each player's Fire and Water Pokemon", "both yours and your
            # opponent's") is no penalty aimed at the opponent
            if is_trainer and re.search(r"both yours|\b(each|any|a) player\b", s):
                continue
            own_g = OWN_TWIN.get(g)
            for m in rx.finditer(s):
                pre = s[:m.start()]
                post = s[m.end():m.end() + 25]
                opp_pre = SYN_OPP_RE.search(pre) is not None
                if opp_ctx and re.search(r"\byou choose $", pre):
                    groups.add(g)     # Plusle: "choose 1 of your opponent's Pokemon... if you choose Pokemon-ex"
                    break
                yours = re.search(r"\b(you|your|yours)\b(?! opponent)[^.]*$", pre) and not opp_pre
                excl = re.search(r"(excluding|not) $|excluding [^)]*$", pre) and not opp_pre
                self_pre = re.search(r"@ $|@ is [^,]*$|attached to (is )?[^,]*$|attach(ed)? only to (a |an )?$|can be attached only to (a |an )?$", pre)
                if yours or excl or (own_g and (self_pre or re.match(r" you have", post))):
                    # YOUR Pokemon being ex / a Stage -> the Synergy twin ("your Pokemon-ex",
                    # "as long as @ is an Evolved Pokemon", Protective Orb "...is a Basic or Pokemon-ex")
                    if own_g and not re.search(r"\beach player|\bas if it were|\btreat\b|search|from your (hand|deck|discard)|onto your bench|in your hand", s):
                        groups.add(own_g)
                    continue
                if _opp_side(pre) or (opp_ctx and re.search(r"\b(that|the) pokemon (is|has) (not )?(a |an )?$", pre)) \
                        or re.search(r"\b(attacks?[^.]*@|done to @) (by|from) (an? )?$|\battack by (a |an )?$", pre):
                    groups.add(g)
                    break
        if SYN_STATUS_RE.search(s) and not SYN_STATUS_SKIP_RE.search(s):
            groups.add("syn_status")
        # SPECIAL ENERGY: anything that uses / needs / hits / blocks Special Energy (React and Holon
        # Energy have their own Synergy rows)
        if re.search(r"special energy", s) and not re.search(r"^this card is a special energy|doesn'?t count as", s):
            groups.add("syn_special")
        # TRAINER TRICKS: counts, finds, discards, shuffles away or borrows Trainer / Supporter cards
        if re.search(r"\b(trainer|supporter) cards?\b|\btrainers?\b(?= (in|from|there))|effect of (a|that|this) (supporter|trainer)|effect on that card", s) \
                and re.search(r"for each|discard|shuffle|search|put|use|choose|return|take|number of|if (you|your opponent) (have|has)|look", s) \
                and not re.search(r"(powers?|attacks?|energy cards?),? (and |or )?trainer cards?|trainer cards? can'?t|can'?t play|(isn'?t|aren'?t) affected by|effects? (of|from) trainer|trainer cards? attached|you can play only|when you play this card|can'?t be played|other than a stadium", s):
            groups.add("trainer_manip")
    return groups


# ════════════════════════════════════════════════════════════════════════════════════════════
def iter_effects(card):
    """Yields (source_bit, raw_text, is_attack, damage_str) for every piece of effect text."""
    sup = card.get("supertype", "")
    for ab in card.get("abilities", []) or []:
        t = ab.get("text", "") or ""
        if t.strip():
            yield SRC_POWER, t, False, ""
    for at in card.get("attacks", []) or []:
        t = at.get("text", "") or ""
        if t.strip():
            yield SRC_ATTACK, t, True, str(at.get("damage", "") or "")
    rules = card.get("rules", []) or []
    if sup == "Pokémon":
        for r in rules:
            low = r.lower().replace("é", "e")
            if any(re.search(p, low) for p in POKEMON_RULE_SKIP):
                continue
            yield SRC_POWER, r, False, ""
    else:
        t = " | ".join(rules)
        if t.strip():
            yield SRC_CARD, t, False, ""


def load_cards():
    cards = []
    for f in sorted(glob.glob(os.path.join(SET_DIR, "*.json"))):
        if os.path.basename(f) == "pack_prices.json":
            continue
        with open(f, encoding="utf-8") as fh:
            cards.extend(json.load(fh))
    return cards


def build():
    cards = load_cards()
    _syn_names(cards)
    out = {}
    per_text = []         # (card_id, src, raw, tags)
    untagged = []
    for c in cards:
        cid = c["id"]
        name = c["name"]
        ctags = defaultdict(int)
        for src, raw, is_attack, dmg in iter_effects(c):
            cleaned = clean(raw, name, c.get("supertype") == "Pokémon")
            sents = sentences(cleaned)
            # Synergy also reads the boilerplate: a Tool's attach line can name its family ("Attach Team
            # Aqua Belt to 1 of your Pokemon with Team Aqua in its name...")
            syn_sents = sentences(cleaned, keep_boiler=True)
            # A Pokemon often calls itself by a SHORTER name than its card ("Latios Star" on Latios ☆,
            # "Mewtwo" on Mewtwo ex). Collapse those to @ too, so the self-tests above hit.
            short = name.lower().replace("é", "e")
            for suf in [" ex", " ☆", " ★", " star", " δ", " lv.x"]:
                short = short.replace(suf, "")
            short = re.sub(r"^(dark|light|shining|rocket'?s|team aqua'?s|team magma'?s|holon'?s|[a-z.]+'s) ", "", short).strip()
            if short and len(short) > 2 and c.get("supertype") == "Pokémon":
                sents = [re.sub(r"\b" + re.escape(short) + r"( star| ex)?\b", "@", s) for s in sents]
                syn_sents = [re.sub(r"\b" + re.escape(short) + r"( star| ex)?\b", "@", s) for s in syn_sents]
            tags = tag_text(sents, src, is_attack, dmg, c)
            if "form_change" not in tags:
                tags |= synergy(syn_sents, c, name)
            tags |= versus(sents, c)
            # "(excluding Pokemon-ex)" is dropped by clean(): read it off the raw text - a Tool / Energy
            # / Power barred from YOUR Pokemon-ex
            for m in re.finditer(r"\(excluding pok[eé]mon-ex", raw.lower()):
                win = raw.lower()[max(0, m.start() - 60):m.start()]
                if "opponent" not in win and re.search(r"attach", win) and not re.search(r"search|bench", win):
                    tags.add("syn_ex")
            whole = " ".join(sents)
            # Metronome = an attack borrowed from another POKEMON. A Technical Machine / Cube / Plate's
            # own attack is a Tool trick; using a Supporter's effect is a Trainer trick.
            # A Technical Machine / Cube / Plate / attack Stadium hands over ONE fixed attack: that's a
            # Bonus Attack, not a Metronome pick
            if "copy_attack" in tags and re.search(r"this card'?s attack|attacks? on this card", whole):
                tags.discard("copy_attack")
                tags.add("extra_attack")
            if re.search(r"effect of (a|that|this) (supporter|trainer)|effect on that card|use that card as if it were in your hand", whole):
                tags.discard("copy_attack")
                tags.add("trainer_manip")
            tags |= tool_stadium_tags(syn_sents)
            tags |= supporter_tags(sents)
            tags |= counter_prize_tags(sents)
            # STATUS IMMUNITY: "can't be Poisoned", "can't be affected by any Special Conditions" is a
            # wall, not a cure
            if "status_cure" in tags:
                if re.search(STATUS_IMMUNE_RE, whole):
                    tags.add("status_immune")
                    if not re.search(r"\bremove|no longer|recover", whole):
                        tags.discard("status_cure")
                if re.search(r"retreat even (when|if) it is", whole):
                    tags.discard("status_cure")
                    tags.add("retreat_aid")
            # BLOCK EFFECTS: "prevent all effects of attacks" (Agility: + damage), "except damage"
            # (Crystal Body: damage still lands), or Trainer / Power effects that can't touch it
            if re.search(r"prevent all effects|effects,? (except|other than|excluding) damage|effects of [^.]*attacks?,? (except|other than|excluding) damage|(isn'?t|aren'?t) affected by effects from trainer", whole):
                tags.add("block_effects")
                if not re.search(r"including damage|prevent all damage|prevent that damage|no damage", whole):
                    tags.discard("prevent_damage")
            if "prevent_damage" in tags and not re.search(r"damage", whole):
                tags.discard("prevent_damage")   # Unown [K], Pokemon Tower, Brock's Protection
                tags.add("block_effects")
            # SURVIVE KNOCK OUT needs a "would be Knocked Out"; it is not also an On-KO trigger
            if "ko_prevent" in tags:
                if not re.search(r"would (be knocked|knock) out", whole):
                    tags.discard("ko_prevent")
                else:
                    tags.discard("ko_on")
            # POWER UP NEXT TURN: Swords Dance / Extra Comet Punch / "the Defending Pokemon takes more
            # damage during your next turn"
            if "damage_boost" in tags and re.search(r"(during|until the end of) your next turn", whole):
                tags.discard("damage_boost")
                tags.add("setup_boost")
            # SELF KNOCK OUT: Selfdestruct / Explosion that does at least its own HP to itself
            try:
                hp = int(c.get("hp") or 0)
            except ValueError:
                hp = 0
            if hp:
                for s in sents:
                    for m in re.finditer(r"@ does (\d+) damage to itself", s):
                        if int(m.group(1)) >= hp and not re.search(r"if tails", s):
                            tags.add("self_ko")
            if "form_change" in tags:
                tags.discard("bounce")     # Castform shuffling itself back is part of the swap
            if not sents:
                continue    # nothing but boilerplate (plain Special Energy, a bare deck rule)
            for t in tags:
                ctags[t] |= src
            per_text.append((cid, name, src, raw, sorted(tags)))
            if not tags:
                untagged.append((cid, name, src, raw))
        # Cards that ARE the theme get its filter whatever their text says (or even with none):
        # every Unown, every React Energy, every Holon Energy.
        lname = name.lower()
        if lname.startswith("unown"):
            ctags["unown"] |= SRC_ALL
        elif lname.startswith("react energy"):
            ctags["syn_react"] |= SRC_ALL
        elif lname.startswith("holon energy"):
            ctags["syn_holon"] |= SRC_ALL
        if c.get("supertype") == "Trainer" and c.get("attacks"):
            ctags["extra_attack"] |= 4
        if ctags:
            out[cid] = dict(sorted(ctags.items()))
    return cards, out, per_text, untagged


def main():
    args = sys.argv[1:]
    cards, out, per_text, untagged = build()

    if "--show" in args:
        key = args[args.index("--show") + 1]
        seen = set()
        for cid, name, src, raw, tags in per_text:
            if key in tags and raw not in seen:
                seen.add(raw)
                print(f"{cid:<12} {name:<28} {raw[:190]}")
        print(f"\n{len(seen)} distinct texts tagged {key}")
        return

    counts = defaultdict(int)
    for cid, tags in out.items():
        for t in tags:
            counts[t] += 1
    print("cards per category:")
    for k in CAT_KEYS:
        print(f"  {k:<16} {counts.get(k, 0)}")
    unknown = set(counts) - set(CAT_KEYS)
    if unknown:
        print("!! tags with no category entry:", unknown)

    seen = set()
    distinct_untagged = []
    for cid, name, src, raw in untagged:
        if raw in seen:
            continue
        seen.add(raw)
        distinct_untagged.append((cid, name, src, raw))
    print(f"\n{len(per_text)} effect texts, {len(distinct_untagged)} distinct untagged")
    for cid, name, src, raw in distinct_untagged:
        print(f"  [{src}] {cid:<12} {name:<26} {raw[:200]}")
    print(f"\n{len(distinct_untagged)} untagged")

    if "--check" in args:
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    payload = {
        "_comment": "GENERATED by Scripts/Utilities/card_effect_tags_build.py - do not hand-edit. "
                    "Source bits: 1 attack, 2 power/body, 4 trainer/energy text.",
        "categories": [{"key": k, "label": l, "group": g, "desc": d} for k, l, g, d in CATEGORIES],
        "cards": out,
    }
    with open(OUT_FILE, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))
    print("wrote", OUT_FILE)


if __name__ == "__main__":
    main()
