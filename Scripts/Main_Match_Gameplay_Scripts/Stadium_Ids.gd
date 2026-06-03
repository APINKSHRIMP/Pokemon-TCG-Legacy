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
