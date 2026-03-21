class_name card_object

# The card's unique identifier (e.g., "Base1-1")
var uid: String

# The card's metadata from JSON
var metadata: Dictionary

# attached cards tracking
var attached_energies: Array = []
var attached_pre_evolutions: Array = []
var attached_cards: Array = [] # This is a generic catch all for tools, special cards, attached pokemon etc

# Tracks the location of the card in player/opponents control.
var current_location: String = "deck"  # "hand", "deck", "bench", "discard", etc.

# Tracks whether this pokemon was placed on the field during the current turn
var placed_on_field_this_turn: bool = false

# self metadata addition to track hp damage
var current_hp: int = 0

# Status condition tracking
var special_condition: String = ""
var is_poisoned: bool = false
var poison_damage: int = 10
var is_burned: bool = false
var is_blind: bool = false
var has_no_damage: bool = false
var is_invincible: bool = false
var has_destiny_bond: bool = false

# Attack disable tracking: { "attack_name": "entire_game" | "while_in_play" | "end_of_turn" }
var disabled_attacks: Dictionary = {}

# Damage threshold shield (Onix Harden / Mr. Mime Invisible Wall)
# If > 0, damage AT OR BELOW this value is prevented entirely
var shielded_damage_threshold: int = 0

# Porygon Conversion temporary type overrides (reset when leaving play)
var temporary_weakness: String = ""   # Overrides weakness type if set
var temporary_resistance: String = "" # Overrides resistance type if set

# Bench token trainer flags (Clefairy Doll, Mysterious Fossil, etc.)
var no_prize_on_ko: bool = false       # If true, opponent does NOT take a prize card when this is KO'd
var is_bench_token: bool = false       # If true, this card is a bench token trainer (cannot retreat, no status)

# Pokemon Power tracking
var power_used_this_turn: bool = false # For once-per-turn power restrictions

# Attached Trainer card tracking (PlusPower, Defender)
var defender_turns_remaining: int = -1 # Countdown for Defender discard (-1 = not active)
var pluspower_count: int = 0           # Number of PlusPower cards attached (stacking)

# Electrode Buzzap: track if this card is an Electrode-as-Energy token
var is_electrode_energy: bool = false
var electrode_energy_type: String = "" # The chosen energy type for Buzzap

# Utility: get damage counters (each counter = 10 damage)
func get_damage_counters() -> int:
	var max_hp = int(metadata.get("hp", "0"))
	if max_hp <= 0:
		return 0
	return (max_hp - current_hp) / 10

# Utility: get max HP from metadata
func get_max_hp() -> int:
	return int(metadata.get("hp", "0"))

# Constructor - initialize the card with a UID and load its metadata
func _init(card_uid: String, card_metadata: Dictionary) -> void:
	uid = card_uid
	metadata = card_metadata
	
	# Initialize current HP to max HP (from metadata)
	if metadata.has("hp"):
		current_hp = int(metadata["hp"])
	else:
		current_hp = 0
