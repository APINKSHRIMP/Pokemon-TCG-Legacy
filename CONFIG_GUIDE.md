# Pokémon TCG Legacy — Configuration Guide

A living reference for every JSON-driven knob in the game. Each section lists
the **field name**, the **allowed values**, the **file(s) that consume it**,
and a **minimal example**.

> Keep this file open while editing data files in `NPC_and_Opponent_Data/`,
> `Card_Set_Data/`, `Map_Data/`, and `Player_Data/`.

---

## 1. Battle Conditions (Deck Restrictions)

Opponents can demand the player meet specific deck requirements before a
battle starts. The restriction is attached to an opponent entry inside any
`NPC_and_Opponent_Data/<Map>_<Day>_<Time>.json` file under the `opponents`
array.

**Validator:** `Scripts/Global_Scripts/Deck_Validation_Helper.gd`
**Popup UI:** `Scripts/Global_Scripts/Deck_Validation_Popup.gd`
**Trigger:** `MapManager._on_yes_pressed` runs validation just before the
battle scene loads. If validation fails, a popup (or text-only message) is
shown and the battle is aborted.

### 1.1 Display modes

| Mode | Triggered by | What the player sees |
|---|---|---|
| `banned` | `banned_card_ids` / `banned_card_names` hit | Full-screen grid titled **"Banned cards"** showing every card on the NPC's banlist |
| `invalid` | Structural rule violated (type, set, supertype, HP, etc.) | Full-screen grid titled **"Cards in your deck that aren't allowed"** showing the offending cards from the player's deck |
| `missing` | Required-card quantity not met | Standard messagebox text only, e.g. `"You can't battle me yet:  • Need at least 4× Alakazam (have 0)"` |

If multiple categories fail at once, priority is **banned > invalid > missing**.
Missing-requirement lines are appended to the popup body when an `invalid`-mode
popup is shown so the player sees everything at once.

### 1.2 Restriction schema

```jsonc
"restrictions": {

  // ────── Strict blacklists (mode = "banned") ──────
  "banned_card_ids":   ["base1-88", "base1-89"],       // exact card ids
  "banned_card_names": ["Professor Oak", "Bill"],      // by name, matches across all sets

  // ────── Required-quantity rules (mode = "missing") ──────
  "required_card_ids":   [{"id": "base1-1", "min": 4}],
  "required_card_names": [{"name": "Alakazam",       "min": 4},
                          {"name": "Psychic Energy", "min": 10}],
  "min_stage_2_pokemon": 4,                            // at least N Stage-2 Pokémon

  // ────── Structural rules (mode = "invalid") ──────
  "allowed_pokemon_types":         ["Fire"],           // Pokémon type whitelist
  "allowed_energy_types":          ["Fire"],           // Energy cards matched by NAME
  "allowed_set_ids":               ["base1", "base2"], // card id prefix whitelist
  "allowed_pokemon_name_prefixes": ["Dark "],          // Pokémon name must start with one
  "banned_pokemon_name_prefixes":  ["Dark "],          // Pokémon name must NOT start with one
  "no_trainers":         true,
  "no_special_energies": true,
  "special_energies_only": true,                       // basic energies forbidden
  "basic_pokemon_only":  true,                         // Stage 1/2 forbidden
  "max_hp":              60,                           // Pokémon HP cap
  "delta_species_only":  true,                         // Pokémon name must contain " δ"
  "no_ex_cards":         true                          // any subtype "ex" forbidden
}
```

### 1.3 Field reference

| Field | Type | Notes |
|---|---|---|
| `banned_card_ids` | `String[]` | Exact card ids (`"base1-88"`). Case-insensitive. |
| `banned_card_names` | `String[]` | Card names. Matches across **all** sets, so `"Professor Oak"` catches every reprint. |
| `required_card_ids` | `[{id, min}]` | Per-card minimum quantity; matches one exact id. |
| `required_card_names` | `[{name, min}]` | Per-name minimum quantity; sums copies across all sets. **Use this for energies** (e.g. `"Psychic Energy"`) because energy cards reprint into many sets. |
| `min_stage_2_pokemon` | `int` | Total Stage-2 Pokémon copies required. |
| `allowed_pokemon_types` | `String[]` | Pokémon `types[]` field must intersect. Values: `Fire`, `Water`, `Grass`, `Lightning`, `Psychic`, `Fighting`, `Colorless`, `Darkness`, `Metal`, `Dragon`, `Fairy`. |
| `allowed_energy_types` | `String[]` | Matched off the energy card's **name** (`"Fire Energy"` → `Fire`). Different sets share the same name, so cross-set Fire Energies all pass. |
| `allowed_set_ids` | `String[]` | Card id prefix (e.g. `base1`, `base5`, `gym1`). Applies to all card types. |
| `allowed_pokemon_name_prefixes` | `String[]` | Case-insensitive name prefix list. Use `"Dark "` (with trailing space) for Team-Rocket Dark Pokémon, `"Light "` for Neo Destiny Light Pokémon. |
| `banned_pokemon_name_prefixes` | `String[]` | Reverse of the above. |
| `no_trainers` | `bool` | Forbid all Trainer cards. |
| `no_special_energies` | `bool` | Forbid any energy with subtype `"Special"`. |
| `special_energies_only` | `bool` | Forbid any energy with subtype `"Basic"`. |
| `basic_pokemon_only` | `bool` | Only `"Basic"` or `"Baby"` subtype Pokémon. |
| `max_hp` | `int` | Pokémon with HP > N are invalid. Trainer/Energy cards ignore this. |
| `delta_species_only` | `bool` | Pokémon name must contain " δ" (the delta-species marker). |
| `no_ex_cards` | `bool` | Any card whose `subtypes` array contains `"ex"` is invalid. |

### 1.4 Example: gym challenge

```jsonc
{
  "name": "Gym Leader Erika",
  "meet_text": "As part of the Gym Challenge you may only use Grass Pokémon. No Trainers either!",
  // ... other opponent fields ...
  "restrictions": {
    "allowed_pokemon_types": ["Grass"],
    "no_trainers": true
  }
}
```

### 1.5 Set id reference (for `allowed_set_ids`)

| Set id | Set name |
|---|---|
| `base1` | Base Set |
| `base2` | Jungle |
| `base3` | Fossil |
| `base5` | Team Rocket |
| `basep` | Wizards Promo |
| `gym1` | Gym Heroes |
| `gym2` | Gym Challenge |
| `neo1`–`neo4` | Neo Genesis / Discovery / Revelation / Destiny |
| `ecard1`–`ecard3` | Expedition / Aquapolis / Skyridge |
| `ex1`–`ex16` | EX era |
| `np` | Nintendo Promo |
| `pop1`–`pop6` | POP series |
| `si1` | Southern Islands |

---

## 2. Match Effects (Special Battle Rules)

Opponents can carry **match-wide rule modifiers** that are active for the whole
battle — e.g. "all Fire Pokémon deal +20 damage", "no retreating", "every coin
flip lands on heads". They are the in-battle counterpart to §1's pre-battle
deck restrictions, and both blocks can sit on the same opponent entry.

**Parser / rules API:** `Scripts/Main_Match_Gameplay_Scripts/Match_Effects.gd`
(the schema is also documented in its header comment)
**Loaded by:** `MapManager._load_and_spawn_opponents` → re-read in the match by
`Main_Match_Core_Gameplay_Script.load_opponent_data_by_name`
**Announced:** at the start of **each game** (after bench setup, before the
opening coin flip) as a "SPECIAL MATCH RULES ARE IN EFFECT!" message sequence —
one line per effect.

Works automatically with `match_format: "best_of_3"` (games 2 and 3 reload the
scene and re-read the JSON) and alongside `restrictions`.

### 2.1 Syntax

`match_effects` is an **array of effect objects**, sibling of `restrictions`
on the opponent entry. Multiple effects stack in one battle.

```jsonc
{
  "name": "Gym Leader Blaine",
  // ... other opponent fields ...
  "restrictions":  { "allowed_pokemon_types": ["Fire"] },   // optional, §1
  "match_effects": [
    { "type": "type_damage_bonus", "pokemon_type": "Fire", "amount": 20 },
    { "type": "no_retreat", "applies_to": "player" },
    { "type": "coin_flip_override", "result": "heads" }
  ]
}
```

Every effect object has:

| Field | Required | Notes |
|---|---|---|
| `type` | yes | One of the effect types in §2.2. Unknown types print a warning and are ignored. |
| `applies_to` | no | `"both"` (default) \| `"player"` \| `"opponent"`. `"player"` = the human, `"opponent"` = the CPU. For offensive effects it selects whose **attacks/actions** are affected; for defensive effects (`type_damage_reduction`, `no_status_effects`, `max_hp_modifier`, `end_of_turn_heal`, `no_healing`, `healing_multiplier`) it selects whose **Pokémon** are affected. |
| *(params)* | varies | Per-type parameters listed below. |

**Stacking rules:** additive effects (damage bonuses, reductions, heals,
modifiers) stack if listed twice. Override-style effects
(`coin_flip_override`, `draw_count`, `opening_hand_size`, `bench_size_limit`,
`trainer_discard_cost`, `extra_energy_per_turn`) — the **last matching entry
in the array wins**.

### 2.2 Effect type reference

#### Damage rules

| `type` | Params | What it does |
|---|---|---|
| `type_damage_bonus` | `pokemon_type`, `amount` | Pokémon of that type deal +X attack damage (e.g. all Fire +20). Stacks. |
| `evolved_damage_bonus` | `amount` | All evolved (non-Basic) Pokémon deal +X attack damage. |
| `stage_damage_bonus` | `basic`, `stage1`, `stage2` (each optional) | Per-stage flat attack bonus, e.g. Stage 1 +10, Stage 2 +20. |
| `type_damage_reduction` | `pokemon_type`, `amount` | Damage dealt **to** Pokémon of that type is reduced by X (e.g. Grass take 20 less). |
| `ignore_weakness` | — | Weakness is skipped in damage calculation. |
| `ignore_resistance` | — | Resistance is skipped in damage calculation. |
| `ignore_weakness_and_resistance` | — | Both skipped (same as listing the two above). |
| `zero_attack_damage` | — | All raw attack damage becomes 0. Attack effects still happen. Applied **last** — wins over every bonus. |
| `raw_damage_only` | — | Attacks lose their effects and only do printed damage. Variable attacks are flattened with **no coin flips**: a `20×` attack just does 20, a `10+` attack does 10. |

Damage rules only affect **attack** damage. Self-damage, recoil, bench splash
and poison ticks are untouched (poison has its own effect below).

#### Turn flow & resources

| `type` | Params | What it does |
|---|---|---|
| `draw_count` | `count` | Draw N cards instead of 1 at the start of each turn. |
| `opening_hand_size` | `count` | Opening hands are N cards instead of 7 (mulligan rules unchanged). |
| `extra_energy_per_turn` | `count` | Players may attach N energy cards per turn instead of 1. |
| `trainer_discard_cost` | `count` | To play a Trainer you must first discard N **other** cards from your hand (CPU pays too, and demands more value before playing trainers). |
| `bench_size_limit` | `size` | Maximum bench size (combines with Narrow Gym — the lower cap wins). |
| `double_prizes` | — | Every knockout awards 2 prize cards instead of 1 (bench tokens still award none). |

#### Retreat rules

| `type` | Params | What it does |
|---|---|---|
| `no_retreat` | — | Retreating is blocked entirely. Beats `free_retreat` if both present. |
| `free_retreat` | — | Retreating costs no energy. |
| `retreat_cost_modifier` | `amount` (can be negative) | Added to every retreat cost, floored at 0 (e.g. +1 = everything pays one more). |

#### Healing rules

| `type` | Params | What it does |
|---|---|---|
| `no_healing` | — | All healing is blocked — potions, powers, berries, attack heals, and the attach/evolve heal effects below. **Beats every other healing effect.** Berries are not consumed while blocked. |
| `healing_multiplier` | `multiplier` | All healing is scaled (2 = doubled). |
| `end_of_turn_heal` | `amount` | Every Pokémon in play (active + bench, both sides unless `applies_to`) heals X HP between turns. |
| `energy_attach_full_heal` | — | Attaching an energy card from hand fully heals that Pokémon. |
| `energy_attach_halve_hp` | — | Attaching an energy card from hand halves that Pokémon's current HP (rounded up to the nearest 10, never below 10 — 50 → 30). |
| `evolve_full_heal` | — | Evolving fully heals the Pokémon. |

Damage-counter **transfer** powers (Damage Swap etc.) are not "healing" and
ignore these rules.

#### Status & powers

| `type` | Params | What it does |
|---|---|---|
| `no_status_effects` | — | Poison / Toxic / Burn / Sleep / Confusion / Paralysis cannot be applied. |
| `poison_damage_multiplier` | `multiplier` | The between-turns poison tick is scaled (2 = doubled). |
| `powers_blocked` | — | All Pokémon Powers and Poké-Bodies stop working (rides the same gate as Muk's Toxic Gas). `applies_to` is ignored — always both sides. |

#### Coins, energy & HP

| `type` | Params | What it does |
|---|---|---|
| `coin_flip_override` | `result`: `"heads"` \| `"tails"` | Every coin flip is forced to that result (animation still plays). Disables Sabrina's ESP re-flip. |
| `rainbow_energy` | — | Every attached energy counts as **any** type. Double Colorless still provides 2 units. |
| `max_hp_modifier` | `amount` (can be negative) | Every Pokémon's max HP is shifted by ±X for the whole game, floored at 10. Cards start play at the shifted max. |

### 2.3 Examples

```jsonc
// Symmetric pair of simple rules
"match_effects": [
  { "type": "draw_count", "count": 2 },
  { "type": "double_prizes" }
]

// One-sided handicap battle: only the PLAYER cannot retreat,
// and only the OPPONENT's Pokémon heal at end of turn
"match_effects": [
  { "type": "no_retreat",       "applies_to": "player" },
  { "type": "end_of_turn_heal", "amount": 10, "applies_to": "opponent" }
]

// Full gauntlet: best-of-3 + deck restriction + several effects at once
{
  "name": "Arena Master",
  "match_format": "best_of_3",
  "restrictions":  { "banned_card_names": ["Bill"] },
  "match_effects": [
    { "type": "type_damage_bonus", "pokemon_type": "Fire", "amount": 10 },
    { "type": "no_retreat", "applies_to": "player" },
    { "type": "coin_flip_override", "result": "heads" }
  ]
}
```

### 2.4 Testing day

`NPC_and_Opponent_Data/Celeste_Harbour_0_Day.json` is a dedicated test day with
**one opponent per effect** (33 total) lined up in Celeste Harbour, plus a
best-of-3 combo opponent. Reach it with the **`[`** debug key (sets date 0).
They all use the `Match Effect Test` deck and announce their rule as their
greeting text.

### 2.5 Known limitations

- CPU attack **scoring** ignores attacker-side damage bonuses and
  `zero_attack_damage` — the AI still picks attacks normally under those rules.
- `max_hp_modifier` conflicts with the two cards that manage their own HP
  override: Koga's Ditto (Giant Growth) and Sabrina's Gastly (Gaseous Form).
- Under `trainer_discard_cost`, the cost is paid even if Mind Games or Chaos
  Gym subsequently wastes the trainer.

---

## 3. NPC & Opponent Spawning Conditions

Any NPC or opponent entry may carry a `condition` block. The entry only spawns
if the condition evaluates to **true**.

**Evaluator:** `MapManager._evaluate_condition` (MapManager.gd ≈ line 311)
**Special case:** During the immediate return-to-map after a battle, a
just-beaten opponent stays spawned long enough to play the result text, even
if their `opponent_not_defeated` condition would normally hide them now.

### 3.1 Condition types

| `type` | Extra fields | Returns true when |
|---|---|---|
| `opponent_defeated` | `target: String` | The named opponent has been beaten at least once |
| `opponent_not_defeated` | `target: String` | The named opponent has NOT been beaten |
| `all_opponents_defeated` | `targets: String[]` | Every name in the list has been beaten |
| `not_all_opponents_defeated` | `targets: String[]` | At least one name in the list has NOT been beaten |
| `any_opponent_defeated` | `targets: String[]` | At least one name in the list has been beaten |
| `npc_met` | `target: String` | The named NPC has been talked to at least once |
| `npc_not_met` | `target: String` | The named NPC has NOT been talked to |
| `flag_set` | `flag: String` | `GameState.progress[flag]` is truthy |
| `flag_not_set` | `flag: String` | `GameState.progress[flag]` is falsy or missing |

### 3.2 Examples

```jsonc
// Spawn only after Misty has been beaten
"condition": { "type": "opponent_defeated", "target": "Gym Leader Misty" }

// Spawn until the player completes ALL six Pikachu Fans
"condition": {
  "type": "not_all_opponents_defeated",
  "targets": [
    "Pikachu Fan Marina", "Pikachu Fan Skye",
    "Pikachu Fan Cami",   "Pikachu Fan Juniper",
    "Pikachu Fan Raye",   "Pikachu Fan Leaf"
  ]
}

// Spawn after a custom progress flag has been set elsewhere
"condition": { "type": "flag_set", "flag": "got_starter_deck" }
```

---

## 4. Movement Patterns

`pattern` controls how a spawned NPC or opponent moves around the map.
The default is `"idle_random"`.

**Implementation:**
- `Scripts/Objects_And_Classes/Opponent_Object_Script.gd`
- `Scripts/Objects_And_Classes/NPC_Object_Script.gd`
- `Scripts/Objects_And_Classes/Shopkeeper_Script.gd`

### 4.1 Pattern values

| Pattern | Behaviour | Extra fields |
|---|---|---|
| `idle_random` | Stands still, randomly turns to face a new direction every 1–4 s | — |
| `idle_cycle` | Stands still but cycles the `walk_down` animation (used for swimmers) | — |
| `idle_up` / `idle_down` / `idle_left` / `idle_right` | Stationary facing the given direction; restored 1 s after a conversation | — |
| `patrol_line` | Walks back and forth along one axis | `patrol_speed` (default `60`), `patrol_distance` (default `100`), `patrol_axis` (`"horizontal"` or `"vertical"`) |
| `patrol_square` | Walks a square loop (down → right → up → left → repeat) | `patrol_speed`, `patrol_distance` |
| `random_wander` | Picks short random walks within a radius of the spawn point | `patrol_speed`, `wander_radius` (default `200`) |

### 4.2 Extra-field reference

| Field | Type | Default | Used by |
|---|---|---|---|
| `patrol_speed` | float | `60.0` | `patrol_line`, `patrol_square`, `random_wander` |
| `patrol_distance` | float | `100.0` | `patrol_line`, `patrol_square` |
| `patrol_axis` | `"horizontal"` \| `"vertical"` | `"horizontal"` | `patrol_line` |
| `wander_radius` | float | `200.0` | `random_wander` |

### 4.3 Examples

```jsonc
{ "name": "Biker2", "pattern": "patrol_line", "patrol_speed": 120,
  "patrol_distance": 210, "patrol_axis": "horizontal",
  "position": { "x": 400, "y": 1050 } }

{ "name": "Pikachu Fan Marina", "pattern": "random_wander",
  "patrol_speed": 20, "wander_radius": 65,
  "position": { "x": 1425, "y": 1000 } }

{ "name": "Fisherman Dave", "pattern": "idle_down",
  "position": { "x": -600, "y": 2730 } }
```

---

## 5. NPC Types

`npc_type` decides which behaviour script handles the NPC and which scene is
instantiated. Set on the NPC's entry in `All_NPC_Constant_Data.json` (or on
the per-map placement if it varies by location).

**Dispatcher:** `MapManager._load_and_spawn_npcs` (≈ line 280) and
`MapManager._on_player_npc_interact` (≈ line 553).

| `npc_type` | Behaviour | Required extra fields |
|---|---|---|
| (omitted) / `"text_only"` | Plain NPC — shows `meet_text` then `repeat_text`. Optionally a gift NPC if `gift_type` is set. | — |
| `"juice_vendor"` | Opens the juice-bar coin lottery | — (handled inline in MapManager) |
| `"shop"` | Opens the corresponding shop scene; uses Shopkeeper state machine | `shop_id` |

### 5.1 Shop ids

| `shop_id` | Scene loaded | Notes |
|---|---|---|
| `"card_mart"` | `Scenes/Main_Menu_Scenes/Pack_Purchase.tscn` | Standard pack shop; uses Day-1 starter-set state machine |
| `"rocket_mart"` | `Scenes/Main_Menu_Scenes/Pack_Purchase.tscn` | Forces `unlocked_packs = ["base5"]` |
| `"coin_mart"` | `Scenes/Main_Menu_Scenes/Coin_Shop.tscn` | Reads `coin_shop_inventory.json` |
| `"holo_mart"` | `Scenes/Main_Menu_Scenes/Holo_Rare_Shop.tscn` | — |

### 5.2 Example shop NPC

```jsonc
"Holo Rare Shopkeeper": {
  "sprite":   "NPC_Holo_Rare_Shopkeeper",
  "npc_type": "shop",
  "shop_id":  "holo_mart"
}
```

---

## 6. Gifts (NPC-given)

A non-shop NPC becomes a **gift NPC** as soon as `gift_type` is non-empty.
The gift is awarded the first time the player talks to them, then the NPC
falls back to its `repeat_text` from then on.

**Handler:** `MapManager._give_gift` (line 619) and
`MapManager._prepare_gift_display` (line 666).
**Detection:** `NPC_Object_Script.is_gift_npc()`.

### 6.1 Gift types

| `gift_type` | `gift_value` format | What it does | Visual reveal |
|---|---|---|---|
| `"card"` | Comma-separated card ids, e.g. `"base1-1, base2-5"` | Adds cards to the player's collection via `GameState.give_cards` | Card-flip animation |
| `"cash"` | Decimal string, e.g. `"250"` | `GameState.add_cash(int(value))` | Silent |
| `"coin"` | Coin filename without `.png`, e.g. `"Pikachu Gold"` | `GameState.add_coin_to_collection(value)` | Coin-flip animation |
| `"costume"` | Costume key (case variants tolerated), e.g. `"Sailor"`, `"LASS2"` | `GameState.add_costume_to_collection(value)` | Fade-in costume image |
| `"energy_style"` | Style name, e.g. `"Base1"` | Appends to `progress["energy_styles"]` | Silent |
| `"available_pack"` | Single pack id, e.g. `"base4"` | Appends to `progress["packs_unlocked"]` — unlocks it for purchase in Card Mart | Silent |
| `"pack"` | Comma-separated pack art codes, e.g. `"base5_a, base1_b"` | Queues `PackOpeningManager.open_packs(...)` on the next OK press — opens packs immediately | Pack opening sequence |
| `"pack_of_cards"` | (Pack name) | **Not implemented** — currently emits a `push_warning` | n/a |

### 6.2 Special placeholders seen in data

| Placeholder | Meaning |
|---|---|
| `"REPLACECOIN"` in `gift_value` | Used in early/draft data to mark "fill in a real coin later". Treat as a TODO marker. |
| `"REPLACEMUSIC"` in `music` field | Same idea for opponent BGM. |

### 6.3 Examples

```jsonc
// Card gift (single)
"Kid Opening Packs": { "sprite": "NPC 02", "gift_type": "card", "gift_value": "base1-20" }

// Multi-card gift
"Card Elder Hamish Day 4": { "sprite": "Elder", "gift_type": "card",
  "gift_value": "base1-1, base1-2, base1-3" }

// Cash
"Man Staring Out To Sea": { "sprite": "Youngcouple2_2",
  "gift_type": "cash", "gift_value": "250" }

// Costume
"Sailor Working On Dock": { "sprite": "Sailor",
  "gift_type": "costume", "gift_value": "Sailor" }

// Unlock a pack for sale in the Card Mart
"Card Mart Rep": { "sprite": "NPC 09",
  "gift_type": "available_pack", "gift_value": "base4" }

// Immediately open one or more packs
"Rocket Pack Gift": { "sprite": "Teamrocket_M",
  "gift_type": "pack", "gift_value": "base5_a, base5_b" }
```

### 6.4 Costume-gated NPCs

An NPC carrying a `required_costume` field reacts to **what the player is
currently wearing** (the `sprite` field of `Player_Current_Data.json`).

**Handler:** `MapManager._handle_costume_gated_npc`.

| Field | Notes |
|---|---|
| `required_costume` | Costume sprite name the player must be wearing. Compared case-insensitively. Presence of this field marks the NPC as costume-gated. |
| `costume_match_text` | Greeting shown **while wearing** the required costume. |
| `meet_text` / `repeat_text` | Greeting shown when **not** wearing it (ordinary text NPC behaviour). |
| `gift_type` / `gift_value` | Standard gift fields (§6.1). The gift is handed over **only** while the required costume is worn, and only once. |

While wearing the costume the player gets `costume_match_text` and the gift;
otherwise they get the normal greeting and nothing — they can return later in
the right outfit. Works with every `gift_type` in §6.1.

```jsonc
// Gives a pack of cards, but only to a player dressed as a Rocket grunt
{
  "name": "Rocket Grunt", "sprite": "Teamrocket_M",
  "required_costume": "Teamrocket_M",
  "meet_text": "What are you looking at, kid? Beat it.",
  "repeat_text": "I told you to get lost.",
  "costume_match_text": "Hey, you're one of us! Here, take this pack.",
  "gift_type": "pack", "gift_value": "base1_a"
}
```

---

## 7. Opponent Rewards

Rewards are read after a winning match by `Match_End_Outro_Script.gd` (around
lines 283–327). They live on the opponent's entry in
`All_NPC_Constant_Data.json` (or on the per-map placement to override).

| Field | Format | Awarded | Notes |
|---|---|---|---|
| `cash_reward` | Integer string, e.g. `"150"` | **Every win** | First win is tripled (×3) and the outro label shows `(First Win ×3!)` |
| `coin_reward` | Single coin filename without `.png`, e.g. `"Pikachu Gold"` | **First win only**, and only if the player doesn't already own that coin | Triggers coin-flip animation |
| `card_reward` | Comma-separated card ids, e.g. `"basep-3, basep-14"` | **First win only** | Added via `GameState.give_cards` |
| `costume_reward` | Comma-separated costume keys, e.g. `"Scientist_M, Scientist_F"` | **First win only** | Per key, only added if not already owned |
| `pack_reward` | Single pack art code, e.g. `"base5_c"` | **Not currently consumed** — present on `Rocket Exec Ariana` but no script reads it. Treat as planned/not-wired. |
| `prize_cards` | int (1–6) | — | Number of prize cards in the match itself (not a reward) |
| `music` | string (set id / `"REPLACEMUSIC"`) | — | BGM track played during the battle |
| `deck` | Deck name (string) | — | Looks up `NPC_and_Opponent_Data/Opponent_Deck_Data/<deck>.json` |

> **Are packs allowed as a prize?** Not via `pack_reward` (currently unused).
> If you want a battle to award a pack, the workable mechanism is to award a
> **card** via `card_reward` and trigger pack-opening via a gift NPC elsewhere
> with `gift_type: "pack"`. The `pack_reward` field is reserved for future
> wiring.

### 7.1 Example opponent

```jsonc
"Card Expert Nathan": {
  "sprite":         "Cooltrainer_M3",
  "deck":           "Energy Burn",
  "music":          "REPLACEMUSIC",
  "prize_cards":    6,
  "cash_reward":    "150",
  "coin_reward":    "Charizard Red",
  "card_reward":    "basep-3, basep-14",
  "costume_reward": "Cooltrainer_M3"
}
```

---

## 8. Map Files: Day & Time Variants

Each overworld map loads a different JSON file depending on the current
**date** and **time of day**.

**Loader:** `Scripts/Map_Scripts/Celeste_Harbour.gd` (≈ line 16)
**State source:** `GameState.get_date()` and `GameState.get_time()`.

### 8.1 Filename convention

`NPC_and_Opponent_Data/<Map>_<Date>_<Time>.json`

| Part | Allowed values |
|---|---|
| `<Map>` | `Celeste_Harbour`, `Verdant_Forest`, … (one per overworld scene) |
| `<Date>` | Integer day number — `1`, `2`, `3`, `4`, `5`, … |
| `<Time>` | `Day`, `Evening`, `Night` |

So:

```
NPC_and_Opponent_Data/Celeste_Harbour_1_Day.json
NPC_and_Opponent_Data/Celeste_Harbour_3_Night.json
NPC_and_Opponent_Data/Verdant_Forest_4_Evening.json
```

### 8.2 File top-level shape

```jsonc
{
  "npcs":      [ { ...npc placement... } ],
  "opponents": [ { ...opponent placement... } ]
}
```

Both arrays may carry per-entry `condition` blocks (see §3) to toggle entries
on or off based on progress.

### 8.3 Time cycle

Time advances **Day → Evening → Night → Day** (Day rollover bumps `date`).
Day-driven map events (e.g. boats appearing, beach blocked, SS Anne docking)
are scripted inside the map's `.gd` file rather than the data JSON.

---

## 9. Card Sets, Decks & Player Data

### 9.1 Card data JSON

Each set lives in `Card_Set_Data/<set_id>.json` and is a flat array of card
objects.

```jsonc
{
  "id":         "base1-1",
  "name":       "Alakazam",
  "supertype":  "Pokémon",          // "Pokémon" | "Trainer" | "Energy"
  "subtypes":   ["Stage 2"],         // "Basic", "Stage 1", "Stage 2", "Baby",
                                     // "Special" (energies), "ex"
  "hp":         "80",                // string, only on Pokémon
  "types":      ["Psychic"],         // energy type(s) for Pokémon
  "evolvesFrom":"Kadabra",
  "attacks":    [ ... ],
  "weaknesses": [ { "type": "Psychic", "value": "×2" } ],
  "retreatCost":["Colorless", "Colorless", "Colorless"],
  "convertedRetreatCost": 3,
  "rarity":     "Rare Holo"
}
```

**Card image path:** `res://Image_Assets/Card_Image_Library/<set_id>/Large/<card_id>.png`

### 9.2 Player decks

Player deck files live in `user://Player_Decks/<name>.json` (and starter
seeds in `res://Player_Data/Player_Decks/`). The format is a simple array:

```jsonc
[
  { "count": 15, "id": "base1-101" },
  { "count": 4,  "id": "base1-43" },
  { "count": 2,  "id": "base1-27" }
]
```

| Field | Type | Notes |
|---|---|---|
| `id` | String | Lowercase `set-number` id. Must exist in the matching `Card_Set_Data/<set>.json`. |
| `count` | int | Copies of the card in the deck. No engine-enforced cap; deck-builder UI enforces TCG standard limits. |

The player's **currently-selected deck name** is the `deck` field of
`user://Player_Current_Data.json`.

### 9.3 Player owned cards

`Player_Data/Player_Owned_Cards/<set>_player_owned_cards.json` tracks how many
copies of each card the player owns:

```jsonc
{
  "owned_cards": [
    { "card_id": "base1-1", "owned": 0 },
    { "card_id": "base1-2", "owned": 5 }
  ]
}
```

### 9.4 Opponent decks

Opponent deck files use the same format as player decks and live at
`NPC_and_Opponent_Data/Opponent_Deck_Data/<DeckName>.json`. The opponent's
`deck` field (a string like `"Energy Burn"`) is mapped to the filename.

---

## 10. Pack Pricing

**File:** `Card_Set_Data/pack_prices.json`
**Reader:** `Scripts/Menu_Scripts/Pack_Purchase_Script.gd`

```jsonc
[
  { "pack": "base1", "cost": "100" },
  { "pack": "base5", "cost": "200" },
  { "pack": "neo4",  "cost": "550" }
]
```

| Field | Notes |
|---|---|
| `pack` | Set id (matches `Card_Set_Data/<set>.json`) |
| `cost` | Cash cost, **stored as a string** but parsed to int |

**Pack art codes** (for gifts and rewards) follow `<set_id>_<letter>`,
e.g. `base1_a`, `base1_b`, `base5_c`. Their images live at
`res://Image_Assets/Packs/<art_code>.png`.

---

## 11. Coin Shop Inventory

**File:** `NPC_and_Opponent_Data/coin_shop_inventory.json`
**Reader:** `Scripts/Menu_Scripts/Coin_Shop_Script.gd`
**Currency:** Munchlax coins (Silver / Gold / Blue) won at the juice vendor.

```jsonc
{
  "coins": [
    { "filename": "Arceus Silver.png",       "cost": 300 },
    { "filename": "Gardevoir Silver 2.png",  "cost": 300 }
  ]
}
```

| Field | Notes |
|---|---|
| `filename` | Coin image filename including `.png` (lives in `Image_Assets/Coins/`) |
| `cost` | Coin cost — integer, not string |

---

## 12. Save / Progress Data Shape

Persisted at `user://Player_Game_Progress.json` and accessed only via the
`GameState` autoload (never bypass it — see [[project_gamestate_save_invariant]]).

Key fields you'll see referenced in JSON conditions and gift hooks:

| Progress key | Type | Set by |
|---|---|---|
| `date` | int | Time cycle / sleep flow |
| `time` | `"Day"` \| `"Evening"` \| `"Night"` | Time cycle |
| `cash` | int | `add_cash`, battle rewards |
| `coins` | `String[]` of filenames | `add_coin_to_collection` |
| `costumes` | `String[]` of lowercase `.png` keys | `add_costume_to_collection` |
| `energy_styles` | `String[]` | Gift `energy_style` |
| `packs_unlocked` | `String[]` of set ids | Gift `available_pack` |
| `packs_opened_total` | int | `Pack_Opening_Manager.gd` — gates god-pack unlock (>20) and guarantee (every 100). See [[project_pack_opening_counter]]. |
| `opponents_beaten` | `String[]` | Match outro |
| `npcs_met` | `String[]` | First interaction |
| `gifts_received` | `String[]` of NPC names | `mark_gift_received` |
| `shop_state` | `"initial"` \| `"awaiting_funds"` \| `"restocking"` \| `"open"` | Shopkeeper state machine |
| `player_collected_shop_starter_set` | bool | Day-1 starter purchase |
| `shop_free_packs_given` | bool | Day-2 free pack drop |

Custom `flag_set` / `flag_not_set` conditions read whatever key you point at
in this dict, so feel free to invent new boolean flags as long as something
elsewhere is setting them.

---

## 13. Interactables (Signs, Bed, TV)

Overworld "objects" the player interacts with by pressing **Space** while standing
inside the object's zone.

**Setup:** each map scene has an `Interactables` **Area2D** node whose children are
named `CollisionShape2D` zones (rectangles). The shared script
`Scripts/Map_Scripts/Interactables_Script.gd` is attached to that node.

**Behaviour is chosen by the shape's NAME:**

| Shape name | Behaviour |
|---|---|
| `Bed` | Sleep flow — see §13.2 |
| `TV` | Cycling news headlines — see §13.3 |
| anything else | Plain flavour text from `Interactables_Data.json` — see §13.1 |

### 13.1 Sign flavour text

**File:** `Map_Data/Interactables_Data.json`
**Reader:** `Interactables_Script.gd`

Keyed by **scene name** (the `.tscn` filename without extension), then by the
**shape name**:

```jsonc
{
  "Celeste_Harbour": {
    "Sign_Shop_Bakery": "Fresh hot bread from here!",
    "Sign_Beach_Right_Big": "‹ Magikarp Pond  |  Pikachu Pond ›"
  },
  "Verdant_Forest": { "Sign_North": "Verdant Event Hall ahead." }
}
```

A shape with no matching entry shows a generic fallback line. `Bed` / `TV`
shapes are handled in code and need no entry.

### 13.2 Bed

| Time of day | Result |
|---|---|
| `Day` / `Evening` | Message: *"…it's far too early to go to sleep now!"* |
| `Night` | Yes/No prompt *"Would you like to go to sleep now?"* |

Choosing **Yes** at night: fades to black over `SLEEP_FADE_DURATION` (3.0s),
remembers the player's position, advances **`date` +1** and **`Night → Day`**
(via `GameState.advance_time`), then reloads the scene fresh.

### 13.3 TV news

The TV picks the **highest progression stage** whose condition is currently met,
then cycles through that stage's headlines on each press. Conditions are checked
top-down in `_tv_stage()`:

| Stage | Condition | Theme |
|---|---|---|
| 5 | `date >= 4` | Verdant Forest open |
| 4 | `date >= 3` | SS Anne arrived |
| 3 | `base2` or `base3` in `packs_unlocked` | New sets in store |
| 2 | `shop_state == "open"` | Card mart selling packs |
| 1 | (default) | Game start |

Headline text lives in the `TV_NEWS` constant in `Interactables_Script.gd`.

### 13.4 Adding a new interactable

1. Add a named `CollisionShape2D` under the scene's `Interactables` node.
2. **Plain text:** add an entry under that scene's key in `Interactables_Data.json`.
3. **Custom behaviour:** add a `case` for the shape name in `_trigger()`.

---

## 14. Cheat Codes

Enter the code **exactly** as shown as your player name on the name-entry screen. The cheat is applied immediately and the game returns you to the normal name prompt. Codes are case-sensitive and must not have leading/trailing spaces.

**Implementation:** `Scripts/Global_Scripts/Cheat_Manager.gd`

| Code | Effect | Sets affected |
|---|---|---|
| `CHT.All_Cards_1` | Set every card in Base/Gym sets to **99 copies** | `base1`, `base2`, `base3`, `base5`, `gym1`, `gym2` |
| `CHT.All_Cards_2` | Set every card in Neo/e-Card sets to **99 copies** | `neo1`, `neo2`, `neo3`, `neo4`, `ecard1`, `ecard2`, `ecard3` |
| `CHT.All_Cards_3` | Set every card in EX Series 1 sets to **99 copies** | `ex1`–`ex8` |
| `CHT.All_Cards_4` | Set every card in EX Series 2 sets to **99 copies** | `ex9`–`ex16` |
| `CHT.Gimme_Cash` | Set cash to **99,999** | — |
| `CHT.Add_Starter_Set` | Add the starter-box card bundle to the collection | — |
| `CHT.Add_Shop_Set` | Add the shop starter card bundle to the collection | — |
| `CHT.Remove_All_Cards` | Set **all** owned card counts to 0 across every set | all sets |

> `CHT.All_Cards_*` also marks each affected set as `set_unlocked: true` in the owned-cards file. `CHT.Remove_All_Cards` zeroes counts but does **not** clear `set_unlocked`.

---

## 15. Quick-Reference Cheat Sheet

| I want to… | Edit this |
|---|---|
| Make an opponent require a specific deck | Add `restrictions: { … }` to their entry (§1) |
| Give a battle special rules (damage boosts, no retreat, forced flips…) | Add `match_effects: [ … ]` to the opponent entry (§2) |
| Hide an opponent until a prerequisite is beaten | Add `condition: { type: "opponent_defeated", target: "…" }` (§3) |
| Change how an NPC moves around | Set `pattern` plus the matching extra fields (§4) |
| Add a new shop NPC | `npc_type: "shop"` plus the correct `shop_id` (§5) |
| Give the player a card / costume / cash | `gift_type` + `gift_value` on the NPC (§6) |
| Make an NPC react to what costume the player wears | `required_costume` + `costume_match_text` (§6.4) |
| Reward an opponent battle with cash + cards | `cash_reward` + `card_reward` (§7) |
| Add a new map-day/time variant | Create `<Map>_<Day>_<Time>.json` (§8) |
| Add a new card to a set | Append to `Card_Set_Data/<set>.json` (§9.1) |
| Change a pack's price | Edit `Card_Set_Data/pack_prices.json` (§10) |
| Add a coin to the Coin Shop | Append to `coin_shop_inventory.json` (§11) |
| Change a sign's flavour text | Edit `Map_Data/Interactables_Data.json` (§13.1) |
| Add a new sign / object interaction | New `CollisionShape2D` under `Interactables` (§13.4) |

---

*Last updated: 2026-06-29*
