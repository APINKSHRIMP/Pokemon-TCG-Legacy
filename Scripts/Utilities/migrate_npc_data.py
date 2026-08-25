#!/usr/bin/env python3
"""
Migrate the per-day NPC/Opponent JSON files into per-map character files.

  python migrate_npc_data.py build     write NPC_and_Opponent_Data/Characters/*.json
  python migrate_npc_data.py verify    re-expand the new files and diff against the old ones

The old format stores one snapshot per (map, day, time-of-day) -- 124 files, 2511
placement records covering 327 characters. The new format stores each character
once, with a `when` rule list describing when it deviates from its own defaults.
"""

import json, os, re, sys, glob, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(os.path.dirname(__file__))))
DATA = os.path.join(ROOT, 'NPC_and_Opponent_Data')
OUT = os.path.join(DATA, 'Characters')

TOD = ['Morning', 'Afternoon', 'Evening', 'Night']
TOD_LETTER = {'Morning': 'M', 'Afternoon': 'A', 'Evening': 'E', 'Night': 'N'}
LETTER_TOD = {v: k for k, v in TOD_LETTER.items()}

# Loop blocks start after the last irreversible world change on that map:
# Celeste Harbour -- Verdant Forest opens on day 5.
# Verdant Forest  -- the Gym Challenge starts on day 8.
CALENDARS = {
    'Celeste_Harbour': {'authored_through': 8, 'loop': {'from': 5, 'period': 4}},
    'Verdant_Forest': {'authored_through': 12, 'loop': {'from': 9, 'period': 4}},
    'Gym_Challenge_Hall': {'authored_through': 8, 'loop': {'from': 8, 'period': 1}},
    'Gym_Challenge_Reception': {'authored_through': 8, 'loop': {'from': 8, 'period': 4}},
}

# Rotating scenery. Runs on its own cycle so it drifts against the cast cycle --
# deliberate, it keeps every day a different combination.
DRESSING = {
    'Celeste_Harbour': {
        'cycle': {'from': 2, 'period': 4},
        'days': {
            '1': ['TILE_MAPS/JETTY/DAY 1 Boats'],
            '2': ['TILE_MAPS/JETTY/DAY 2 Boats', 'TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 2'],
            '3': ['TILE_MAPS/JETTY/DAY 3 Boats', 'TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 3'],
            '4': ['TILE_MAPS/JETTY/DAY 4 Boats', 'TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 4'],
            '5': ['TILE_MAPS/JETTY/DAY 5 Boats', 'TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 5'],
        },
    },
}

HELP = [
    "days    : '3-6' range | '1,3,5' list | '2-8/2' every other | '4' one day",
    "times   : M=Morning A=Afternoon E=Evening N=Night. Combine: 'M,A' or 'M,A,E,N'",
    "move    : bare pattern name, or {pattern, speed, distance, axis, radius}",
    "requires: 'beaten: NAME' | 'met: NAME' | 'flag: NAME', any prefixed with 'not '.",
    "          Compound gates use the longhand object form.",
    "when    : optional rule list, evaluated TOP TO BOTTOM, FIRST MATCH WINS.",
    "          A rule states when the character is present plus ONLY what differs.",
    "          Anything a rule omits falls back to the character's own value above.",
    "loop    : set false for story characters who must never repeat when the",
    "          calendar loops -- they are matched against the real day instead.",
]

NAME_PREFIX = re.compile(r'^(?:CH|VF|GH|GP)\s+[0-9,\-]+\s*(?:[DMAEN](?:,[DMAEN])*)?\s+(.*)$')

MOVE_EXTRAS = {'patrol_speed': 'speed', 'patrol_distance': 'distance',
               'patrol_axis': 'axis', 'wander_radius': 'radius'}
SAYS_KEYS = {'meet_text': 'meet', 'repeat_text': 'repeat', 'first_win_text': 'first_win',
             'rematch_win_text': 'rematch_win', 'loss_text': 'loss'}
DROP_KEYS = {'name', 'position', 'pattern', 'condition', '_MISSING_ENTRY'}
DROP_KEYS |= set(MOVE_EXTRAS) | set(SAYS_KEYS)

# ---------------------------------------------------------------- fixed edits
# Applied during migration, agreed before the build.
PIKACHU_FANS = ['Pikachu Fan Marina', 'Pikachu Fan Skye', 'Pikachu Fan Cami',
                'Pikachu Fan Juniper', 'Pikachu Fan Raye', 'Pikachu Fan Leaf']
# Old Guy Neighbour belongs to Celeste Harbour until Verdant Forest opens on day 5.
OLD_GUY = 'Old Guy Neighbour'
STORY_NO_LOOP = re.compile(r'^(RIVAL \d+|' + re.escape(OLD_GUY) + r')$')

DUPES = collections.Counter()


def read_json(path):
    return json.loads(open(path, 'rb').read().decode('utf-8-sig'))


NUM_ARRAY = re.compile(r'\[\s*\n\s*(-?\d+(?:\.\d+)?)\s*,\s*\n\s*(-?\d+(?:\.\d+)?)\s*\n\s*\]')


def write_json(path, obj):
    """indent=2 everywhere except coordinate pairs, which stay on one line so a
    character's position reads as a position rather than three lines of noise."""
    text = json.dumps(obj, indent=2, ensure_ascii=False)
    text = NUM_ARRAY.sub(lambda m: '[%s, %s]' % (m.group(1), m.group(2)), text)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text + '\n')


# Two distinct receptionists shared the name "GH 9 Gym Receptionist 2" in the old
# files; the loader disambiguates duplicates with a #n suffix, this gives the
# second one a real name.
RENAMES = {'Gym Receptionist 2 #2': 'Gym Receptionist 4'}

# new character name -> the constants entry it should inherit from.
CONSTANT_ALIASES = {'Gym Receptionist 4': 'Gym Receptionist 2'}


def clean_name(n):
    m = NAME_PREFIX.match(n or '')
    base = m.group(1).strip() if m else (n or '')
    return RENAMES.get(base, base)


def base_name(n):
    """Strip the #n disambiguation suffix added to duplicate keys."""
    return re.sub(r' #\d+$', '', n or '')


def to_move(e):
    if 'pattern' not in e:
        return None          # placeholder entries (the RIVALs) carry no movement at all
    pat = e['pattern']
    extra = {new: e[old] for old, new in MOVE_EXTRAS.items() if old in e}
    if not extra:
        return pat
    out = {'pattern': pat}
    out.update({k: extra[k] for k in ('speed', 'distance', 'axis', 'radius') if k in extra})
    return out


SAYS_ORDER = ['meet', 'repeat', 'first_win', 'rematch_win', 'loss']


def to_says(e):
    got = {new: e[old] for old, new in SAYS_KEYS.items() if e.get(old, '') != ''}
    return {k: got[k] for k in SAYS_ORDER if k in got}


def rewrite_targets(c):
    """Conditions name other characters, so renaming characters has to rename the
    things that point at them too. Missing this left all eight Ex Gym Leaders gated
    on `npc_met: CH 3-6 E Brock`, a name that no longer exists -- they would simply
    never have appeared."""
    if not isinstance(c, dict):
        return c
    out = dict(c)
    if 'target' in out:
        out['target'] = clean_name(out['target'])
    if 'targets' in out and isinstance(out['targets'], list):
        out['targets'] = [clean_name(t) for t in out['targets']]
    if 'conditions' in out and isinstance(out['conditions'], list):
        out['conditions'] = [rewrite_targets(sub) for sub in out['conditions']]
    return out


def to_requires(c):
    if not c:
        return None
    c = rewrite_targets(c)
    t = c.get('type', '')
    simple = {'opponent_defeated': 'beaten: %s', 'opponent_not_defeated': 'not beaten: %s',
              'npc_met': 'met: %s', 'npc_not_met': 'not met: %s'}
    if t in simple:
        return simple[t] % c.get('target', '')
    if t == 'flag_set':
        return 'flag: %s' % c.get('flag', '')
    if t == 'flag_not_set':
        return 'not flag: %s' % c.get('flag', '')
    listy = {'all_opponents_defeated': 'all_beaten', 'any_opponent_defeated': 'any_beaten',
             'not_all_opponents_defeated': 'not_all_beaten'}
    if t in listy:
        return {listy[t]: c.get('targets', [])}
    return c


def payload(entry, consts):
    """The overridable body of one placement, normalised and stripped of
    anything All_NPC_Constant_Data.json already supplies."""
    out = {}
    if 'position' in entry:
        out['at'] = [entry['position']['x'], entry['position']['y']]
    else:
        # No position means nothing to spawn. The RIVALs are like this on purpose
        # -- they become cutscene / collision-triggered forced battles, so their
        # dialogue and schedule are kept but the loader skips them without
        # complaining about data it is meant to ignore.
        out['placeholder'] = True
    mv = to_move(entry)
    if mv is not None:
        out['move'] = mv
    says = to_says(entry)
    if says:
        out['says'] = says
    req = to_requires(entry.get('condition'))
    if req is not None:
        out['requires'] = req
    for k, v in entry.items():
        if k in DROP_KEYS:
            continue
        if consts.get(k) == v:
            continue
        out[k] = v
    return out


def compress_days(days):
    days = sorted(days)
    if not days:
        return ''
    if len(days) >= 3:
        step = days[1] - days[0]
        if step > 1 and all(days[i] - days[i - 1] == step for i in range(1, len(days))):
            return '%d-%d/%d' % (days[0], days[-1], step)
    parts, i = [], 0
    while i < len(days):
        j = i
        while j + 1 < len(days) and days[j + 1] == days[j] + 1:
            j += 1
        parts.append(str(days[i]) if j == i else '%d-%d' % (days[i], days[j]))
        i = j + 1
    return ','.join(parts)


def compress_slots(slots):
    """[(day, tod)] -> [(days_str, times_str)], one pair per distinct time-set."""
    by_day = collections.defaultdict(set)
    for d, t in slots:
        by_day[d].add(t)
    by_times = collections.defaultdict(list)
    for d, ts in by_day.items():
        by_times[tuple(t for t in TOD if t in ts)].append(d)
    out = [(compress_days(days), ','.join(TOD_LETTER[t] for t in times))
           for times, days in by_times.items()]
    return sorted(out, key=lambda p: (len(p[0]), p[0], p[1]))


def expand_days(spec, lo, hi):
    out = set()
    for part in str(spec).split(','):
        part = part.strip()
        if not part:
            continue
        step = 1
        if '/' in part:
            part, s = part.split('/', 1)
            step = int(s)
        if '-' in part.lstrip('-'):
            a, b = part.split('-', 1)
            out.update(range(int(a), int(b) + 1, step))
        else:
            out.add(int(part))
    return {d for d in out if lo <= d <= hi}


def expand_times(spec):
    return [LETTER_TOD[c] for c in str(spec).replace(',', '') if c in LETTER_TOD]


# ------------------------------------------------------------------ load side

def load_records():
    """(map, kind, raw_name) -> list of (day, tod, entry)."""
    recs = collections.defaultdict(list)
    for path in sorted(glob.glob(os.path.join(DATA, '*_*.json'))):
        parts = os.path.basename(path)[:-5].rsplit('_', 2)
        if len(parts) != 3 or not parts[1].isdigit():
            continue
        mp, day, tod = parts[0], int(parts[1]), parts[2]
        if mp not in CALENDARS or tod not in TOD:
            continue
        data = read_json(path)
        for kind in ('npcs', 'opponents'):
            slot_seen = {}
            for e in data.get(kind, []) or []:
                if not (isinstance(e, dict) and e.get('name')):
                    continue
                name = e['name']
                # The same name can appear twice in one section of one file. If the
                # two entries are identical it is a stray duplicate -- drop it. If
                # they differ they are two distinct actors sharing a name, which a
                # name-keyed format cannot represent -- give the later one a suffix.
                sig = json.dumps(e, sort_keys=True, ensure_ascii=False)
                prev = slot_seen.get(name)
                if prev is not None:
                    if sig in prev:
                        DUPES['identical %s' % clean_name(name)] += 1
                        continue
                    name = '%s #%d' % (name, len(prev) + 1)
                    DUPES['renamed %s -> %s' % (clean_name(e['name']), clean_name(name))] += 1
                slot_seen.setdefault(e['name'], set()).add(sig)
                recs[(mp, kind, name)].append((day, tod, e))
    return recs


def apply_fixed_edits(recs):
    """The agreed content changes, applied to the raw records before grouping."""
    log = []
    # 1. Pikachu Fans: drop the NPC variant, move the opponent to the NPC position,
    #    and remove the self-gating so they stay rebattleable through the loop.
    # The fans are battleable in both states: spread across the forest until you
    # beat them, then clustered up by the gate, still rebattleable. The old data
    # expressed that as an opponent entry plus a separate NPC entry; it is now one
    # character with two rules gated on opposite sides of its own defeat.
    npc_pos = {}
    npc_slots = collections.defaultdict(set)
    for (mp, kind, raw), apps in list(recs.items()):
        base = base_name(clean_name(raw))
        if kind == 'npcs' and base in PIKACHU_FANS:
            npc_pos.setdefault(base, apps[0][2]['position'])
            npc_slots[base].update((d, t) for d, t, _e in apps)
            del recs[(mp, kind, raw)]
    for (mp, kind, raw), apps in list(recs.items()):
        cn = base_name(clean_name(raw))
        if kind != 'opponents' or cn not in PIKACHU_FANS:
            continue
        template = apps[0][2]
        have = {(d, t) for d, t, _e in apps}
        # The NPC entries covered evenings the opponent entry did not. Folding them
        # in without carrying those slots would empty the forest at dusk, so the
        # fan is present for the union of both -- battleable now, in both states.
        extra = sorted(npc_slots.get(cn, set()) - have)
        for day, tod in extra:
            apps.append((day, tod, json.loads(json.dumps(template))))

        both = []
        for day, tod, e in apps:
            # Pre-defeat: exactly where and how they always were, out in the forest.
            e['condition'] = {'type': 'opponent_not_defeated', 'target': cn}
            both.append((day, tod, e))
            # Post-defeat: gathered at the old NPC spot, wandering, still battleable.
            after = json.loads(json.dumps(e))
            if cn in npc_pos:
                after['position'] = dict(npc_pos[cn])
            after['pattern'] = 'random_wander'
            after['patrol_speed'] = 20.0
            after['wander_radius'] = 65
            for stale in ('patrol_distance', 'patrol_axis'):
                after.pop(stale, None)
            after['condition'] = {'type': 'opponent_defeated', 'target': cn}
            both.append((day, tod, after))
        recs[(mp, kind, raw)] = both
        log.append('%s: forest spot until beaten, then wanders at (%s, %s); +%d evening slot(s)'
                   % (cn, npc_pos.get(cn, {}).get('x'), npc_pos.get(cn, {}).get('y'), len(extra)))
    # 2. Old Guy Neighbour leaves Celeste Harbour when the forest opens on day 5.
    for (mp, kind, raw), apps in list(recs.items()):
        if mp == 'Celeste_Harbour' and clean_name(raw) == OLD_GUY:
            keep = [a for a in apps if a[0] <= 4]
            dropped = len(apps) - len(keep)
            if not keep:
                del recs[(mp, kind, raw)]
            else:
                recs[(mp, kind, raw)] = keep
            if dropped:
                log.append('%s: removed %d Celeste Harbour slots from day 5 on' % (OLD_GUY, dropped))
    # 3. A character listed as BOTH an npc and an opponent in the same slot spawns two
    #    actors stacked on one tile -- an authoring slip. Keep the battleable one, the
    #    same call already made for the Pikachu Fans.
    occupied = collections.defaultdict(lambda: collections.defaultdict(set))
    for (mp, kind, raw), apps in recs.items():
        for day, tod, _e in apps:
            occupied[(mp, clean_name(raw))][(day, tod)].add(kind)
    for (mp, kind, raw), apps in list(recs.items()):
        if kind != 'npcs':
            continue
        cn = clean_name(raw)
        clash = {s for s, kinds in occupied[(mp, cn)].items() if len(kinds) > 1}
        if not clash:
            continue
        keep = [a for a in apps if (a[0], a[1]) not in clash]
        log.append('%s: dropped %d NPC slot(s) stacked on the opponent version'
                   % (cn, len(apps) - len(keep)))
        if keep:
            recs[(mp, kind, raw)] = keep
        else:
            del recs[(mp, kind, raw)]

    # 4. Seed Celeste Harbour NPC days 7-8 from days 5-6 so the loop block is complete.
    for (mp, kind, raw), apps in list(recs.items()):
        if mp != 'Celeste_Harbour' or kind != 'npcs':
            continue
        add = []
        for day, tod, e in apps:
            if day in (5, 6) and not any(a[0] == day + 2 and a[1] == tod for a in apps):
                add.append((day + 2, tod, json.loads(json.dumps(e))))
        if add:
            recs[(mp, kind, raw)] = apps + add
    log.append('seeded Celeste Harbour NPC days 7-8 from days 5-6')
    return log


def collapse_constants(consts):
    """All_NPC_Constant_Data.json is keyed by the OLD prefixed names, several of
    which collapse to one character ("CH 1 D Old Guy Neighbour", "CH 2 D ...").

    A field only stays constant if every variant of that name agrees on it.
    Where they disagree it was never constant data -- gift_type/gift_value differ
    per encounter, and Sunbathing Dude 1 even changes sprite and message_colour
    between days. Those get returned as `varying` so build_characters can push
    them down into the `when` rule they belong to instead of losing them.

    Returns (collapsed, varying_fields) keyed [section][clean_name].
    """
    collapsed = {}
    varying = {}
    for section in ('npcs', 'opponents'):
        groups = collections.defaultdict(dict)
        for raw, body in consts.get(section, {}).items():
            groups[clean_name(raw)][raw] = body
        collapsed[section] = {}
        varying[section] = {}
        for cn, variants in groups.items():
            all_fields = set()
            for body in variants.values():
                all_fields |= set(body)
            keep, drop = {}, set()
            for field in all_fields:
                seen = {json.dumps(b.get(field), sort_keys=True) for b in variants.values()}
                if len(seen) == 1 and list(variants.values())[0].get(field) is not None:
                    keep[field] = list(variants.values())[0][field]
                else:
                    drop.add(field)
            collapsed[section][cn] = keep
            varying[section][cn] = drop
    return collapsed, varying


def build_characters(recs, consts, collapsed, varying):
    """(map, section, clean_name) -> character dict."""
    raw_consts = {}
    for section in ('npcs', 'opponents'):
        for raw, body in consts.get(section, {}).items():
            raw_consts[(section, raw)] = body

    grouped = collections.defaultdict(list)
    for (mp, kind, raw), apps in recs.items():
        cn = clean_name(raw)
        for day, tod, e in apps:
            grouped[(mp, cn)].append((kind, day, tod, e, raw))

    chars = collections.defaultdict(dict)
    for (mp, cn), apps in sorted(grouped.items()):
        kinds = collections.Counter(k for k, _d, _t, _e, _r in apps)
        section = kinds.most_common(1)[0][0]
        cst = collapsed.get(section, {}).get(cn, {})
        varies = varying.get(section, {}).get(cn, set())

        variants = collections.defaultdict(list)
        for kind, day, tod, e, raw in apps:
            # Fold in the constants for the ORIGINAL prefixed name first, so the
            # data each appearance carries is exactly what the game used to see.
            merged = dict(e)
            for field, value in raw_consts.get((kind, raw), {}).items():
                if field in varies and field not in merged:
                    merged[field] = value
            body = payload(merged, cst)
            if kind != section:
                body['kind'] = 'npc' if kind == 'npcs' else 'opponent'
            variants[json.dumps(body, sort_keys=True, ensure_ascii=False)].append((day, tod))

        # Whichever variant becomes the character's defaults should read as its
        # normal state: ungated first, then the "not yet" gate, then the "already
        # done" one. Otherwise a character defaults to its post-quest self with its
        # original position demoted to an override, which is backwards.
        def variant_rank(sig):
            req = json.loads(sig).get('requires')
            if req is None:
                return 0
            if isinstance(req, str) and req.startswith('not '):
                return 1
            return 2

        ordered = sorted(variants.items(),
                         key=lambda kv: (-len(kv[1]), variant_rank(kv[0]), kv[0]))
        base = json.loads(ordered[0][0])
        entry = dict(base)

        # Days past `authored_through` are produced by the calendar loop, so listing
        # them would be redundant noise. Story characters (loop:false) keep theirs.
        cal = CALENDARS.get(mp, {})
        horizon = cal.get('authored_through', 9999) if not STORY_NO_LOOP.match(cn) else 9999

        rules = []
        for sig, slots in ordered:
            body = json.loads(sig)
            diff = {k: v for k, v in body.items() if base.get(k) != v}
            for k in base:
                if k not in body:
                    diff[k] = None
            kept = [(d, t) for d, t in slots if d <= horizon]
            if not kept:
                continue
            for days, times in compress_slots(kept):
                rule = {'days': days, 'times': times}
                rule.update(diff)
                rules.append(rule)

        if not rules:
            continue
        if len(rules) == 1:
            entry['days'] = rules[0]['days']
            entry['times'] = rules[0]['times']
        else:
            entry['when'] = rules
        if STORY_NO_LOOP.match(cn):
            entry['loop'] = False
        chars[(mp, section)][cn] = entry
    return chars


ORDER = ['kind', 'at', 'days', 'times', 'move', 'loop', 'requires', 'says', 'when']


def tidy(entry, keep_null=False):
    """Order keys for readability. A null inside a `when` rule is meaningful --
    it clears a field the character sets at its top level -- so it survives."""
    out = {}
    for k in ORDER:
        if k in entry and (keep_null or entry[k] is not None):
            out[k] = entry[k]
    for k in sorted(entry):
        if k not in out and (keep_null or entry[k] is not None):
            out[k] = entry[k]
    if isinstance(out.get('says'), dict):
        out['says'] = {k: out['says'][k] for k in SAYS_ORDER if k in out['says']}
    if 'when' in out:
        out['when'] = [tidy(r, keep_null=True) for r in out['when']]
    return out


def write_constants(collapsed, chars):
    """Rewrite All_NPC_Constant_Data.json keyed by the same clean names the
    character files use. Without this every NPC silently loses its sprite,
    friendly_name and message_colour, because the lookup is by name."""
    used = collections.defaultdict(set)
    for (_mp, section), cast in chars.items():
        for name in cast:
            used[section].add(name)
    doc = collections.OrderedDict()
    for section in ('npcs', 'opponents'):
        out = {}
        for name in sorted(collapsed.get(section, {})):
            body = collapsed[section][name]
            if body:
                out[name] = body
        # A character split out of another during migration inherits its
        # constants -- Gym Receptionist 4 was the second entry sharing
        # Receptionist 2's name, so it wears the same sprite and colour.
        for new_name, source in CONSTANT_ALIASES.items():
            if new_name in used[section] and source in out:
                out[new_name] = dict(out[source])
        doc[section] = out
    path = os.path.join(DATA, 'All_NPC_Constant_Data.json')
    write_json(path, doc)
    missing = []
    for section in ('npcs', 'opponents'):
        for name in sorted(used[section]):
            if name not in doc[section]:
                missing.append('%s/%s' % (section, name))
    print('constants rewritten: %d npcs, %d opponents'
          % (len(doc['npcs']), len(doc['opponents'])))
    if missing:
        print('  %d character(s) have no constants entry (placeholders): %s'
              % (len(missing), ', '.join(m.split('/')[-1] for m in missing[:6])))
    return missing


SNAPSHOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_migration_snapshot.json')


def load_source_constants():
    """The constants as they were BEFORE migration, keyed by the old prefixed
    names. build() snapshots them on its first run, because it rewrites the real
    file in place and verify still needs the original to compare against."""
    if os.path.exists(SNAPSHOT):
        return read_json(SNAPSHOT)
    current = read_json(os.path.join(DATA, 'All_NPC_Constant_Data.json'))
    if any(NAME_PREFIX.match(k) for k in current.get('npcs', {})):
        write_json(SNAPSHOT, current)     # still the old format -- capture it
    return current


def build():
    consts = load_source_constants()
    collapsed, varying = collapse_constants(consts)
    recs = load_records()
    log = apply_fixed_edits(recs)
    chars = build_characters(recs, consts, collapsed, varying)

    # Interior maps with no schedule at all -- their cast is simply always present.
    for src, mp in (('Card_Mart_NPCs', 'Card_Mart'), ('Rocket_Mart_NPCs', 'Rocket_Mart'),
                    ('Windmill', 'Windmill')):
        data = read_json(os.path.join(DATA, src + '.json'))
        doc = collections.OrderedDict()
        doc['_help'] = HELP
        doc['map'] = mp
        doc['calendar'] = {}
        for section in ('npcs', 'opponents'):
            out = {}
            for e in data.get(section, []) or []:
                if isinstance(e, dict) and e.get('name'):
                    cst = consts.get(section, {}).get(e['name'], {})
                    out[e['name']] = tidy(payload(e, cst))
            doc[section] = out
        write_json(os.path.join(OUT, mp + '.json'), doc)
        print('%-26s %3d npcs  %3d opponents  (always present)'
              % (mp, len(doc['npcs']), len(doc['opponents'])))

    for mp in sorted(CALENDARS) + ['Gym_Plaza']:
        doc = collections.OrderedDict()
        doc['_help'] = HELP
        doc['map'] = mp
        doc['calendar'] = CALENDARS.get(mp, {'authored_through': 1, 'loop': {'from': 1, 'period': 1}})
        if mp in DRESSING:
            doc['dressing'] = DRESSING[mp]
        doc['npcs'] = {n: tidy(e) for n, e in sorted(chars.get((mp, 'npcs'), {}).items())}
        doc['opponents'] = {n: tidy(e) for n, e in sorted(chars.get((mp, 'opponents'), {}).items())}
        write_json(os.path.join(OUT, mp + '.json'), doc)
        print('%-26s %3d npcs  %3d opponents' % (mp, len(doc['npcs']), len(doc['opponents'])))
    print()
    write_constants(collapsed, chars)
    print()
    for line in log:
        print('  edit: ' + line)


# ---------------------------------------------------------------- verify side
# Re-expands the new files back into every (map, day, time) slot and compares the
# EFFECTIVE spawn -- character body merged under All_NPC_Constant_Data.json, which
# is what MapManager actually hands to the actor -- against the same merge done on
# the original day files. Byte-comparing the raw files would flag the redundant
# constants we deliberately stripped, so this compares what the game sees instead.

REV_SAYS = {v: k for k, v in SAYS_KEYS.items()}
REV_MOVE = {'speed': 'patrol_speed', 'distance': 'patrol_distance',
            'axis': 'patrol_axis', 'radius': 'wander_radius'}


def from_requires(r):
    if r is None:
        return None
    if isinstance(r, dict):
        listy = {'all_beaten': 'all_opponents_defeated', 'any_beaten': 'any_opponent_defeated',
                 'not_all_beaten': 'not_all_opponents_defeated'}
        for k, t in listy.items():
            if k in r:
                return {'type': t, 'targets': r[k]}
        return r
    neg = r.startswith('not ')
    body = r[4:] if neg else r
    head, _, arg = body.partition(':')
    arg = arg.strip()
    if head == 'beaten':
        return {'type': 'opponent_not_defeated' if neg else 'opponent_defeated', 'target': arg}
    if head == 'met':
        return {'type': 'npc_not_met' if neg else 'npc_met', 'target': arg}
    if head == 'flag':
        return {'type': 'flag_not_set' if neg else 'flag_set', 'flag': arg}
    return r


def to_legacy(body):
    e = {}
    if body.get('at') is not None:
        e['position'] = {'x': body['at'][0], 'y': body['at'][1]}
    mv = body.get('move')
    if isinstance(mv, str):
        e['pattern'] = mv
    elif isinstance(mv, dict):
        e['pattern'] = mv.get('pattern')
        for new, old in REV_MOVE.items():
            if new in mv:
                e[old] = mv[new]
    for new, val in (body.get('says') or {}).items():
        e[REV_SAYS[new]] = val
    if body.get('requires') is not None:
        e['condition'] = from_requires(body['requires'])
    for k, v in body.items():
        if k in ('at', 'move', 'says', 'requires', 'days', 'times', 'when', 'loop', 'kind'):
            continue
        e[k] = v
    return e


def resolve_day(cal, day):
    lp = cal.get('loop')
    if not lp:
        return day
    start, period = lp['from'], lp['period']
    return day if day < start else start + ((day - start) % period)


def rule_matches(rule, day, tod):
    if rule.get('days') is not None and day not in expand_days(rule['days'], 0, 9999):
        return False
    if rule.get('times') is not None and tod not in expand_times(rule['times']):
        return False
    return True


def cast_for(doc, day, tod):
    """name -> (section, legacy entry dict) for one slot."""
    cal = doc.get('calendar', {})
    rday = resolve_day(cal, day)
    out = {}
    for section in ('npcs', 'opponents'):
        for name, ch in doc.get(section, {}).items():
            eff = rday if ch.get('loop', True) else day
            body = {k: v for k, v in ch.items() if k not in ('when', 'days', 'times', 'loop')}
            if 'when' in ch:
                hit = next((r for r in ch['when'] if rule_matches(r, eff, tod)), None)
                if hit is None:
                    continue
                for k, v in hit.items():
                    if k in ('days', 'times'):
                        continue
                    if v is None:
                        body.pop(k, None)
                    else:
                        body[k] = v
            elif not rule_matches(ch, eff, tod):
                continue
            sect = section
            if body.get('kind') == 'npc':
                sect = 'npcs'
            elif body.get('kind') == 'opponent':
                sect = 'opponents'
            out[name] = (sect, to_legacy(body))
    return out


def merged(entry, consts, section, name):
    cst = consts.get(section, {}).get(name, {})
    m = dict(entry)
    for k, v in cst.items():
        m.setdefault(k, v)
    # Both are bookkeeping rather than content: _MISSING_ENTRY was a stale marker
    # in the old files, `placeholder` is the new flag replacing it.
    m.pop('_MISSING_ENTRY', None)
    m.pop('placeholder', None)
    # Conditions point at characters by name, so the old side has to be read
    # through the same rename as the new side for the comparison to mean anything.
    if isinstance(m.get('condition'), dict):
        m['condition'] = rewrite_targets(m['condition'])
    return m


def authored_domain():
    """(map, section) -> the set of days that section was actually authored for.
    Anything the new files add outside this is the loop filling a gap the old
    format left empty, not a regression."""
    dom = collections.defaultdict(set)
    for path in sorted(glob.glob(os.path.join(DATA, '*_*.json'))):
        parts = os.path.basename(path)[:-5].rsplit('_', 2)
        if len(parts) != 3 or not parts[1].isdigit():
            continue
        mp, day, tod = parts[0], int(parts[1]), parts[2]
        if mp not in CALENDARS or tod not in TOD:
            continue
        data = read_json(path)
        for section in ('npcs', 'opponents'):
            if data.get(section):
                dom[(mp, section)].add(day)
    return dom


def verify():
    # Two different constants files: the old prefixed one the day files were
    # written against, and the rewritten one the character files use. Merging each
    # side with its own is the whole point -- it proves the rename didn't drop a
    # sprite, a colour or a gift on the way through.
    source_consts = load_source_constants()
    consts = read_json(os.path.join(DATA, 'All_NPC_Constant_Data.json'))
    docs = {mp: read_json(os.path.join(OUT, mp + '.json')) for mp in CALENDARS}
    dom = authored_domain()

    expected = 0
    fills = 0
    failures = collections.defaultdict(list)
    slots = 0
    for path in sorted(glob.glob(os.path.join(DATA, '*_*.json'))):
        parts = os.path.basename(path)[:-5].rsplit('_', 2)
        if len(parts) != 3 or not parts[1].isdigit():
            continue
        mp, day, tod = parts[0], int(parts[1]), parts[2]
        if mp not in CALENDARS or tod not in TOD:
            continue
        slots += 1
        old = {}
        for section in ('npcs', 'opponents'):
            for e in read_json(path).get(section, []) or []:
                if isinstance(e, dict) and e.get('name'):
                    cn = clean_name(e['name'])
                    body = {k: v for k, v in e.items() if k != 'name'}
                    # merged against the ORIGINAL prefixed key, which is what the
                    # game actually looked up before the migration.
                    old[cn] = merged(body, source_consts, section, e['name'])
        new = {n: merged(b, consts, s, n) for n, (s, b) in cast_for(docs[mp], day, tod).items()}

        sections = {n: s for n, (s, _b) in cast_for(docs[mp], day, tod).items()}
        for n in set(old) | set(new):
            if _is_expected(mp, n, day):
                expected += 1
                continue
            if n not in old and day not in dom.get((mp, sections.get(n, 'npcs')), set()):
                fills += 1          # loop populating a day the old format left empty
                continue
            if n not in new:
                failures['%s missing' % n].append('%s d%d %s' % (mp, day, tod))
            elif n not in old:
                failures['%s unexpected' % n].append('%s d%d %s' % (mp, day, tod))
            elif old[n] != new[n]:
                diff = sorted(k for k in set(old[n]) | set(new[n])
                              if old[n].get(k) != new[n].get(k))
                failures['%s differs (%s)' % (n, ','.join(diff))].append(
                    '%s d%d %s' % (mp, day, tod))

    print('slots re-expanded : %d' % slots)
    print('agreed edits      : %d' % expected)
    print('loop fills        : %d  (days the old files left empty)' % fills)
    print('UNEXPECTED DIFFS  : %d' % len(failures))
    for k, v in sorted(failures.items())[:25]:
        print('   %-58s %d slots  e.g. %s' % (k[:58], len(v), v[0]))
    return 0 if not failures else 1


def _is_expected(mp, name, day):
    if base_name(name) in PIKACHU_FANS or name == 'Pikachu Mum':
        return True
    if name == OLD_GUY:
        return True
    if name in ('Gym Receptionist 2', 'Gym Receptionist 4'):
        return True          # one name split into two distinct receptionists
    if mp == 'Celeste_Harbour' and day in (7, 8):
        return True
    return False


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'build'
    if cmd == 'build':
        build()
    elif cmd == 'verify':
        sys.exit(verify())
    else:
        print('unknown command: %s' % cmd)
        sys.exit(1)
