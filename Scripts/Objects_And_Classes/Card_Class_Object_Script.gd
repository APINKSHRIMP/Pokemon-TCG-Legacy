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

# BASEP (Base Set Promos) properties
var lightning_rod_marked: bool = false   # basep-46 Electabuzz Lightning Rod — takes 20 bonus damage from Lightning Bolt

# NEO1 (Neo Genesis) properties
var screech_damage_bonus: int = 0      # neo1-31/69 Screech: +20 damage from next attack received this turn
var has_char_counter: bool = false     # neo1-47 Quilava Char: each turn owner flips; tails = 20 damage
var endure_active: bool = false        # neo1-43 Phanpy Endure: survive KO at 10 HP one time
var jaw_clamp_locked: bool = false     # neo1-31 Croconaw Jaw Clamp: target can't retreat next turn

# NEO2 (Neo Discovery) properties
var lock_on_active: bool = false           # neo2-7/26 Magnemite: next Electric Bolt treats tails as heads
var counter_active: bool = false           # neo2-16/35 Wobbuffet: if damaged, flip for equal counter-damage
var pursuit_active: bool = false           # neo2-32 Umbreon: retreating opponent takes 10 damage
var secrete_poison_active: bool = false    # neo2-41 Kakuna: if hit, attacker poisoned + 10 to each opp bench
var slime_active: bool = false             # neo2-71 Wooper: attacker flips before damaging, tails = no damage
var gaze_suppressed: bool = false          # neo2-40 Igglybuff Gaze: this pokemon's power is suppressed this turn

# NEO3 (Neo Revelation) properties
var night_eyes_used: bool = false          # neo3-11 Misdreavus Night Eyes: set on defender; Perish Song checks this
var triggered_poison_active: bool = false  # neo3-4 Crobat Triggered Poison: if opp attaches energy to this, it becomes Poisoned
var neo3_high_speed_locked: bool = false   # neo3-36 Piloswine High-Speed Charge: can't use next turn
var submerge_active: bool = false          # neo3-32 Lanturn Submerge: type is Water this turn
var legendary_body_active: bool = false    # neo3-17/22/27 Legendary Body: while Active, trainer effects ignored

# NEO4 (Neo Destiny) properties
var neo4_immune_to_status: bool = false        # neo4-24 Light Ledian Flash Touch: can't be statused while Active
var neo4_prevent_high_damage: int = 0          # neo4-48 Light Jolteon Pulse Guard: prevent incoming damage >= this value next turn
var neo4_prevent_bench_damage: bool = false    # neo4-45 Light Dewgong Ice Pillar: prevent attack damage to your benched next turn
var neo4_counter_flip_20: bool = false         # neo4-109 Shining Mewtwo Reflect Shield: flip to prevent damage + 20 to attacker
var neo4_cant_evolve_next_turn: bool = false   # neo4-19 Dark Omastar Dark Tentacle: defender can't evolve next turn
var perform_damage_stored: int = 0             # neo4-58 Unown [P] [Perform]: damage received while Active last opponent turn

# GYM2 (Gym Challenge) properties
var gym2_focus_energy_active: bool = false # Lt. Surge's Raticate/Rattata Focus Energy — boosted attack doubled next turn
var gym2_lie_low_counter: int = 0          # Brock's Dugtrio Lie Low — Earthdrill is usable while this is > 0
var ditto_giant_growth: bool = false       # Koga's Ditto Giant Growth — max HP 80, Pound base damage 30
var max_hp_override: int = 0               # If > 0, overrides the metadata HP value (Koga's Ditto Giant Growth)
var gym2_mega_burn_locked: bool = false    # Sabrina's Alakazam Mega Burn — can't use this attack next turn

# Coin-flip attack block (Sand-attack, Smokescreen, Lightning Flash, Sandstorm, Mirage)
# When set, the pokemon must flip before attacking: tails = attack fails
var attack_flip_blocked: bool = false      # If true, this pokemon must flip before attacking next turn

# GYM1 (Gym Heroes) Trainer attachments / per-turn buffs
var gym1_charity_attached: bool = false       # gym1-99 Charity — outgoing damage may be reduced this turn; returns to hand at end of turn if not KO'd
var gym1_sabrina_esp_attached: bool = false   # gym1-117 Sabrina's ESP — first coin-flip in attack auto re-flips on tails; discarded at end of turn
var gym1_sabrina_esp_credit_active: bool = false  # one-shot re-flip credit; cleared on use, refreshed when ESP is freshly attached
var gym1_recall_active: bool = false          # gym1-116 Recall — Active may use any attack from its Basic / Evolution chain this turn

# GYM2 (Gym Challenge) Trainer attachments / per-turn buffs
var gym2_giovanni_evolve_anywhere: bool = false # gym2-18/104 Giovanni — bypass placed-this-turn / first-turn evolution restrictions; inherited by the evolved form
var gym2_brocks_protection_attached: bool = false # gym2-101 Brock's Protection — attached energies are protected from opp's attacks / Trainer cards
var gym2_koga_ninja_trick_attached: bool = false  # gym2-115 Koga's Ninja Trick — owner may switch this pokemon with a bench pokemon when opponent attacks it; discarded if it leaves Active by any other means

# ── Generic expiring-effects store ─────────────────────────────────────────────
# Replaces one-off per-set boolean flags for temporary effects. Keys are short
# effect-id strings (e.g. "tailwind", "strength_charm_triggered"). Values hold a
# duration tag and optional payload. Durations:
#   "end_of_own_turn"       — cleared when this card's owner's turn ends
#   "end_of_opponent_turn"  — cleared when the other side's turn ends
#   "until_leaves_play"     — cleared only in send_card_to_discard / return-to-hand paths
# New sets must use set_effect/has_effect for temporary per-pokemon state instead
# of adding new one-off booleans here.
var active_effects: Dictionary = {}

func set_effect(effect_id: String, duration: String, data = null) -> void:
	active_effects[effect_id] = {"duration": duration, "data": data}

func has_effect(effect_id: String) -> bool:
	return active_effects.has(effect_id)

func get_effect_data(effect_id: String):
	if not active_effects.has(effect_id):
		return null
	return active_effects[effect_id]["data"]

func clear_effect(effect_id: String) -> void:
	active_effects.erase(effect_id)

func clear_effects_with_duration(duration: String) -> void:
	var to_remove: Array = []
	for k in active_effects:
		if active_effects[k]["duration"] == duration:
			to_remove.append(k)
	for k in to_remove:
		active_effects.erase(k)

func clear_all_expiring_effects() -> void:
	active_effects.clear()

# GYM1 + GYM2 Pokemon Powers / Bodies — per-pokemon state
var shapeshift_form_metadata: Dictionary = {}   # gym2-3 Brock's Ninetales Shapeshift: metadata of the Evolution card attached as a form
var shapeshift_form_uid: String = ""            # uid of the attached form card (for textures + discard reference)
var shapeshift_form_card: card_object = null    # the actual Evolution card object attached (to discard back to pile)

# Returns true if this pokemon has an ability with the given name
func has_ability(ability_name: String) -> bool:
	for ab in metadata.get("abilities", []):
		if ab.get("name", "") == ability_name:
			return true
	return false

# Returns the first ability Dictionary matching the given name, or {} if not found
func get_ability(ability_name: String) -> Dictionary:
	for ab in metadata.get("abilities", []):
		if ab.get("name", "") == ability_name:
			return ab
	return {}

# Returns true if this card is owned by the opponent side
func is_owner_opp(main_ref: Node) -> bool:
	return (self == main_ref.opponent_active_pokemon
		or self in main_ref.opponent_bench
		or self in main_ref.opponent_hand
		or self in main_ref.opponent_deck
		or self in main_ref.opponent_discard_pile
		or self in main_ref.opponent_prize_cards)

# Returns true if a special condition (Asleep/Confused/Paralyzed) is blocking this pokemon's powers or attacks
func is_status_blocked() -> bool:
	return special_condition in ["Paralyzed", "Asleep", "Confused"]

# Utility: get damage counters (each counter = 10 damage)
func get_damage_counters() -> int:
	var max_hp = get_max_hp()
	if max_hp <= 0:
		return 0
	return (max_hp - current_hp) / 10

# ── Per-turn flag resets ───────────────────────────────────────────────────────
# Centralised reset helpers. When adding a new per-turn flag, add the reset here
# so callers don't need updating — only the card_object method needs the new line.

# Clear one-shot attack-boost flags. Call at end of any attack in the generic
# (non-dispatch) path so lingering boosts expire after each turn.
func clear_attack_boost_flags() -> void:
	swords_dance_active = false
	focus_energy_active = false
	gym2_focus_energy_active = false
	# Add future one-shot per-turn attack boosts here.

# Called for all field pokemon at inter-turn (placed_on_field resets each turn for both sides).
func reset_placed_this_turn() -> void:
	placed_on_field_this_turn = false

# Called for all field pokemon belonging to the side whose turn just ended.
func reset_power_used() -> void:
	power_used_this_turn = false

# ── Utility ────────────────────────────────────────────────────────────────────

# Utility: get max HP (metadata HP, unless temporarily overridden)
func get_max_hp() -> int:
	if max_hp_override > 0:
		return max_hp_override
	return int(metadata.get("hp", "0"))

# Returns this Pokemon's current type(s), accounting for temporary overrides:
# Crystal Shard (ecard3-122, permanent while attached) takes priority over Crystal Type
# (ecard2/ecard3 Poké-Body, "crystal_type_active" in the expiring-effects store, until end of
# the holder's own turn). Falls back to the printed metadata type. Use this instead of reading
# metadata.get("types", ...) directly anywhere a Pokemon's OWN current type matters for a
# type-restricted effect (bench-type-splash, retreat-cost-by-type, etc.) — weakness/resistance
# triggering on THIS Pokemon as an attacker is handled centrally in Main's calculate_final_damage.
func get_effective_types() -> Array:
	for ac in attached_cards:
		if ac.uid.to_lower() == "ecard3-122":
			return ["Colorless"]
	if has_effect("crystal_type_active"):
		return [get_effect_data("crystal_type_active")]
	return metadata.get("types", ["Colorless"])

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
