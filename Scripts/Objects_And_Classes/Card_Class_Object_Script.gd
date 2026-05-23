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

# Scyther Swords Dance: if true, Slash does 60 instead of 30 next turn
var swords_dance_active: bool = false

# Minimize / Pounce / Snivel: reduce incoming damage by this amount next turn
var damage_reduction_next_turn: int = 0

# Tail Wag / Leer: if true, the defending pokemon can't attack this pokemon next turn
# Benching either pokemon ends the effect
var attack_blocked_next_turn: bool = false
var attack_blocked_by_id: int = -1  # instance_id of the pokemon that set the block

# Venomoth Shift: temporary type override (persists until changed or leaves play)
var temporary_type: String = ""

# Ditto Transform: stores original data so Transform can be reverted cleanly
var is_ditto_transformed: bool = false
var ditto_original_uid: String = ""          # Ditto's real UID (for image restore)
var ditto_original_metadata: Dictionary = {} # Ditto's real metadata (full backup)
var ditto_transform_uid: String = ""         # UID of the copied card (for image display)

# Trainer lock tracking (Psyduck Headache) — NOT per-pokemon, tracked on Trainer_Effects.gd

# BASE5 (Team Rocket) properties
var mirror_shell_active: bool = false                    # Dark Wartortle Mirror Shell counter-attack
var power_disabled_until_end_of_next_turn: bool = false  # Dark Arbok Stare power disable

# GYM1 (Gym Heroes) properties
var counter_attack_double: bool = false   # Rocket's Hitmonchan Crosscounter — coin flip, heads = counter double the damage taken
var counter_attack_fixed: int = 0         # Rocket's Moltres Fire Wall — counter this much damage when attacked
var dodge_active: bool = false            # Rocket's Scyther Shadow Images — attacker flips, tails = no damage; lasts until damage gets through
var damage_halved_next_turn: bool = false # Erika's Exeggcute Deflector — incoming damage halved (round down to nearest 10) next turn
var focus_energy_active: bool = false     # Lt. Surge's Rattata Focus Energy — Gnaw base damage doubled next turn

# GYM2 (Gym Challenge) properties
var gym2_focus_energy_active: bool = false # Lt. Surge's Raticate/Rattata Focus Energy — boosted attack doubled next turn
var gym2_lie_low_counter: int = 0          # Brock's Dugtrio Lie Low — Earthdrill is usable while this is > 0
var ditto_giant_growth: bool = false       # Koga's Ditto Giant Growth — max HP 80, Pound base damage 30
var max_hp_override: int = 0               # If > 0, overrides the metadata HP value (Koga's Ditto Giant Growth)

# GYM1 (Gym Heroes) Trainer attachments / per-turn buffs
var gym1_charity_attached: bool = false       # gym1-99 Charity — outgoing damage may be reduced this turn; returns to hand at end of turn if not KO'd
var gym1_sabrina_esp_attached: bool = false   # gym1-117 Sabrina's ESP — first coin-flip in attack auto re-flips on tails; discarded at end of turn
var gym1_sabrina_esp_credit_active: bool = false  # one-shot re-flip credit; cleared on use, refreshed when ESP is freshly attached
var gym1_recall_active: bool = false          # gym1-116 Recall — Active may use any attack from its Basic / Evolution chain this turn

# Utility: get damage counters (each counter = 10 damage)
func get_damage_counters() -> int:
	var max_hp = get_max_hp()
	if max_hp <= 0:
		return 0
	return (max_hp - current_hp) / 10

# Utility: get max HP (metadata HP, unless temporarily overridden)
func get_max_hp() -> int:
	if max_hp_override > 0:
		return max_hp_override
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

# Ditto Transform: copy another card's metadata while preserving Ditto's identity
func apply_ditto_transform(target_metadata: Dictionary, target_uid: String) -> void:
	if is_ditto_transformed:
		revert_ditto_transform()
	
	# Back up originals
	ditto_original_uid = uid
	ditto_original_metadata = metadata.duplicate(true)
	is_ditto_transformed = true
	ditto_transform_uid = target_uid
	
	# Build the cloned metadata: copy everything from target BUT keep Ditto's abilities
	var cloned = target_metadata.duplicate(true)
	
	# Preserve Ditto's Transform ability so it always shows in the power list
	var ditto_abilities = ditto_original_metadata.get("abilities", [])
	cloned["abilities"] = ditto_abilities
	
	# Ditto can't evolve — strip evolution fields
	cloned.erase("evolvesFrom")
	cloned.erase("evolvesTo")
	
	# Overwrite metadata with the clone
	metadata = cloned
	
	# Override the display UID so textures load the copied card's image
	uid = target_uid
	
	# Adjust HP: Ditto takes on the target's max HP but carries over damage
	var old_max = int(ditto_original_metadata.get("hp", "0"))
	var damage_taken = old_max - current_hp
	var new_max = int(cloned.get("hp", "0"))
	current_hp = max(1, new_max - damage_taken)

# Ditto Transform: revert to original Ditto card data
func revert_ditto_transform() -> void:
	if not is_ditto_transformed:
		return
	
	# Calculate damage to carry back
	var clone_max = int(metadata.get("hp", "0"))
	var damage_taken = clone_max - current_hp
	
	# Restore originals
	uid = ditto_original_uid
	metadata = ditto_original_metadata.duplicate(true)
	is_ditto_transformed = false
	ditto_transform_uid = ""
	
	# Carry damage back to Ditto's original HP pool
	var ditto_max = int(metadata.get("hp", "0"))
	current_hp = max(0, ditto_max - damage_taken)
	
	# Clear the backups
	ditto_original_uid = ""
	ditto_original_metadata = {}
