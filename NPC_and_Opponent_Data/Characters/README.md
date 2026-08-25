# Character files

One file per map. Every NPC and opponent on that map is defined **once**, with a
schedule describing when they appear and what changes about them when they do.

This replaced 124 per-day files (`Celeste_Harbour_5_Morning.json` and friends)
that held 2,511 placement records for 327 characters — the same person copied out
once per day/time slot. Moving someone meant editing every copy, and they drifted
apart when you didn't. Now moving someone is one edit.

| | old | new |
|---|---|---|
| files | 124 | 5 |
| records | 2,511 | 253 characters |
| on disk | 2.1 MB | 212 KB |

---

## The three rules

1. **`days` / `times` at the top level** if the character never varies.
   Use `when` only if they do.
2. **`when` rules run top to bottom. First match wins.**
3. **A rule inherits everything it doesn't state.** It says *when* the character
   is present, plus *only what differs* from the character's own values above it.

Everything else is the field names you already know.

---

## File shape

```jsonc
{
  "_help": [ ... ],                  // cheat sheet, ignored by the game
  "map": "Celeste_Harbour",
  "calendar": { "authored_through": 8, "loop": { "from": 5, "period": 4 } },
  "dressing": { ... },               // optional, rotating scenery
  "npcs":      { "Name": { ... } },
  "opponents": { "Name": { ... } }
}
```

Which section a character sits in decides whether they're battleable. There's no
`kind` field to remember — except on a rule that flips it (see *Kind switching*).

---

## Fields

| field | meaning |
|---|---|
| `at` | `[x, y]` position |
| `days` | `"3-6"` range · `"1,3,5"` list · `"2-8/2"` every other · `"4"` one day |
| `times` | `M` Morning · `A` Afternoon · `E` Evening · `N` Night. Combine: `"M,A"` |
| `move` | bare pattern name, or `{ pattern, speed, distance, axis, radius }` |
| `says` | `meet` · `repeat` · `first_win` · `rematch_win` · `loss` |
| `requires` | a gate — see below |
| `loop` | `false` for story characters that must never repeat |
| `when` | rule list, first match wins |

Anything else (`match_effects`, `restrictions`, `npc_type`, `shop_id`,
`gift_type`, `sleeve`, …) carries through untouched.

Sprite, deck, prizes and rewards are **not** here — they live in
`../All_NPC_Constant_Data.json`, keyed by the same name. Only put a field here if
it needs to *differ* from the constant.

### `requires`

```jsonc
"requires": "beaten: Gym Challenge Brock"       // opponent_defeated
"requires": "not beaten: Pikachu Fan Marina"    // opponent_not_defeated
"requires": "met: Old Guy Neighbour"            // npc_met
"requires": "flag: gym_entry_paid"              // flag_set
```

Any of them takes a `not ` prefix. Compound gates use the longhand object form:

```jsonc
"requires": { "all_beaten": ["Pikachu Fan Marina", "Pikachu Fan Skye"] }
```

---

## Worked examples

### The common case

```jsonc
"Bad Dude Paul": {
  "at": [-810, 2550],
  "days": "2,4-5,8",
  "times": "N",
  "move": "idle_random",
  "says": {
    "meet": "Heh you want to try and beat me kid??",
    "repeat": "Damn... they're gonna kick me out of the cool guy biker gang for this.",
    "first_win": "Heh you're pretty tough, you wanna join our gang?",
    "rematch_win": "Now they're DEFINITELY going to kick me out...",
    "loss": "Heh heh heh, too easy."
  }
}
```

### Different dialogue in the evening

The first rule sets nothing — it just means *"also here, exactly as described above."*

```jsonc
"Bakery Shopkeeper": {
  "at": [2570, 1650],
  "move": "idle_down",
  "says": {
    "meet": "Get your freshly baked pastries, cakes and bread all here.",
    "repeat": "Everything is freshly baked this morning and some of the bread is still warm!"
  },
  "when": [
    { "days": "3-8", "times": "M,A" },
    { "days": "3-8", "times": "E",
      "says": { "repeat": "Plenty of items still fresh to enjoy!" } }
  ]
}
```

### Somewhere different every day

`loop: false` opts out of the calendar loop entirely — see *Calendars* below.

```jsonc
"Old Guy Neighbour": {
  "at": [-150, 1710],
  "loop": false,
  "move": { "pattern": "random_wander", "radius": 65, "speed": 30.0 },
  "says": { "meet": "Oh hello there neighbour!...", "repeat": "..." },
  "when": [
    { "days": "1", "times": "M,A" },
    { "days": "2", "times": "M,A", "at": [-575, 1962], "move": "idle_down",
      "says": { "meet": "Good morning! I'm going to spend my day here I think...", "repeat": "..." } },
    { "days": "3-4", "times": "E", "at": [-375, 1625], "move": "idle_down",
      "says": { "meet": "It's been a long day for sure...", "repeat": "..." } }
  ]
}
```

### Branching on progress, and switching kind

A rule can gate on `requires` as well as days/times, and the resolver picks the
first rule whose **days, times _and_ condition** all pass. That lets one character
hold several states at once. The Pikachu Fans use four — where they stand follows
whether you have beaten them, whether they can be battled follows the time of day:

```jsonc
"Pikachu Fan Marina": {
  "at": [3272, 1427],
  "move": "idle_random",
  "requires": "not beaten: Pikachu Fan Marina",
  "says": { "meet": "Have you ever seen a Pikachu Surf...", ... },
  "when": [
    { "days": "5-12", "times": "M,A" },
    { "days": "5-12", "times": "E", "kind": "npc", "says": { ...quieter lines... } },
    { "days": "5-12", "times": "M,A", "at": [0, 100], "move": { "pattern": "random_wander", ... },
      "requires": "beaten: Pikachu Fan Marina" },
    { "days": "5-12", "times": "E", "kind": "npc", "at": [0, 100], "move": { ... },
      "says": { ... }, "requires": "beaten: Pikachu Fan Marina" }
  ]
}
```

Two things to know:

- **A rule with no `requires` inherits the character's.** The first two rules above
  are gated on `not beaten` without repeating it, the same way they inherit `at`.
- **They are a group, and the evening state exists for a reason.** None of the six
  can be battled after dark, so when time rolls over to night they all vanish
  together. Without it, beating one child at the moment time advanced would respawn
  that child alone in the forest with no parent — see `Pikachu Mum`, who is
  likewise never battleable in the evening and is present on every day they are.

### Clearing an inherited field

`null` in a rule removes a field the character sets above it:

```jsonc
"when": [
  { "days": "5", "requires": null }
]
```

---

## Calendars

```jsonc
"calendar": { "authored_through": 8, "loop": { "from": 5, "period": 4 } }
```

Days up to `from` are authored literally. From then on, day `D` resolves to
authored day `from + ((D - from) % period)` — so day 9 is day 5, day 12 is day 8,
day 847 is day 7. **The player can play forever and never run out of content.**

| map | loop | why there |
|---|---|---|
| `Celeste_Harbour` | from 5, period 4 | Verdant Forest opens on day 5 |
| `Verdant_Forest` | from 9, period 4 | the Gym Challenge starts on day 8 |
| `Gym_Challenge_Hall` | from 8, period 1 | day 8 repeats; the 8 leaders never change |
| `Gym_Challenge_Reception` | from 8, period 4 | opens day 8, repeating cast |
| `Gym_Plaza` | — | not populated yet |

> **The loop block must start after the last irreversible world change on that
> map.** Otherwise the loop rewinds the world — a Celeste Harbour loop covering
> day 3 would drag Old Guy Neighbour back from the forest on day 7.

**The loop repeats the stage, not the play.** Day 15 resolves to day 5's cast in
day 5's positions. It does not touch your save. An opponent gated
`not beaten: self` is still filtered out once you've beaten them, permanently.
So: **anything you want farmable in the endgame must not be gated on its own
defeat.**

Don't list days past `authored_through` in a character's schedule — the loop
generates them. `loop: false` characters are the exception: they're matched
against the real day, so their days can run as far as you like and they simply
stop existing afterwards.

---

## Dressing

Rotating scenery, on its own cycle, independent of the cast cycle.

```jsonc
"dressing": {
  "cycle": { "from": 2, "period": 4 },
  "days": {
    "1": ["TILE_MAPS/JETTY/DAY 1 Boats"],
    "2": ["TILE_MAPS/JETTY/DAY 2 Boats", "TILE_MAPS/OBJECTS/CAR PARK CARS/CARS DAY 2"]
  }
}
```

The cycle starts at **2**, not 1: day 1 is the intro day and has boats but no cars,
so a cycle including it emptied the car park every fifth day. Day 1 now resolves
only to itself and days 2–5 rotate forever.

> **Watch the period against the map's cast cycle.** Celeste Harbour's cast also
> runs period 4, so the two are currently in lockstep — day 9 looks exactly like
> day 5, scenery and people both. Giving dressing a period that shares no factor
> with the cast's (5 against 4) makes every day a different combination and hides
> the loop, which needs a fifth entry in `days`.

Nodes listed for the resolved day are shown; everything named anywhere in the
block and not listed for today is hidden. Permanent unlocks (the forest gate, the
station gate, beach cones) are **not** dressing — they follow the real date and
never come back.

---

## Placing characters in-game

Guessing coordinates in a text file is the slow way. Run the game (debug build —
`DebugMode.is_enabled()`), stand where you want someone, and press:

| key | |
|---|---|
| `F` | open / close the placement tool |
| `Tab` / `Shift+Tab` | select the next / previous actor — **nearest first**, and the camera pans to whoever is selected (tinted green) |
| `G` | grab or drop — a grabbed actor follows you, tinted orange, with its collision off |
| `Ctrl` + arrows | nudge 1px (hold `Shift` for 10px). Holding `Ctrl` also freezes the player, since arrows are movement |
| `R` | cycle movement pattern |
| `Enter` | save every pending change to this map's character file |
| `Esc` | close — refuses while changes are unsaved |

**The player has no collision while the tool is open.** That keeps dropping an
actor from shunting you a few pixels into scenery, makes crossing a big map much
quicker, and lets you place characters somewhere the player can never stand — a
maintenance worker out on the water fixing a light is scenery for that time slot,
not somebody you are meant to reach. The one catch: you can close the tool while
standing inside geometry, so walk clear first (or press `F` again to walk out).

### What a save actually rewrites

The write goes back to **the rule that produced that actor today, edited in place.**
It does *not* split the current day out into a new rule.

So if a character has one rule reading `"days": "8,12"` and you move them on day 8,
they move on **day 12 as well** — the whole rule changed. That is normally what you
want when repositioning someone, but it is worth being deliberate about, so the HUD
spells the blast radius out before you press Enter:

```
edit applies to: when-rule #3 — days 8,12, M,A,E
```

Matching the character's top-level `at` instead (`the character's defaults`) is
broader still — it feeds every rule that doesn't set its own position.

If you want a position that applies to one day only, add a rule for that day in the
JSON first, then reload and move the actor — the tool will match the new narrower
rule and edit that. Combine with the date and time debug keys (`1`–`0`,
`H`/`J`/`K`/`L`) to reach the slot you want.

---

## Verifying

```
py Scripts/Utilities/migrate_npc_data.py verify        # data-level (needs the old day files)
Godot --headless --script res://Scripts/Utilities/verify_schedule.gd
```

The second one is the live check and the one that still works. It resolves every
map across days 1–20 and asserts:

- every entry has a name and a position (unless flagged `placeholder`)
- nobody spawns twice in one slot
- **every character resolves a sprite**, from its own entry or from
  `All_NPC_Constant_Data.json`
- `day == day + period` holds seven cycles out
- `loop: false` characters stay gone through day 45

It must report **`FAILURES: 0`**.

> The sprite check exists because the constants file is keyed **by name**. The
> migration renamed characters (`CH 1 D Old Guy Neighbour` → `Old Guy Neighbour`),
> and renaming the placement files without renaming the constants made every NPC
> silently lose its sprite, crashing the map load on the first one. Fields the
> prefixed variants disagreed on — `gift_type`, `gift_value`, and `Sunbathing Dude
> 1`'s sprite and colour, which genuinely change between days — were never
> constant data and now live in the `when` rules instead.

`migrate_npc_data.py` was the one-time migration from the 124 per-day files. Those
files are gone, so `build` and `verify` only run against a checkout that still has
them — kept for reference and for the record of what the migration did.
