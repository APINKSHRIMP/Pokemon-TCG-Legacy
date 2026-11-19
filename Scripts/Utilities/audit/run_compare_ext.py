# exec()'d by run_compare.py (shares meta, ALL, BASE, rows, re). EXTENDED AUDIT 2026-11-19: Tools, Stadiums, Special Energy and the
# conditional boards. Board: attacker Porygon (plain Colorless, one 30-damage attack), defender Clefairy-like 900 HP, no W/R.
# Every flag here is a LEAD: check the card text, then the code, before calling it a bug. Known probe artifacts are skipped below.
PORY = 30
PU_EVAL = [0]

def add2(rec, c, fl, detail):
    rows.append((rec["uid"], c.get("name", "?"), "%s:%s:%s" % (rec["kind"], rec["name"], rec.get("scen", "")), fl, detail))

def dealt(rec): return rec["pre"]["def_hp"] - rec["post"].get("def_hp", rec["pre"]["def_hp"])
def rules_of(c): return " ".join(c.get("rules", []) or [])
NUM = re.compile(r"(\d+) more damage")
TEAM_ONLY = re.compile(r"team (aqua|magma)|in its name|only to a", re.I)

for rec in ALL.values():
    k = rec["kind"]
    if k not in ("tool", "stadium", "senergy", "cond"): continue
    c = meta.get(rec["uid"].lower())
    if not c: continue
    sc = rec.get("scen", ""); pre, post = rec["pre"], rec["post"]; ex = rec.get("extra") or {}
    msgs = " | ".join(rec["msgs"]); msgl = msgs.lower(); rl = rules_of(c).lower()
    if rec["timed_out"]: add2(rec, c, "run_hang", "no result within %d frames; last msgs: %s" % (rec["frames"], msgs[:120])); continue
    power_saver = any(x.get("name") == "Power Saver" for x in c.get("abilities", []) or [])   # PROBE ARTIFACT: get_attacks_for_card = [] -> Main:9967
    for e in rec["errors"]:
        if e.startswith("Card_Probe.gd") or (power_saver and "Core_Gameplay_Script.gd:9967" in e): continue
        add2(rec, c, "run_script_error", e)
    if "not implemented" in msgl: add2(rec, c, "run_not_implemented", msgs[:140])
    if not post: add2(rec, c, "run_no_post_state", "match ended or state unreadable"); continue
    refused = ex.get("refused")

    # ------------------------------------------------------------------------------------------------ TOOLS
    if k == "tool":
        gated = bool(TEAM_ONLY.search(rl)) or "evolved" in rl and "attach" in rl
        if sc == "play_me":
            held = post["me_cards"] or post["bench_cards"]
            if not held and not refused and not gated: add2(rec, c, "tool_not_attached", "played from hand, not on any Pokémon; msgs: " + msgs[:100])
        elif sc == "play_foe":
            if not post["def_cards"] and not refused and not gated: add2(rec, c, "tool_not_attached_foe", "CPU play did not attach; msgs: " + msgs[:100])
        elif sc in ("atk_tool", "atk_tool_prize") or sc.startswith("atk_tool_type_"):
            d = dealt(rec); m = NUM.search(rl)
            if m and "prize" not in rl and "type" not in sc and "flip" not in rl and d != PORY + int(m.group(1)) and "active" not in rl.replace("active pokémon", ""):
                add2(rec, c, "tool_attacker_damage", "text: %s more damage; dealt %d (expected %d)" % (m.group(1), d, PORY + int(m.group(1))))
            if sc == "atk_tool_prize" and m and d != PORY + int(m.group(1)):
                add2(rec, c, "tool_prize_condition", "behind on Prizes (6 vs 4): expected %d, dealt %d" % (PORY + int(m.group(1)), d))
            at = ex.get("after_turn")
            if sc == "atk_tool" and at is not None and re.search(r"end of your opponent's (next )?turn|end of your opponent's turn after you played", rl) and c["name"] in at["me_cards"]:
                add2(rec, c, "tool_not_discarded_end_of_opp_turn", "text: discarded at the end of the opponent's next turn; turns %s, still attached: %s" % (ex.get("turn_before_after"), at["me_cards"]))
            if sc == "atk_tool" and at is not None and not TEAM_ONLY.search(rl) and re.search(r"discard (this card|%s)[^.]*at the end of (the|any) turn|at the end of the turn in which this happens|if that pok.mon attacks, discard" % re.escape(c["name"].lower()), rl) and "flip" not in rl:
                if c["name"] in at["me_cards"] or "Strength Charm" in at["me_cards"] and "strength charm" in c["name"].lower():
                    add2(rec, c, "tool_not_discarded_end_of_turn", "text: discarded at end of the attack turn; still attached afterwards: %s" % at["me_cards"])
        elif sc in ("def_tool", "def_tool_dmg"):
            d = dealt(rec); m = re.search(r"reduced by (\d+)", rl)
            if m and "damage done to the pok" in rl and d != max(0, PORY - int(m.group(1))): add2(rec, c, "tool_defender_damage", "reduces by %s; dealt %d" % (m.group(1), d))
            if not m and "prevent all effects" not in rl and d != PORY and "flip" not in rl: add2(rec, c, "tool_defender_unexpected_damage", "dealt %d, text has no damage change: %s" % (d, rl[:90]))
        elif sc == "def_tool_ko":
            survived = not post.get("foe_active_swapped")
            reduce_ = re.search(r"reduced by (\d+)", rl)
            if not survived and not reduce_ and not gated:
                if pre["my_prize"] - post["my_prize"] != 1: add2(rec, c, "tool_ko_no_prize", "defender KO'd, prizes taken %d" % (pre["my_prize"] - post["my_prize"]))
                if post["foe_disc"] - pre["foe_disc"] < 2 and "time shard" not in rl and "return" not in rl: add2(rec, c, "tool_ko_not_discarded", "KO'd holder + tool should both reach the discard pile; foe discard +%d (%s)" % (post["foe_disc"] - pre["foe_disc"], post["foe_disc_tail"]))
            if survived and "flip" not in rl and not reduce_ and "prevent" not in rl: add2(rec, c, "tool_ko_survived", "holder survived 30 damage with 30 HP; text: " + rl[:90])
            if "3 damage counters on the attacking" in rl and pre["me_hp"] - post["me_hp"] != 30 and not survived: add2(rec, c, "tool_ko_counter", "text: 3 counters on the Attacking Pokémon; attacker lost %d HP" % (pre["me_hp"] - post["me_hp"]))
        elif sc in ("between_me", "between_foe"):
            who_hp = (pre["me_hp"], post["me_hp"], post["me_cond"], post.get("me_pois_now"), post["me_cards"]) if sc == "between_me" else (pre["def_hp"], post["def_hp"], post["def_cond_now"] if "def_cond_now" in post else "", post["def_pois"], post["def_cards"])
            m = re.search(r"remove (\d+) damage counters", rl)
            if m and "between turns" in rl and "flip" not in rl and not rec["prompts"]:
                n = int(m.group(1))
                if who_hp[1] - who_hp[0] < 10 * n and sc == "between_me": add2(rec, c, "tool_between_no_heal", "text: remove %d counters between turns; HP %d -> %d" % (n, who_hp[0], who_hp[1]))
            if "remove all" in rl and "special condition" in rl and sc == "between_me" and (who_hp[2] or who_hp[3]) and not rec["prompts"]:
                add2(rec, c, "tool_between_status_kept", "text removes Special Conditions between turns; cond=%r pois=%s" % (who_hp[2], who_hp[3]))
        continue

    # ------------------------------------------------------------------------------------------------ STADIUMS
    if k == "stadium":
        if sc == "play":
            if post["stadium"].lower() != rec["uid"].lower() and not refused: add2(rec, c, "stadium_not_in_play", "after play: stadium=%r; msgs %s" % (post["stadium"], msgs[:80]))
            if post["my_hand"] - pre["my_hand"] != -1 and not refused and "giant stump" not in c["name"].lower(): add2(rec, c, "stadium_hand_count", "hand %d -> %d" % (pre["my_hand"], post["my_hand"]))
        elif sc == "same_name":
            if "same name" in rl and not refused and "was discarded" in msgl:
                add2(rec, c, "stadium_same_name_allowed", "text: a Stadium with the same name in play blocks playing this card, but the 2nd copy was played and the first discarded; msgs: " + msgs[:100])
        elif sc == "replace_foe":
            if post["stadium"].lower() != rec["uid"].lower(): add2(rec, c, "stadium_replace_failed", "stadium after replace: %r" % post["stadium"])
            if post["foe_disc"] - pre["foe_disc"] != 1: add2(rec, c, "stadium_replace_old_not_to_owner_discard", "old (opponent-owned) Stadium: foe discard +%d, my discard +%d" % (post["foe_disc"] - pre["foe_disc"], post["my_disc"] - pre["my_disc"]))
        elif sc == "actions":
            for a in ex.get("acts", []):
                if a.get("listed_before_2") and not re.search(r"as often as|as many", rl) and a["changed_2"]:
                    add2(rec, c, "stadium_reusable_same_turn", "action %r still offered after use and a 2nd use changed %s" % (a["name"], a["changed_2"][:5]))
                elif a.get("listed_before_2") and not re.search(r"as often as|as many", rl):
                    add2(rec, c, "stadium_still_listed_after_use", "action %r offered again after use (no visible change on 2nd use)" % a["name"])
            OFFER_OR_PASSIVE = ("ecard2-131", "pop2-10", "ex11-96", "ex12-76", "ex12-77")   # PROBE ARTIFACT: passive, or offered at the start of the turn (Main ~8263-8271), not a menu action
            if rec["uid"].lower() not in OFFER_OR_PASSIVE and re.search(r"once during (each|his|her)", rl) and not ex.get("acts") and not re.search(r"start of|at the end", rl):
                add2(rec, c, "stadium_no_action", "text has a once-per-turn action but stadium_actions_for_player() returned none on the rich board")
        elif sc == "atk":
            d = dealt(rec); m = re.search(r"reduced by (\d+)", rl); exp = PORY
            if m and "colorless" in rl: exp = max(0, PORY - int(m.group(1)))
            if "prevent all effects of an attack" in rl: exp = 0
            if d != exp and not post.get("foe_active_swapped"): add2(rec, c, "stadium_attack_damage", "expected %d with this Stadium in play, dealt %d (text: %s)" % (exp, d, rl[:90]))
        elif sc == "play_bench5":
            m = re.search(r"more than (\d+) (?:benched|pok.mon on)", rl)
            if m:
                n = int(m.group(1))
                if post["own_bench_n"] > n or post["foe_bench_n"] > n: add2(rec, c, "stadium_bench_limit", "limit %d; after play own bench %d, foe bench %d" % (n, post["own_bench_n"], post["foe_bench_n"]))
        elif sc.startswith("stats"):
            m = re.search(r"pays? ((?:colorless)+) (less|more) to retreat", rl)
            if m and sc == "stats":
                n = m.group(1).count("colorless") * (1 if m.group(2) == "more" else -1)
                typed = [t for t in ["fire", "water", "psychic", "baby", "basic", "dark", "misty"] if t in rl]
                if not typed and pre["me_retreat"] + n != post["me_retreat"] and not (pre["me_retreat"] + n < 0 and post["me_retreat"] == 0):
                    add2(rec, c, "stadium_retreat_cost", "text: %s%d; Active retreat %d -> %d" % ("+" if n > 0 else "", n, pre["me_retreat"], post["me_retreat"]))
            hp = re.search(r"gets \+(\d+) hp", rl)
            if hp and sc.startswith("stats_") and "name" not in sc:
                t = sc.split("_")[-1]
                if t.lower() in rl and post["me_maxhp"] - pre["me_maxhp"] != int(hp.group(1)) and post["def_maxhp"] - pre["def_maxhp"] != int(hp.group(1)):
                    add2(rec, c, "stadium_hp_bonus", "text +%s HP for %s Pokémon; Active max HP %d -> %d, defender %d -> %d" % (hp.group(1), t, pre["me_maxhp"], post["me_maxhp"], pre["def_maxhp"], post["def_maxhp"]))
            if hp and "name" in sc:
                if post["me_maxhp"] - pre["me_maxhp"] != int(hp.group(1)): add2(rec, c, "stadium_hp_bonus_name", "text +%s HP (%s); Active max HP %d -> %d" % (hp.group(1), sc, pre["me_maxhp"], post["me_maxhp"]))
            if m and sc.startswith("stats_") :
                n = m.group(1).count("colorless") * (1 if m.group(2) == "more" else -1)
                t = sc.split("_")[-1].lower()
                if t in ("fire", "water", "psychic") and t in rl and pre["me_retreat"] + n != post["me_retreat"] and not (pre["me_retreat"] + n < 0 and post["me_retreat"] == 0):
                    add2(rec, c, "stadium_retreat_cost_typed", "text %s%d for %s; Active retreat %d -> %d" % ("+" if n > 0 else "", n, t, pre["me_retreat"], post["me_retreat"]))
        continue

    # ------------------------------------------------------------------------------------------------ SPECIAL ENERGY
    if k == "senergy":
        d = dealt(rec); prov = ex.get("provided")
        ck = ex.get("attach_check", {})
        if sc in ("attach_ok",) and ck and not ck.get("allowed", True) and "shining or light" not in ck.get("reason", "").lower():   # Miracle Energy needs a Shining/Light name
            add2(rec, c, "senergy_attach_refused", "holder meets the attach rule (Evolved/named) but can_attach_to refused: %s" % ck.get("reason", "")[:90])
        if sc == "provides":
            m = re.search(r"provides ((?:colorless)+) energy", rl)
            if m and prov is not None and "multi" not in c["name"].lower() and "every type" not in rl and len(prov) != m.group(1).count("colorless") and "doesn't count" not in rl.replace("provides ", "", 1)[:0]:
                add2(rec, c, "senergy_provides_count", "text provides %d Colorless; get_energy_provided_by_card = %s" % (m.group(1).count("colorless"), prov))
        if sc == "provides_ok" and prov is not None:
            if "boost energy" in c["name"].lower() and len(prov) != 3: add2(rec, c, "senergy_provides_count", "Boost: provided %s" % prov)
            if "scramble" in c["name"].lower() and len(prov) != 3: add2(rec, c, "senergy_scramble_prizes", "behind on Prizes (6 vs 4): provided %s (text: provides 3 Colorless)" % prov)
            if "double rainbow" in c["name"].lower() and len(prov) != 2: add2(rec, c, "senergy_provides_count", "Double Rainbow: provided %s" % prov)
        if sc in ("attach_hurt", "attach_ok"):
            gain = post["me_hp"] - pre["me_hp"]
            if re.search(r"remove 1 damage counter", rl) and "evolved" not in rl and gain != 10 and ck.get("allowed", True):
                add2(rec, c, "senergy_attach_heal", "text: remove 1 damage counter on attach; HP %d -> %d" % (pre["me_hp"], post["me_hp"]))
            if re.search(r"no longer asleep|all special conditions", rl) and (post["me_cond"] or post.get("me_pois_now")) and ck.get("allowed", True):
                add2(rec, c, "senergy_attach_cure", "text cures on attach; cond=%r pois=%s" % (post["me_cond"], post.get("me_pois_now")))
        if sc in ("atk_alone", "atk_plus", "atk_ok") or sc.startswith("atk_type_"):
            if refused: continue
            if d == 0 and not post.get("foe_active_swapped") and sc != "atk_alone": add2(rec, c, "senergy_attack_no_damage", "attack with this Energy attached dealt 0; msgs %s" % msgs[:80])
            if d != PORY and "damage" not in rl and "weakness" not in rl and not post.get("foe_active_swapped"): add2(rec, c, "senergy_unexpected_damage", "text has no damage clause; dealt %d" % d)
            if "10 more damage" in rl and sc.startswith("atk_type_Darkness") and d != PORY + 10: add2(rec, c, "senergy_darkness_bonus", "Darkness attacker: expected %d, dealt %d" % (PORY + 10, d))
            if "10 more damage" in rl and sc == "atk_alone" and d != PORY:   # Porygon is Colorless: bonus must be ignored (printed 'unless Darkness' on newer cards)
                if "ignore this effect unless" in rl: add2(rec, c, "senergy_darkness_bonus_on_nondark", "newer Darkness Energy applies +10 to a Colorless attacker (dealt %d)" % d)
        if sc in ("def_hit", "def_ok"):
            m = re.search(r"reduced by (\d+)", rl)
            if m and "metal" in rl and sc == "def_hit" and "ignore this effect if" in rl and d != PORY: add2(rec, c, "senergy_metal_nonmetal", "newer Metal Energy on a non-Metal defender: dealt %d (expected %d)" % (d, PORY))
        continue

    # ------------------------------------------------------------------------------------------------ CONDITIONAL BOARDS
    if k == "cond":
        a = next((x for x in c.get("attacks", []) if x["name"] == rec["name"]), None)
        if not a: continue
        t = (a.get("text") or ""); tl = t.lower()
        base = BASE.get((rec["uid"].lower(), rec["name"]))
        # PROBE ARTIFACTS (variant boards that do not model the condition's direction / history):
        if sc == "me_damaged" and re.search(r"defending pok.mon[^.]*damage counter|damage counters? on (the defending|it)", tl): continue
        if sc == "def_damaged" and re.search(r"(if|has) (this pok.mon|%s)[^.]*damage" % re.escape(c["name"].lower()), tl): continue
        if sc == "my_prize1" and "you have only" not in tl: continue
        if sc == "foe_prize1" and "you have only" in tl: continue
        if sc.startswith(("me_energy6", "def_energy3")) and (" than " in tl or "any " in tl or "count the amount" in tl): continue   # standard board already has the Energy / compares counts
        if "you may discard" in tl or "last turn" in tl or "your opponent's last" in tl: continue   # needs a prompt answer / attack history
        if sc == "def_evolved" and "stage 2" in tl: continue   # def_stage2 covers it
        d = dealt(rec)
        if post.get("foe_active_swapped") or "flip" in tl or "coin" in tl or "Darkness" in (c.get("types") or []) or any("Body" in (x.get("type") or "") for x in c.get("abilities", []) or []): continue
        if base is None: continue
        mm = re.search(r"(\d+) (more|less) damage", tl)
        plus = (a.get("damage") or "").endswith("+")
        if (mm and mm.group(2) == "more" or plus) and "for each" not in tl and "times" not in tl and "number of" not in tl:
            n = int(mm.group(1)) if mm else 0
            if n and d < base + n and sc not in ("def_tool", "me_tool"):
                add2(rec, c, "cond_bonus_missing", "board=%s: text '%s more damage'; standard board dealt %d, condition board dealt %d (text: %s)" % (sc, n, base, d, t[:80]))
        if mm and mm.group(2) == "less" and "for each" not in tl and d > base - int(mm.group(1)) and base - int(mm.group(1)) >= 0 and False:
            pass
        # EXACT per-unit formulas on the condition boards (standard board: 0 counters, 0 Defending Energy, 2+2 Benched, 6/6 Prizes, 4/4 cards in hand)
        fe = re.search(r"(\d+) (?:more )?damage for each ([^.]*)", tl)
        if fe and "more than" not in tl and "can't add" not in tl and "minus" not in tl and "+" in (a.get("damage") or "+"):
            n_ = int(fe.group(1)); what = fe.group(2)
            fresh = {"def_damaged": ("damage counter on the defending", (pre["def_maxhp"] - pre["def_hp"]) // 10, 0),
                     "me_damaged": ("damage counter on " + c["name"].lower(), (pre["me_maxhp"] - pre["me_hp"]) // 10, 0),
                     "def_energy3": ("energy attached to the defending", len(pre["def_energy_names"]), 0),
                     "own_bench0": ("of your benched", pre["own_bench_n"], 2), "own_bench5": ("of your benched", pre["own_bench_n"], 2),
                     "foe_bench0": ("of your opponent's benched", pre["foe_bench_n"], 2), "foe_bench5": ("of your opponent's benched", pre["foe_bench_n"], 2),
                     "foe_prize1": ("prize card your opponent has taken", 6 - pre["foe_prize"], 0),
                     "hand8": ("card in your hand", pre["my_hand"], 4), "hand0": ("card in your hand", pre["my_hand"], 4)}.get(sc)
            PU_EVAL[0] += 1 if fresh else 0
            if fresh and fresh[0] in what.lower() + " " + tl[:0] and what.lower().startswith(fresh[0].split(" ")[0]) :
                exp = base + n_ * (fresh[1] - fresh[2])
                if d != exp: add2(rec, c, "cond_per_unit_mismatch", "board=%s: %d per unit x (%d vs %d on the standard board): expected %d, dealt %d (text: %s)" % (sc, n_, fresh[1], fresh[2], exp, d, t[:90]))
        if "instead" in tl:
            m2 = re.search(r"(\d+) damage instead", tl) or re.search(r"does (\d+) damage", tl)
            if m2 and d != int(m2.group(1)) and sc in ("def_ex", "def_evolved", "def_damaged", "me_damaged") and "more" not in tl:
                add2(rec, c, "cond_instead", "board=%s: text '%s instead'; dealt %d (standard %d) (text: %s)" % (sc, m2.group(1), d, base, t[:80]))
        if "for each" in tl or "times" in tl:
            if d == base and sc in ("def_energy3", "my_disc_rich", "own_bench0", "own_bench5", "foe_bench5", "me_energy6", "hand8", "hand0", "foe_hand8", "my_prize1", "foe_prize1", "def_damaged", "me_damaged"):
                add2(rec, c, "cond_for_each_unchanged", "board=%s: 'for each' damage unchanged (%d) vs standard board (text: %s)" % (sc, d, t[:90]))
        if "rec_prompt" == "x": pass

print('per-unit checks evaluated:', PU_EVAL[0])
