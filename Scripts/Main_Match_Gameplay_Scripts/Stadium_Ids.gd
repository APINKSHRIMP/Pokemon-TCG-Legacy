class_name StadiumIds
extends RefCounted

######################################################################################################################################################
####################################################### STADIUM CARD IDs ############################################################################
######################################################################################################################################################
#
# Named constants for all stadium card UIDs used in game logic.
# Use these everywhere instead of raw string literals so a rename is one-line.
# Access as StadiumIds.CONSTANT_NAME (class_name makes these globally available).
#

# ── Gym Heroes (gym1) ─────────────────────────────────────────────────────────
const NO_REMOVAL_GYM      = "gym1-103"  # Energy Removal/Super Energy Removal require 2 extra cards
const ROCKETS_TRAINING_GYM = "gym1-104" # Rocket's Pokemon get +10 HP while in play
const CELADON_CITY_GYM    = "gym1-107"  # Erika's Pokemon power: discard Energy to cure status
const CERULEAN_CITY_GYM   = "gym1-108"  # Misty's Water Pokemon get reduced retreat cost
const PEWTER_CITY_GYM     = "gym1-115"  # Brock's Fighting Pokemon deal +10 damage
const VERMILION_CITY_GYM  = "gym1-120"  # Surge's Lightning Pokemon: attach extra Energy
const NARROW_GYM          = "gym1-124"  # Bench is limited to 3 pokemon each side

# ── Gym Challenge (gym2) ──────────────────────────────────────────────────────
const CHAOS_GYM           = "gym2-102"  # Trainer cards require a coin flip to work
const RESISTANCE_GYM      = "gym2-109"  # All Resistance is reduced by 20
const CINNABAR_CITY_GYM   = "gym2-113"  # Blaine's Pokemon deal +10 damage
const FUCHSIA_CITY_GYM    = "gym2-114"  # Koga's Pokemon: flip to shuffle back into deck
const ROCKETS_MINEFIELD_GYM = "gym2-119" # Bench damage when playing Trainer cards
const SAFFRON_CITY_GYM    = "gym2-122"  # Sabrina's Pokemon: return basic Energy to hand
const VIRIDIAN_CITY_GYM   = "gym2-123"  # Giovanni's Pokemon can evolve on the first turn

# ── Base Set Promos (basep) ────────────────────────────────────────────────────
const LUCKY_STADIUM    = "basep-41"  # Once per turn each player flips — heads draws 1 card
const POKEMON_TOWER    = "basep-42"  # Prevents cards from being recovered from the discard pile

# ── Neo Genesis (neo1) ────────────────────────────────────────────────────────
const ECOGYM           = "neo1-84"   # Opponent-discarded non-Colorless energy returns to owner's hand
const SPROUT_TOWER     = "neo1-97"   # Colorless Pokémon attacks deal -30 damage

# ── Neo Revelation (neo3) ─────────────────────────────────────────────────────
const HEALING_FIELD    = "neo3-61"   # Once per turn each player may flip — heads remove 2 damage counters from Active
const ROCKETS_HIDEOUT  = "neo3-63"   # Pokemon with "Dark" in name get +20 HP

# ── Neo Destiny (neo4) ────────────────────────────────────────────────────────
const BROKEN_GROUND_GYM = "neo4-92"  # Each player pays Colorless more to retreat a Baby/Basic Pokemon
const RADIO_TOWER       = "neo4-95"  # Once per turn each player may look at top 2 of deck, put back same order
const ENERGY_STADIUM    = "neo4-99"  # Once per turn each player may flip — heads basic Energy from discard to hand
const NEO4_LUCKY_STADIUM = "neo4-100" # Once per turn each player may flip — heads draw a card

# ── Nintendo Promos (np) ───────────────────────────────────────────────────────
const CHAMPIONSHIP_ARENA  = "np-28"   # At end of each player's turn, if 8+ cards in hand discard to 7
