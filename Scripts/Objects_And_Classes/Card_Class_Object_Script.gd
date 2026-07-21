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

# EX11 Holon's Pokémon (Magnemite/Voltorb/Electrode/Magneton): these Pokémon cards may be attached
# from hand as a Special Energy card. When attached_as_energy is true the card lives in a Pokémon's
# attached_energies and provides pokemon_energy_types (e.g. ["Colorless"] or ["Any","Any"]).
var attached_as_energy: bool = false
var pokemon_energy_types: Array = []

# Scyther Swords Dance: if true, Slash does 60 instead of 30 next turn
var swords_dance_active: bool = false
# Swords Dance boosted Slash base damage next turn (0 = use legacy default of 60).
# ex8 Ninjask boosts Slash to 80; base Scyther to 60 — read from the card's own text.
var swords_dance_slash_damage: int = 0

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

# EX3 (EX Dragon) properties
var ex3_buffer_piece_turns: int = 0        # ex3-83 Buffer Piece Tool: end-of-turn counter; discarded after the opponent's turn following play

# EX15 (EX Dragon Frontiers) properties
# Holon Veil (Ampharos δ ex15-1) treats every Basic Pokémon and Evolution card on your side as a
# Pokémon that has δ on its card. refresh_holon_veil() (Powers_And_Bodies_Effects.gd) recomputes this
# flag for every Pokémon in each side's deck/hand/discard/play; is_delta() then reads it.
var granted_delta: bool = false
# Imprison markers (Gardevoir ex δ ex15-93): a Pokémon with any Imprison marker can't use Poké-Powers
# or Poké-Bodies. Shock-wave markers (Tyranitar ex δ ex15-99): a Pokémon with a Shock-wave marker can
# be Knocked Out by Tyranitar ex's Shock-wave attack. Both persist until removed (Tropical Heal) or the
# Pokémon leaves play; stored as until_leaves_play effects so send_card_to_discard clears them.
var imprison_markers: int = 0
var shockwave_markers: int = 0

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
	var hp = int(metadata.get("hp", "0"))
	# ex10 Hitmonchan "Stages of Evolution": +30 HP while it is an Evolved Pokemon (via Baby Evolution).
	if metadata.get("name","") == "Hitmonchan":
		for ab in metadata.get("abilities", []):
			if ab.get("name","") == "Stages of Evolution" and not attached_pre_evolutions.is_empty():
				hp += 30
	# ex10 Energy Root (Pokémon Tool): +20 HP while attached.
	for ac in attached_cards:
		if ac.uid.to_lower() == "ex10-83":
			hp += 20
	return hp

# Returns this Pokemon's current type(s), accounting for temporary overrides:
# Crystal Shard (ecard3-122, permanent while attached) takes priority over Crystal Type
# (ecard2/ecard3 Poké-Body, "crystal_type_active" in the expiring-effects store, until end of
# the holder's own turn). Falls back to the printed metadata type. Use this instead of reading
# metadata.get("types", ...) directly anywhere a Pokemon's OWN current type matters for a
# type-restricted effect (bench-type-splash, retreat-cost-by-type, etc.) — weakness/resistance
# triggering on THIS Pokemon as an attacker is handled centrally in Main's calculate_final_damage.
func get_effective_types() -> Array:
	for ac in attached_cards:
		if ac.uid.to_lower() == "ecard3-122" or ac.uid.to_lower() == "ex8-85" or ac.uid.to_lower() == "ex14-76":
			return ["Colorless"]
	if has_effect("crystal_type_active"):
		return [get_effect_data("crystal_type_active")]
	# ex2 Lunar/Solar Eclipse (Lunatone/Solrock): temporary type override until end of turn.
	if has_effect("ex2_type_override"):
		return [get_effect_data("ex2_type_override")]
	# ISSUE #45 FIX: Venomoth's Shift (and similar temporary_type overrides like Texture Magic) fully
	# change this Pokémon's type until it changes again or leaves play. Routing it through the
	# effective-types path means Weakness/Resistance now actually respect the shifted type (previously
	# the shift changed nothing about damage).
	if temporary_type != "":
		return [temporary_type]
	# ex2 Energy Variation (Kecleon): its type is every type of basic Energy card attached to it.
	# Basic Energy cards carry no "types" field, so the type is read from the card name
	# ("Fire Energy" -> "Fire"), which is how basic Energy provides its type in this data set.
	if has_ability("Energy Variation"):
		var ev_types: Array = []
		for e in attached_energies:
			if "Basic" not in e.metadata.get("subtypes", []):
				continue
			var t = e.metadata.get("name", "").replace(" Energy", "").strip_edges()
			if t != "" and t not in ev_types:
				ev_types.append(t)
		if not ev_types.is_empty():
			return ev_types
		return ["Colorless"]
	# EX12 Reactive Colors (Kecleon ex12-37): while any React Energy is attached, it is Grass, Fire,
	# Water, Lightning, Psychic, and Fighting type.
	if has_ability("Reactive Colors") and react_energy_count() > 0:
		return ["Grass", "Fire", "Water", "Lightning", "Psychic", "Fighting"]
	# EX12 Dual Armor: name-collides with EX7's Dual Armor but changes to a DIFFERENT second type.
	# Lanturn (ex12-19): Water + Lightning while any Water Energy attached. Armaldo ex (ex12-84):
	# Grass + Fighting while any React Energy attached.
	if has_ability("Dual Armor"):
		var nm12 = metadata.get("name", "")
		if nm12 == "Lanturn":
			var lt = metadata.get("types", ["Colorless"]).duplicate()
			if _dual_armor_has_energy("Water") and "Lightning" not in lt:
				lt.append("Lightning")
			return lt
		if nm12 == "Armaldo ex":
			if react_energy_count() > 0:
				return ["Grass", "Fighting"]
			return metadata.get("types", ["Colorless"]).duplicate()
		# EX14 Medicham (ex14-25): Psychic + Fighting while any Psychic Energy is attached.
		if nm12 == "Medicham":
			if _dual_armor_has_energy("Psychic"):
				return ["Psychic", "Fighting"]
			return metadata.get("types", ["Colorless"]).duplicate()
	# EX7 Dual Armor (Rocket's Scizor ex / Rocket's Scyther ex): adds a second type while a specific
	# Energy is attached (Metal for Scizor, Grass for Scyther).
	if has_ability("Dual Armor"):
		var base_types = metadata.get("types", ["Colorless"]).duplicate()
		for ab in metadata.get("abilities", []):
			if ab.get("name","") == "Dual Armor":
				var t = ab.get("text","")
				if "Metal Energy" in t and _dual_armor_has_energy("Metal") and "Metal" not in base_types:
					base_types.append("Metal")
				if "Grass Energy" in t and _dual_armor_has_energy("Grass") and "Grass" not in base_types:
					base_types.append("Grass")
					if "Psychic Energy" in t and _dual_armor_has_energy("Psychic") and "Psychic" not in base_types:
						base_types.append("Psychic")
					if "Fighting Energy" in t and _dual_armor_has_energy("Fighting") and "Fighting" not in base_types:
						base_types.append("Fighting")
				break
		return base_types
	return metadata.get("types", ["Colorless"])

# Local helper for Dual Armor: does an attached Energy card provide the given type? (Basic "<Type>
# Energy" by name, or a Special Energy whose name contains the type, e.g. "Dark Metal Energy".)
func _dual_armor_has_energy(type_name: String) -> bool:
	for e in attached_energies:
		var ename = e.metadata.get("name","")
		if ename == type_name + " Energy" or type_name in ename:
			return true
	return false

# EX11 (EX Delta Species): a Pokemon "has δ on its card" if the δ symbol is part of its printed
# name (e.g. "Beedrill δ", "Latios δ"). Used by Holon stadiums/supporters and the Delta powers.
func is_delta() -> bool:
	# EX15 Holon Veil (Ampharos δ) sets granted_delta on every Basic/Evolution card on that side.
	return "δ" in metadata.get("name", "") or granted_delta

# EX11: number of "Holon Energy" special-energy cards (Holon Energy FF/GL/WP) attached to this
# Pokemon. Several ex11 attacks/bodies scale off, or gate on, attached Holon Energy.
func holon_energy_count() -> int:
	var n := 0
	for e in attached_energies:
		if e.metadata.get("name", "").begins_with("Holon Energy"):
			n += 1
	return n

# EX12 (EX Legend Maker): number of React Energy special-energy cards attached to this Pokemon.
# React Energy provides Colorless, but many ex12 attacks/bodies scale off, gate on, or move it.
func react_energy_count() -> int:
	var n := 0
	for e in attached_energies:
		if e.metadata.get("name", "") == "React Energy":
			n += 1
	return n

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
