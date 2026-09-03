extends Control

######################################################################################################################################################
################################################################# SET OF VARIABLES ###################################################################
######################################################################################################################################################

# GLOBAL VARIABLES FOR FULL MATCH VARIABLES AND CHANGABLES. MOST ARE SELF EXPLANATORY BY NAME

# TESTING VARIABLES
var amount_of_cards_to_draw = 7	# CAN CHANGE THE AMOUNT OF INITIAL HAND CARDS TO CHECK ARRAYS AND CARD FUNCTIONS
var hide_hidden_cards = true      	# TO SHOW PRIZE CARDS AND OPPONENTS HAND SET TO TRUE. FOR REAL GAME SET TO FALSE
var opponent_deck_name = "null"
var player_deck_name = "null"
var amount_of_prize_cards = 6

# When true, the match is ending — all turn logic should bail out immediately
var game_is_over: bool = false

# Helper: returns true if the game has ended or this node has been removed from
# the scene tree (which happens after change_scene_to_file). Every async function
# should call this after any await and return immediately if true.

# Fix 3: Consolidated boolean check for pokemon selection modes
func is_pokemon_selection_mode_active() -> bool:
	return (card_attach_mode_active or evolution_mode_active or retreat_mode_active
		or trainer_pokemon_selection_active or forced_switch_selection_active
		or knockout_bench_selection_active or damage_swap_mode_active
		or rain_dance_mode_active or energy_trans_mode_active
		or buzzap_mode_active or trainer_bench_token_discard_active
		or pokemon_preview_active)  # ISSUE #80: single-card preview lays the focus Pokémon out like the retreat active


# Fix 1: Returns cached card array for a set prefix
func get_set_cards(set_prefix: String) -> Array:
	if set_prefix in _set_metadata_cache:
		return _set_metadata_cache[set_prefix]
	return []

func _should_bail() -> bool:
	return game_is_over or not is_inside_tree()

# There are different rulesets for burn and confusion depending on what generation/set is being played.
# Additionally I personally felt base set confusion retreat rule is horrendous, so I have created a personal rule that doesn't give free retreat but doesn't force discard then coin flip
# ISSUE #34: both are chosen by the player in Options; _ready() copies the saved choice out of
# GameState. The values below are only the fallback if a match somehow runs before GameState loads.
var burn_rules: String = "base_set_burn_rules" # "base_set_burn_rules" or "modern_era_burn_rules"
var confusion_rules: String = "base_set_confusion_rules" # "base_set_confusion_rules" or "fairer_confusion_rules" or "modern_era_confusion_rules"

# Customisable in game textures
# Load coin textures
var tex_heads = load("res://Image_Assets/Coins/Pikachu Gold 1.png")
var tex_opp_heads = null   # loaded after opponent_data is available; falls back to tex_heads
var tex_tails = load("res://Image_Assets/Coins/Back Basic.png")

# Game Variables
var turn_number: int = 0
var opponent_data = {}

# PLAYER VARIABLES
var player_hand: Array = []
var player_deck: Array = []
var player_bench: Array = []
var player_prize_cards = []
var player_active_pokemon: card_object = null
var player_discard_pile: Array = []

# OPPONENT VARIABLES
var opponent_hand: Array = []
var opponent_deck: Array = []
var opponent_bench: Array = []
var opponent_prize_cards = []
var opponent_active_pokemon: card_object = null
var opponent_discard_pile: Array = []

# FUNCTIONAL REQUIREMENT VARIABLES
var card_selection_mode_enabled = false
var selected_card_for_action = null
var prize_card_selection_active: bool = false

## ISSUE #158: while true, show_enlarged_array_selection_mode draws the pool FACE
## DOWN whatever array it was handed. Set it, run the prompt, clear it — see
## Attack_Effects._pick_blind_from_hand, which is the only user.
var force_face_down_selection: bool = false
var force_face_down_sleeve: String = ""
var knockout_bench_selection_active: bool = false

var match_just_started_basic_pokemon_required = true
var bench_setup_phase_active = false

var player_energy_played_this_turn: bool = false
var opponent_energy_played_this_turn: bool = false
# MATCH EFFECT: extra_energy_per_turn — attach counters. The bools above keep meaning
# "limit reached" so all existing readers work unchanged; these track how many so far.
var player_energy_attach_count: int = 0
var opponent_energy_attach_count: int = 0

var energy_card_awaiting_target: card_object = null  # Stores the energy card while selecting its target
var card_attach_mode_active: bool = false

var evolution_card_awaiting_target: card_object = null
var evolution_mode_active: bool = false

var opponents_turn_active: bool = false

var retreat_mode_active: bool = false
# ISSUE #46 (retest): during the player retreat energy-selection screen, raise the small energy
# cards this many pixels so their vertical centre lines up with the enlarged Active card's centre,
# instead of their bottoms sitting on the Active's HP-label line. TWEAKABLE.
const RETREAT_ENERGY_RAISE_PX: float = 120.0
var retreat_bench_selection_active: bool = false
var retreat_energies_selected: Array = []
var retreat_cost_remaining: int = 0
## ISSUE #265: true while a disabled-row explanation is on screen, so a burst of
## clicks on a dead Retreat row cannot stack up a queue of identical message boxes.
var _disabled_reason_showing: bool = false
var player_retreat_disabled: bool = false
var opponent_retreat_disabled: bool = false

# ISSUE #80: bench viewing / single-card preview. `bench_view_active` = the enlarged all-bench VIEW is
# up (view-only, no action button); clicking a card there opens the single-card preview.
# `pokemon_preview_active` = the single-card preview is up (that Pokémon + its attached energies/tools
# laid out to the left, HP underneath, only a centred Close button). Both are view-only.
var bench_view_active: bool = false
var pokemon_preview_active: bool = false
var pokemon_preview_target: card_object = null
var player_retreated_this_turn: bool = false
var opponent_retreated_this_turn: bool = false
var xxxxx_used_this_turn: bool = false  # neo4-30 Unown [X] [XXXXX]: only one bonus per turn
# EX5: "at most 1 per turn across all copies" gates for Bellossom Heal Dance and Castform Temperamental Weather
var player_ex5_heal_dance_used: bool = false
var opponent_ex5_heal_dance_used: bool = false
var player_ex5_weather_used: bool = false
var opponent_ex5_weather_used: bool = false
# EX8: "at most 1 per turn across all copies" gates for Deoxys Form Change and Ludicolo Happy Dance
var player_ex8_form_change_used: bool = false
var opponent_ex8_form_change_used: bool = false
var player_ex8_happy_dance_used: bool = false
var opponent_ex8_happy_dance_used: bool = false
# EX8 Pelipper Bay Dance: +30 to your Active Pokemon's attacks during your NEXT turn.
# pending set the turn Bay Dance is used; promoted to active when that side's next turn begins.
var player_ex8_bay_dance_pending: bool = false
var opponent_ex8_bay_dance_pending: bool = false
var player_ex8_bay_dance_active: bool = false
var opponent_ex8_bay_dance_active: bool = false
# EX3/EX9 Dragon Dance: side-wide "your Active Pokemon do +N damage next turn" buff. Stores the bonus
# amount (0 = inactive); pending set the turn Dragon Dance is used, promoted to active next turn.
var player_dragon_dance_pending: int = 0
var opponent_dragon_dance_pending: int = 0
var player_dragon_dance_active: int = 0
var opponent_dragon_dance_active: int = 0

# Mirror Move: stores the last attack result so Pidgeotto can copy it
var last_attack_on_player: Dictionary = {}   # {"damage": int, "attack": Dictionary, "attacker_types": Array}
var last_attack_on_opponent: Dictionary = {} # same structure

# Special attack selection modes (Metronome, Amnesia, Conversion)
var special_attack_selection_active: bool = false
var special_attack_selection_callback: Callable
var energy_type_selection_active: bool = false

# Defender energy discard selection (Hyper Beam, Whirlpool)
var defender_energy_discard_active: bool = false

# Forced switch selection (Whirlwind, Lure)  
var forced_switch_selection_active: bool = false

# Track whether an attack was made this turn (for mirror move clearing)
var player_attacked_this_turn: bool = false
var opponent_attacked_this_turn: bool = false

# TRAINER CARD VARIABLES
var trainer_card_mode_active: bool = false
var trainer_discard_selection_active: bool = false
var trainer_discard_cards_needed: int = 0
var trainer_discard_selected: Array = []
var trainer_deck_search_active: bool = false
var trainer_pokemon_selection_active: bool = false
# True only while a genuine Yes/No question is on screen (Trainer_Effects.gym1_prompt_yes_no).
# Set by that helper and read by _input(), which is what lets Space/Enter answer YES and
# Escape answer NO. Kept separate from the selection flags above because those modes are
# card pickers, not questions — binding the keys to them would confirm partial selections.
var yes_no_prompt_active: bool = false
var trainer_energy_selection_active: bool = false
var trainer_reorder_active: bool = false
var trainer_bench_token_discard_active: bool = false

# Pokedex reorder tracking
var pokedex_cards: Array = []
var pokedex_reorder_result: Array = []

# Stadium zone — only one stadium can be in play at a time. New stadium discards old to its owner's pile.
var current_stadium_card: card_object = null
var current_stadium_owner_is_opponent: bool = false  # tracks which side OWNS the stadium (for discard pile destination only)

# Stadium activatable effects (per-turn flags)
var player_celadon_used_this_turn: bool = false      # gym1-107 Celadon City Gym — once-per-turn-per-player activation
var opponent_celadon_used_this_turn: bool = false
var player_apricorn_forest_used_this_turn: bool = false   # ecard2-118 Apricorn Forest
var opponent_apricorn_forest_used_this_turn: bool = false
var player_undersea_ruins_used_this_turn: bool = false    # ecard2-138 Undersea Ruins
var opponent_undersea_ruins_used_this_turn: bool = false
var player_power_plant_used_this_turn: bool = false       # ecard2-139 Power Plant
var opponent_power_plant_used_this_turn: bool = false
var player_ancient_ruins_used_this_turn: bool = false      # ecard3-119 Ancient Ruins
var opponent_ancient_ruins_used_this_turn: bool = false
var player_mystery_zone_used_this_turn: bool = false        # ecard3-137 Mystery Zone
var opponent_mystery_zone_used_this_turn: bool = false
var player_underground_lake_used_this_turn: bool = false    # ecard3-141 Underground Lake
var opponent_underground_lake_used_this_turn: bool = false
var player_fuchsia_used_this_turn: bool = false      # gym2-114 Fuchsia City Gym — once-per-turn-per-player Koga shuffle
var opponent_fuchsia_used_this_turn: bool = false
var player_lucky_stadium_used_this_turn: bool = false     # basep-41 Lucky Stadium
var opponent_lucky_stadium_used_this_turn: bool = false
var player_saffron_used_this_turn: bool = false           # gym2-113 Saffron City Gym
var opponent_saffron_used_this_turn: bool = false
var player_healing_field_used_this_turn: bool = false     # neo3-61 Healing Field
var opponent_healing_field_used_this_turn: bool = false

# Stadium one-shot attack modifiers — gym1-120 Vermilion City Gym (Lt. Surge attacker coin flip)
var vermilion_lt_surge_bonus_damage: int = 0          # +10 added by calculate_final_damage when set, cleared after read
var vermilion_lt_surge_self_damage_pending: int = 0   # 10 applied to attacker after damage resolves
var vermilion_lt_surge_attacker_is_opponent: bool = false  # which side the pending self-damage belongs to

# POKEMON POWER VARIABLES
var power_menu_active: bool = false
var damage_swap_mode_active: bool = false
var damage_swap_source: card_object = null
var rain_dance_mode_active: bool = false
var energy_trans_mode_active: bool = false
var energy_trans_source: card_object = null
var buzzap_mode_active: bool = false

# Special Energy Effects handler
var special_energy_effects: Node

# BASE5 (TEAM ROCKET) VARIABLES
var goop_gas_active: bool = false
var goop_gas_owner_is_opponent: bool = false
var player_prizes_face_up: bool = false
var opponent_prizes_face_up: bool = false

# GYM1 (GYM HEROES) trainer match-state
var player_misty_boost_active: bool = false       # gym1-18/102 Misty — next damage attack by Misty-named active gets +20 (one-shot, cleared at end of turn)
var opponent_misty_boost_active: bool = false

# ECARD1 Charizard Burning Energy: while active, all basic Energy on that side's Pokemon counts as Fire (cleared at end of turn)
var player_ecard1_burning_energy_active: bool = false
var opponent_ecard1_burning_energy_active: bool = false
var player_tickled_set_aside: Array = []          # gym1-119 Tickling Machine — cards held away from hand
var opponent_tickled_set_aside: Array = []
var player_hand_tickled: bool = false             # true while player's hand is held in player_tickled_set_aside
var opponent_hand_tickled: bool = false           # true while opponent's hand is held in opponent_tickled_set_aside
var player_turn_force_end: bool = false           # set by Tickling Machine tails / Minion of Team Rocket tails (player side)
var opponent_turn_force_end: bool = false         # set by Tickling Machine tails / Minion of Team Rocket tails (CPU side)

# GYM2 (GYM CHALLENGE) trainer match-state
var player_blaine_double_attach_used: bool = false  # gym2-17/100 Blaine — replaces this turn's energy attachment; one-shot per turn
var opponent_blaine_double_attach_used: bool = false
var player_koga_poison_active: bool = false         # gym2-19/106 Koga — if this turn a Koga-named attacker damages defender, Poison them
var opponent_koga_poison_active: bool = false
var player_transparent_walls_active: bool = false   # gym2-125 Transparent Walls — bench-damage protection until end of opp's next turn
var opponent_transparent_walls_active: bool = false

# PRELOADED RESOURCES
var theme_disabled = preload("res://UI_Themes/ui/ui_secondary.tres")
var theme_green = preload("res://UI_Themes/ui/ui_primary.tres")
var theme_blue = preload("res://UI_Themes/ui/ui_secondary.tres")
var theme_red = preload("res://UI_Themes/ui/ui_danger.tres")
var card_display_script = preload("res://Scripts/Global_Scripts/Card_Image_Loader_Script.gd")
var card_back_texture: Texture2D          # player's sleeve small — set in _ready
var opponent_card_back_texture: Texture2D # opponent's sleeve small — set in _ready
var player_sleeve_small: String = ""
var opponent_sleeve_small: String = ""
var player_sleeve_border_color: Color = Color(0.15, 0.15, 0.15, 1.0)
var opponent_sleeve_border_color: Color = Color(0.15, 0.15, 0.15, 1.0)

# The ESC forfeit confirmation popup, or null when it isn't up. See _show_forfeit_dialog().
var forfeit_dialog: CanvasLayer = null

# --- Card zoom (hold Shift to enlarge whatever the mouse is over) ------------
# The same hold-to-preview the deck builder, coin case, sleeve and costume screens use,
# brought onto the match board: hold the key and slide the mouse and the enlarged image
# follows from card to card, so a whole row can be read one after another without ever
# letting go. Works on anything face up - your hand, either Active, either bench, the
# energies and tools attached to them, the top of a discard pile, and the cards laid out
# by a selection screen. Face-down cards (the opponent's hand, both sets of prize cards)
# are refused, and stay refused until some effect turns one face up.
const ZOOM_BACKDROP_ALPHA: float = 0.95        # how much of the board the preview hides behind it
var zoom_overlay: CanvasLayer = null
var is_zoomed: bool = false
var zoom_held: bool = false                    # the key is down, so the preview tracks the mouse
var zoomed_card_node: CardDisplay = null       # the card currently on show, so _process only redraws on a change
# The panel that draws the enlarged card AND every box of its data. Kept so a hover change can
# re-point the live panel instead of rebuilding the overlay. See Scripts/Global_Scripts/Card_Detail_Panel.gd.
var detail_panel: CardDetailPanel = null

#signals
signal message_acknowledged
signal prize_card_taken
signal knockout_replacement_chosen
signal special_attack_selected(attack_index: int)
signal energy_type_selected(energy_type: String)
signal defender_energy_chosen(energy_card: card_object)
signal forced_switch_chosen

# Trainer card signals
signal trainer_discard_selection_done
signal trainer_target_selected
signal trainer_deck_search_done
signal trainer_reorder_done
signal power_action_done

# CACHED NODE PATHS - These are assigned once when the node enters the scene tree via @onready.
# In GDScript, @onready runs the assignment at the same time as _ready(), meaning the scene tree
# is fully built. This avoids repeated get_node() calls every time we reference these paths with $.
@onready var action_button = $BUTTONS/SELECTION_BUTTONS/card_action_button
@onready var cancel_button = $cancel_selection_mode_view_button
var action_button_default_offset_left: float = 0.0
var action_button_default_offset_right: float = 0.0
var action_button_paired_offset_left: float = 0.0
var action_button_paired_offset_right: float = 0.0
var action_button_positions_stored: bool = false
@onready var header_label = $SCREEN_LABELS/MAIN_LABELS/large_header_text_label
@onready var hint_label = $SCREEN_LABELS/MAIN_LABELS/small_hint_info_text_label
@onready var player_active_container = $ACTIVE_POKEMON/PLAYER/player_active_pokemon_container
@onready var opponent_active_container = $ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_container
@onready var player_bench_container = $CARD_COLLECTIONS/PLAYER/player_bench_container
@onready var opponent_bench_container = $CARD_COLLECTIONS/OPPONENT/opponent_bench_container
@onready var player_hand_container = $CARD_COLLECTIONS/PLAYER/player_hand_hbox_container
@onready var opponent_hand_container = $CARD_COLLECTIONS/OPPONENT/opponent_hand_hbox_container
@onready var player_energy_container = $ACTIVE_POKEMON/PLAYER/player_active_pokemon_energies
@onready var opponent_energy_container = $ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_energies
@onready var player_hp_container = $ACTIVE_POKEMON/PLAYER/player_active_pokemon_hp_container
@onready var opponent_hp_container = $ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_hp_container
@onready var player_status_container = $ACTIVE_POKEMON/PLAYER/player_active_pokemon_status_container
@onready var opponent_status_container = $ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_status_container
@onready var player_prize_container = $CARD_COLLECTIONS/PLAYER/player_prize_cards_container
@onready var opponent_prize_container = $CARD_COLLECTIONS/OPPONENT/opponent_prize_cards_container
@onready var player_deck_icon = $CARD_COLLECTIONS/PLAYER/player_deck_icon
@onready var opponent_deck_icon = $CARD_COLLECTIONS/OPPONENT/opponent_deck_icon
@onready var player_discard_icon = $CARD_COLLECTIONS/PLAYER/player_discard_pile_icon
@onready var opponent_discard_icon = $CARD_COLLECTIONS/OPPONENT/opponent_discard_pile_icon
@onready var small_selection_container = $SELECTION_MODE/small_selection_mode_container
@onready var selection_scroller = $SELECTION_MODE/selection_mode_scroller
@onready var large_selection_container = $SELECTION_MODE/selection_mode_scroller/large_selection_mode_container
@onready var attack_buttons_container = $BUTTONS/main_screen_attack_buttons_container
@onready var main_buttons_container = $BUTTONS/main_screen_buttons_container
@onready var msgbox_container = $messagebox_container
# ISSUE #121: retired. Both are hidden for good by _ensure_match_msgbox() -- kept only so the
# scene's node paths stay valid. The box itself is now a DynamicMessageBox, see show_message().
@onready var msgbox_texture = $messagebox_container/messagebox_texture
@onready var msgbox_label = $messagebox_container/messagebox_text_label

# ISSUE #121: the in-match message box, built in code like every other box in the game.
var _match_msgbox: DynamicMessageBox = null
# Same panel height as an overworld sign/interactable box. The font is the match's own 40pt
# ceiling rather than the overworld's 28 -- set_body_text() steps it down if a long line needs it.
const MATCH_MSGBOX_HEIGHT: float = 138.0
const MATCH_MSGBOX_FONT_SIZE: int = 34
## The MessageBoxTheme key the in-match box and the match log both use.
const MATCH_MSGBOX_THEME: String = "match"

# ── MATCH LOG (Caps Lock) ────────────────────────────────────────────────────
# Every message shown this match, oldest first, as
# { "text": String, "turn": int, "opp": bool }. Appended by show_message(), which
# is the single funnel all ~3,000 in-match messages pass through, so nothing else
# had to change to capture them.
#
# BEST-OF-3: this is an instance var and every round loads a fresh copy of the
# match scene through SceneCache.change_scene_to_packed(), so the log empties
# itself between rounds with no explicit reset. Do NOT make it static.
var _match_log: Array = []
var _match_log_panel: MatchLogPanel = null
var _match_log_layer: CanvasLayer = null
var match_log_open: bool = false
# Oldest entries are dropped past this. A long match with a lot of Powers can run
# to several hundred messages and the panel rebuilds the whole list on open.
const MATCH_LOG_MAX_ENTRIES: int = 250
# Above the forfeit dialog (100), below the card preview (150).
const MATCH_LOG_LAYER: int = 120
@onready var coin_container = $coin_flip_container
@onready var coin_texture = $coin_flip_container/coin_flip_texture
@onready var opponent_blocker = $opponent_turn_input_blocker
@onready var animation_blocker = $animation_input_blocker
@onready var buttons_only_blocker = $allow_buttons_only_blocker
@onready var trainer_block_container = $trainer_block_screen_container
@onready var played_trainer_container = $trainer_block_screen_container/played_trainer_card_container
@onready var player_attached_cards_container = $ACTIVE_POKEMON/PLAYER/player_active_pokemon_attached_cards
@onready var opponent_attached_cards_container = $ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_attached_cards
@onready var stadium_card_container = $CARD_COLLECTIONS/stadium_card

# QUICK REFERENCE VECTORS JUST USED FOR EASY SWAPPING OF SIZES FOR DEVELOPMENT
# Board chrome, built by _build_board_layout().
var _board_header : UIKit.ChromeBar = null
var _board_footer : UIKit.ChromeBar = null
var _turn_chip_holder : Control = null
var _turn_chip : Control = null
var _turn_divider_label : Label = null
var _duel_divider_x : float = 0.0

## ISSUE #212: the board furniture _set_board_furniture_visible() toggles.
var _stadium_slot : Control = null
var _stadium_caption : Label = null
var _turn_divider_rules : Array = []

# The two action-panel holders, filled by _build_action_panel().
var _player_action_panel : Control = null
var _opp_action_panel : Control = null
var _stadium_overlay : Control = null
var _end_turn_btn : Button = null
## ISSUE #239: the two attachment-row captions per side, so #212 can hide them
## with the rest of the board furniture.
var _attach_captions: Array = []
## ISSUE #214 / #235: true while a single card is being shown full-screen.
var _card_showcase_active: bool = false

# The prize count each side started the match with — see display_prize_cards().
var player_prize_start : int = 0
var opponent_prize_start : int = 0

var card_scales: Dictionary = {
	1: Vector2(450, 619),
	1.5: Vector2(575, 791),
	2: Vector2(400, 550),
	2.5: Vector2(525, 722),
	3: Vector2(375, 515),
	3.5: Vector2(405, 557),
	4: Vector2(350, 481),
	4.5: Vector2(375, 515),
	5: Vector2(350, 481),
	5.5: Vector2(325, 447),
	6: Vector2(300, 413),
	6.5: Vector2(282, 388),
	7: Vector2(265, 364),
	7.5: Vector2(262, 361),
	8: Vector2(260, 358),
	8.5: Vector2(230, 316),
	9: Vector2(200, 275),
	9.5: Vector2(175, 240),
	10: Vector2(150, 206),
	10.5: Vector2(125, 172),
	11: Vector2(100, 138),
	11.55: Vector2(50, 69),
	11.5: Vector2(75, 103),
	12: Vector2(50, 69),
	13: Vector2(25, 35)
}

# Fix 4: Named card size constants for readability
const CARD_SIZE_FULLSCREEN = Vector2(450, 619)
const CARD_SIZE_SINGLE_SELECTION = Vector2(400, 550)
const CARD_SIZE_SELECTION_4 = Vector2(405, 557)
const CARD_SIZE_SELECTION_LARGE = Vector2(350, 481)
const CARD_SIZE_ACTIVE = Vector2(260, 358)
const CARD_SIZE_ACTIVE_ANIM = Vector2(200, 275)
const CARD_SIZE_ENERGY_ANIM = Vector2(150, 206)
const CARD_SIZE_BENCH = Vector2(100, 138)
const CARD_SIZE_OPPONENT_HAND = Vector2(50, 69)
const CARD_SIZE_SMALL_ANIM = Vector2(50, 69)

# Helper script references (instantiated in _ready)
var attack_effects: Node
var trainer_effects: Node
var cpu_ai: Node
var powers_and_bodies: Node
var card_ops: Node
var match_effects: Node

# Fix 1: Set metadata cache — keyed by set prefix string, value is parsed Array from JSON
var _set_metadata_cache: Dictionary = {}

# Fix 8: Texture cache — keyed by card UID string, value is Texture2D
var _texture_cache: Dictionary = {}

######################################################################################################################################################
################################################################# END OF VARIABLES ###################################################################
######################################################################################################################################################

######################################################################################################################################################
################################################################ START OF FUNCTIONS ##################################################################
######################################################################################################################################################

#       #####     ######  #####   #####    ##         ##    ##   ##
#       ##   ##     ##   ##       ##   ##  ##        ####    ##  ##
#       ##     ##   ##     ###    #####    ##       ##  ##     ###
#       ##   ##     ##        ##  ##       ##      ########     ##
#       #####     ######  #####   ##       #####  ##      ##   ###

######################################################################################################################################################
################################################################# DISPLAY FUNCTIONS ##################################################################

# Main reusable function to display any array passed in a LARGE viewing mode, hide everything else on the screen and allows selection of cards for action
func show_enlarged_array_selection_mode(card_array: Array) -> void:
	
	selection_scroller.visible = false
	large_selection_container.visible = false
	small_selection_container.visible = false
	
	# Prevent showing empty arrays
	if card_array.size() == 0:
		print("Cannot show enlarged array: array is empty")
		return
	
	# Hide attack buttons if they are currently showing
	if attack_buttons_container.visible:
		hide_attack_buttons()
	
	card_selection_mode_enabled = true
	var amount_of_cards_to_show = card_array.size()
	
	# Hide all main screen elements
	_set_board_furniture_visible(false)   # ISSUE #212
	player_hand_container.visible = false
	opponent_hand_container.visible = false
	player_active_container.visible = false
	opponent_active_container.visible = false
	player_active_container.mouse_filter = MOUSE_FILTER_IGNORE
	opponent_active_container.mouse_filter = MOUSE_FILTER_IGNORE
	player_energy_container.visible = false
	opponent_energy_container.visible = false
	player_hp_container.visible = false
	opponent_hp_container.visible = false
	player_status_container.visible = false
	opponent_status_container.visible = false
	player_bench_container.visible = false
	opponent_bench_container.visible = false
	$SCREEN_LABELS/OPPONENT/opponent_bench_cards_label.visible = false
	$SCREEN_LABELS/PLAYER/player_bench_cards_label.visible = false
	$SCREEN_LABELS/OPPONENT/opponent_prize_cards_label.visible = false
	$SCREEN_LABELS/PLAYER/player_prize_cards_label.visible = false
	opponent_prize_container.visible = false
	player_prize_container.visible = false
	player_deck_icon.visible = false
	opponent_deck_icon.visible = false
	player_discard_icon.visible = false
	opponent_discard_icon.visible = false
	player_attached_cards_container.visible = false
	opponent_attached_cards_container.visible = false
	hint_label.visible = true
	header_label.visible = true
	main_buttons_container.visible = false
	
	for card in player_active_container.get_children():
		card.mouse_filter = MOUSE_FILTER_IGNORE
	for card in opponent_active_container.get_children():
		card.mouse_filter = MOUSE_FILTER_IGNORE
	
	action_button.visible = true
	
	if match_just_started_basic_pokemon_required == true or knockout_bench_selection_active == true or forced_switch_selection_active == true or defender_energy_discard_active == true or energy_type_selection_active == true or trainer_discard_selection_active == true or trainer_pokemon_selection_active == true or trainer_deck_search_active == true or trainer_reorder_active == true:
		cancel_button.visible = false
	else:
		cancel_button.visible = true
	
	var is_view_only_array = card_array in [opponent_hand, opponent_bench, player_discard_pile, opponent_discard_pile]
	if not prize_card_selection_active:
		is_view_only_array = is_view_only_array or card_array in [player_prize_cards, opponent_prize_cards]
		
	if is_view_only_array:
		action_button.visible = false		
	else:
		action_button.visible = true
	
	if trainer_pokemon_selection_active or trainer_deck_search_active or trainer_discard_selection_active or trainer_reorder_active:
		action_button.visible = true

	# ISSUE #80: bench viewing and the single-card preview are view-only — never show an action button
	# (this removes the legacy "PLACE ON BENCH" that used to appear when viewing the player's bench).
	if bench_view_active or pokemon_preview_active:
		action_button.visible = false

	if not action_button_positions_stored:
		action_button_default_offset_left = action_button.offset_left
		action_button_default_offset_right = action_button.offset_right
		action_button_paired_offset_left = action_button.offset_left - 210.0
		action_button_paired_offset_right = action_button.offset_right - 210.0
		action_button_positions_stored = true

	if action_button.visible:
		if cancel_button.visible:
			action_button.offset_left = action_button_paired_offset_left
			action_button.offset_right = action_button_paired_offset_right
			cancel_button.offset_left = 35.0
			cancel_button.offset_right = 473.0
		else:
			action_button.offset_left = action_button_default_offset_left
			action_button.offset_right = action_button_default_offset_right
	else:
		cancel_button.offset_left = -219.0
		cancel_button.offset_right = 219.0
		
	update_selection_mode_labels(card_array, match_just_started_basic_pokemon_required)
	
	# ISSUE #158: force_face_down_selection lets an effect show a pool the player
	# must pick from WITHOUT SEEING IT — "choose 1 card from your opponent's hand
	# without looking". The usual test is identity-based (`card_array ==
	# opponent_hand`), which a shuffled copy of that hand can never satisfy.
	var should_hide = force_face_down_selection or (hide_hidden_cards and (card_array == opponent_hand or card_array == player_prize_cards or card_array == opponent_prize_cards))
	var selection_sleeve: String = ""
	if should_hide:
		if force_face_down_selection and force_face_down_sleeve != "":
			selection_sleeve = force_face_down_sleeve
		else:
			selection_sleeve = opponent_sleeve_small if (card_array == opponent_hand or card_array == opponent_prize_cards) else player_sleeve_small

	# --- UNIFIED SIZING SYSTEM ---
	# The white zone is the usable display area between the hint label bottom and the action buttons.
	# Screen height = 816. Hint label bottom ≈ 165. Button top ≈ 771. Padding = 20px each side.
	# This gives a usable content height of ~586px and a center at y ≈ 468.
	const WHITE_ZONE_TOP: float = 165.0
	const WHITE_ZONE_BOTTOM: float = 771.0
	const WHITE_ZONE_CENTER_Y: float = (WHITE_ZONE_TOP + WHITE_ZONE_BOTTOM) / 2.0  # ≈ 468
	const WHITE_ZONE_HEIGHT: float = WHITE_ZONE_BOTTOM - WHITE_ZONE_TOP            # = 606
	const ZONE_PADDING: float = 20.0
	const USABLE_HEIGHT: float = WHITE_ZONE_HEIGHT - (ZONE_PADDING * 2.0)          # = 566
	
	if amount_of_cards_to_show > 7:
		# Large scroller: use fixed card_scales[5] as before — scroller handles overflow.
		selection_scroller.visible = true
		large_selection_container.visible = true
		display_hand_cards_array(card_array, large_selection_container, card_scales[5], should_hide, 1300.0, 12, selection_sleeve)
	else:
		small_selection_container.visible = true
		small_selection_container.custom_minimum_size = Vector2(0, 0)
		
		# Determine whether this array can have energies/HP (pokemon selection modes).
		var is_bench_view = (card_array == player_bench or card_array == opponent_bench)
		var is_pokemon_mode = is_bench_view or is_pokemon_selection_mode_active()
		
		# Find the max energy count on any in-play pokemon in this array.
		var max_energies = 0
		if is_pokemon_mode:
			for card_obj in card_array:
				var loc = card_obj.current_location
				if (loc == "bench" or loc == "active") and card_obj.metadata.has("hp"):
					max_energies = max(max_energies, card_obj.attached_energies.size())
		
		# The "scale level" key for card_scales. Larger key = smaller card.
		# For a single card, go one size smaller (key+1) so it doesn't dominate the screen.
		var scale_key = float(amount_of_cards_to_show)
		if amount_of_cards_to_show == 1:
			scale_key = 2.0  # one step smaller than scale[1]
		
		# Retrieve the base card size for this array count.
		var base_card_size: Vector2 = card_scales.get(scale_key, card_scales[7])
		
		# Compute the energy strip height using the same formula as the slot builder.
		# This tells us how many pixels of energy stack sit above the card.
		var energy_strip_px: float = 0.0
		if max_energies > 0:
			var fraction = 0.12 - (max_energies - 1) * 0.01
			energy_strip_px = max(10.0, base_card_size.y * fraction) * max_energies
		
		# Estimated HP label height in pixels. Font size 33 ≈ 40px rendered height.
		var hp_label_px: float = 40.0 if is_pokemon_mode else 0.0
		
		# Total slot height = energy stack + card height + HP label.
		var total_slot_height = energy_strip_px + base_card_size.y + hp_label_px
		
		# If the total height exceeds the usable zone, scale the card down proportionally.
		# The active pokemon is 1.05x (was 1.2x, now halved the extra: 1.0 + (0.2/2) = 1.1, then
		# request #1 says halve that again: 1.0 + 0.1/2 = 1.05).
		# We account for this by using the active card's height (1.05x) in the ceiling calculation.
		var active_scale_factor = 1.05
		var max_card_h = base_card_size.y
		if is_pokemon_mode and amount_of_cards_to_show > 1:
			max_card_h = base_card_size.y * active_scale_factor
		
		# Recompute total slot height with active scale applied.
		var energy_strip_active_px: float = 0.0
		if max_energies > 0:
			var fraction = 0.12 - (max_energies - 1) * 0.01
			energy_strip_active_px = max(10.0, max_card_h * fraction) * max_energies
		var effective_total_h = energy_strip_active_px + max_card_h + hp_label_px
		
		# Scale factor to fit everything in the usable zone.
		var fit_scale = 1.0
		if effective_total_h > USABLE_HEIGHT:
			fit_scale = USABLE_HEIGHT / effective_total_h
		
		var card_size = Vector2(base_card_size.x * fit_scale, base_card_size.y * fit_scale)
		
		# Recompute energy stack and total slot height with final card size.
		var final_energy_px: float = 0.0
		if max_energies > 0:
			var fraction = 0.12 - (max_energies - 1) * 0.01
			final_energy_px = max(10.0, card_size.y * fraction) * max_energies
		var final_hp_px: float = 40.0 * fit_scale if is_pokemon_mode else 0.0
		var final_card_h = card_size.y * (active_scale_factor if (is_pokemon_mode and amount_of_cards_to_show > 1) else 1.0)
		var final_total_h = final_energy_px + final_card_h + final_hp_px
		
		# The HBoxContainer has alignment=END, meaning its children are bottom-aligned
		# within the container rect. With center anchor (anchor_y = 408 on a 816px screen)
		# and grow_vertical=BOTH:
		#   container top    = anchor_y - offset_top
		#   container bottom = anchor_y + offset_bottom
		#   content sits at the BOTTOM of this rect.
		#
		# So content bottom y = anchor_y + offset_bottom.
		# We want the content to be vertically centred in the white zone.
		# White zone center = WHITE_ZONE_CENTER_Y = 468.
		# Content spans final_total_h pixels, so:
		#   content bottom = WHITE_ZONE_CENTER_Y + final_total_h / 2
		#   offset_bottom  = content_bottom - anchor_y
		# The small_selection_container parent SELECTION_MODE is a 40x40 Control at (0,0).
		# anchor_top = anchor_bottom = 0.5, so anchor screen y = 0 + 0.5*40 = 20.
		# With alignment=END: content bottom = anchor_screen_y + offset_bottom = 20 + offset_bottom.
		# To centre content in white zone (top=165, bottom=771, centre=468):
		#   content_bottom = 468 + total_h/2  =>  offset_bottom = content_bottom - 20
		# offset_top: make container top well above content top (negative = above anchor).
		var anchor_screen_y: float = 20.0
		var content_bottom = WHITE_ZONE_CENTER_Y + final_total_h / 2.0 + 100.0
		var new_offset_bottom = content_bottom - anchor_screen_y
		var content_top = content_bottom - final_total_h
		var new_offset_top = content_top - anchor_screen_y - ZONE_PADDING
		small_selection_container.offset_top = new_offset_top
		small_selection_container.offset_bottom = new_offset_bottom
		
		# ISSUE #237: THE ROW HAD NO HORIZONTAL BOX TO LIVE IN.
		#
		# The scene parks small_selection_mode_container as a 40px-wide stub
		# (offsets 920..960 off a centre anchor) and only the VERTICAL offsets were
		# ever written. An HBoxContainer whose minimum width exceeds its rect then
		# grows out of that stub, and where it grows to depends on which way the
		# layout engine resolves the anchor that frame - which is why the row was
		# usually centred but occasionally started AT the centre and ran off the
		# right, and why it depended on the exact card count (six cards at
		# card_scales[6] is the widest combination the small path ever builds).
		#
		# It gets a real full-screen box and a CENTRE alignment, so there is nothing
		# left to resolve: the row is centred in 1920px whatever it contains.
		small_selection_container.offset_left = SELECT_ROW_LEFT
		small_selection_container.offset_right = SELECT_ROW_RIGHT
		small_selection_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
		small_selection_container.alignment = BoxContainer.ALIGNMENT_CENTER

		# ...and the cards are fitted to that width as well as to the height, so a
		# row that would have overflowed is shrunk instead of spilling off-screen.
		var natural_w: float = card_size.x * float(amount_of_cards_to_show) \
			+ float(HAND_SEPARATION) * float(maxi(amount_of_cards_to_show - 1, 0)) \
			+ (SELECT_FOCUS_EXTRA if is_pokemon_mode else 0.0)
		if natural_w > SELECT_ROW_MAX_W:
			var width_fit: float = SELECT_ROW_MAX_W / natural_w
			card_size = Vector2(card_size.x * width_fit, card_size.y * width_fit)

		display_hand_cards_array(card_array, small_selection_container, card_size, should_hide, 1300.0, 12, selection_sleeve)

# Both the cancel button and action button will hide selection mode so function is vaguely named for both actions
func hide_selection_mode_display_main() -> void:
	
	if selected_card_for_action != null:
		var card_ui = find_card_ui_for_object(selected_card_for_action)
		if card_ui:
			card_ui.set_selected(false)
	
	# End card selection mode and clear any selected card to prevent errors
	card_selection_mode_enabled = false
	selected_card_for_action = null
	# ISSUE #80: defensively clear the view-only preview/bench-view flags whenever the selection UI is torn down.
	bench_view_active = false
	pokemon_preview_active = false
	pokemon_preview_target = null
	update_action_button()
	
	# Hide the enlarged selection mode cards
	small_selection_container.visible = false
	selection_scroller.visible = false
	large_selection_container.visible = false
	
	# Hide the buttons
	cancel_button.visible = false
	action_button.visible = false
	
	# Show the player and opponents hands
	_set_board_furniture_visible(true)   # ISSUE #212
	# ISSUE #217: coming OUT of a selection screen is a state change the action
	# rows care about (is_pokemon_selection_mode_active is part of their gate), so
	# they are rebuilt here as well as on every turn transition.
	_refresh_action_panels()
	player_hand_container.visible = true
	opponent_hand_container.visible = true
	
	# Show the player and opponents active pokemon
	player_active_container.visible = true
	opponent_active_container.visible = true
	
	player_energy_container.visible = true
	opponent_energy_container.visible = true
	
	player_hp_container.visible = true
	opponent_hp_container.visible = true
	
	player_status_container.visible = true
	opponent_status_container.visible = true
	
	main_buttons_container.visible = true
	
	# Show the player and oppoents bench
	player_bench_container.visible = true
	opponent_bench_container.visible = true
	
	$SCREEN_LABELS/OPPONENT/opponent_bench_cards_label.visible = true
	$SCREEN_LABELS/PLAYER/player_bench_cards_label.visible = true
	
	$SCREEN_LABELS/OPPONENT/opponent_prize_cards_label.visible = true
	$SCREEN_LABELS/PLAYER/player_prize_cards_label.visible = true
	
	opponent_prize_container.visible = true
	player_prize_container.visible = true
	
	player_deck_icon.visible = true
	opponent_deck_icon.visible = true

	player_discard_icon.visible = true
	opponent_discard_icon.visible = true
	
	player_attached_cards_container.visible = true
	opponent_attached_cards_container.visible = true
	
	update_deck_icon(false)
	update_deck_icon(true)
	
	# We do however want to show the header and hint labels
	hint_label.visible = false
	header_label.visible = false
	
	action_button.text = "Select a Card"
	action_button.disabled = true
	action_button.theme = theme_disabled
	
	# Re-enable mouse input on previously hidden containers
	player_active_container.mouse_filter = MOUSE_FILTER_PASS
	opponent_active_container.mouse_filter = MOUSE_FILTER_PASS
	player_bench_container.mouse_filter = MOUSE_FILTER_PASS
	
	# Re-enable input on cards in the active pokemon containers
	for card in player_active_container.get_children():
		card.mouse_filter = MOUSE_FILTER_PASS
	for card in opponent_active_container.get_children():
		card.mouse_filter = MOUSE_FILTER_PASS
	
# Displays both the player and opponents hand cards. Shows players at the top of screen and opponents in top right smaller.
## ISSUE #248: the normal gap between two cards in a hand or a selection row. The
## overlap branch below may go BELOW this (cards tuck behind each other) but never
## above it.
const HAND_SEPARATION := 3

func display_hand_cards_array(hand: Array, hand_container, card_size: Vector2, face_down: bool = false, max_hand_width: float = 1300.0, max_before_overlap: int = 12, sleeve_path: String = ""):
	
	# Clear existing cards from container to prevent stale entries when cards leave or enter the hand.
	#
	# ISSUE #170: remove_child BEFORE queue_free. queue_free only detaches the node
	# at the END of the frame, so the old hand was still parented — and still
	# counted in the HBoxContainer's minimum width — while the new cards were being
	# added beside it. The row therefore grew to hold BOTH hands, shoving itself
	# out of position, and snapped back the moment the old cards were finally
	# freed. That is the "hand moves, cards appear, hand moves back" the player
	# sees whenever the opponent plays Bill or any other draw card.
	for child in hand_container.get_children():
		hand_container.remove_child(child)
		child.queue_free()
		
	if hand_container is HBoxContainer:
		var is_inside_scroller = hand_container.get_parent() is ScrollContainer
		if not is_inside_scroller and hand.size() > max_before_overlap:
			# ISSUE #248: THIS FORMULA COULD SPREAD A HAND OUT AS WELL AS TIGHTEN IT.
			# It solves for the separation that makes the row exactly max_hand_width
			# wide - so for the OPPONENT (36px sleeves in a 400px box, overlapping
			# past 7) eight cards came out at 16px apart instead of the usual 3, and
			# the fan visibly sprang open. Then a card was played, the count dropped
			# back under the threshold, and it snapped shut again: exactly the
			# "randomly became very spread out, went back after a card was played"
			# that was reported. Overlapping is the ONLY thing this branch is for, so
			# the result is clamped to the normal spacing.
			var card_width = card_size.x
			var n = hand.size()
			var sep: float = (max_hand_width - (n * card_width)) / (n - 1)
			var applied: int = mini(HAND_SEPARATION, int(floor(sep)))
			hand_container.add_theme_constant_override("separation", applied)
		else:
			hand_container.add_theme_constant_override("separation", HAND_SEPARATION)
	
	# Determine if we are in a pokemon selection mode.
	var is_bench_view = (hand == player_bench or hand == opponent_bench)
	var is_pokemon_selection_mode = is_bench_view or is_pokemon_selection_mode_active()
	
	# Draw all cards in the hand
	for index in range(hand.size()):
		var this_card_in_hand = hand[index]
		
		var loc = this_card_in_hand.current_location
		var card_is_in_play = (loc == "bench" or loc == "active")
		# ISSUE #75 (retest): only give the taller pokemon-SLOT layout (VBox with HP/energy) to Pokémon
		# actually IN PLAY. A Pokémon sitting in a revealed HAND (e.g. the lone Basic in a Lass reveal,
		# which turns on trainer_pokemon_selection to drive its Done button) has no HP/energy to show and
		# must render as a plain card like every other hand card — otherwise it sat ~10px out of line.
		var is_displayed_pokemon = is_pokemon_selection_mode and not face_down and this_card_in_hand.metadata.has("hp") and card_is_in_play
		var is_active_slot = is_pokemon_selection_mode and index == hand.size() - 1 and this_card_in_hand.current_location == "active"
		# ISSUE #80: the single-card preview's focus Pokémon is the LAST entry and may be a BENCH Pokémon
		# (not just the active), so treat it as the focus slot too.
		var is_preview_focus = pokemon_preview_active and index == hand.size() - 1 and card_is_in_play
		var is_focus_slot = is_active_slot or is_preview_focus

		if is_displayed_pokemon:
			# ISSUE #46/#80: on the retreat screen AND the single-card preview the focus Pokémon's
			# attached energies (and, for the preview, tools) are already shown as separate cards to its
			# left, so don't ALSO stack them above the card. Hide the stacked energies (HP stays) and
			# blow the focus card up 50% so it clearly stands out from the cards beside it.
			var is_expanded_focus = (retreat_mode_active and is_active_slot) or is_preview_focus
			var scale_factor = 1.5 if is_expanded_focus else (1.05 if is_active_slot else 1.0)
			var display_size = Vector2(card_size.x * scale_factor, card_size.y * scale_factor)
			var show_hp_and_energies = card_is_in_play
			var show_energies = card_is_in_play and not is_expanded_focus
			var slot = build_pokemon_slot_with_energies_and_hp(this_card_in_hand, display_size, 33, is_focus_slot, show_hp_and_energies, show_energies)
			slot.size_flags_vertical = Control.SIZE_SHRINK_END

			if is_focus_slot:
				var spacer = Control.new()
				spacer.custom_minimum_size = Vector2(25, 0)
				spacer.mouse_filter = MOUSE_FILTER_IGNORE
				hand_container.add_child(spacer)
				for child_idx in range(hand_container.get_child_count() - 1):
					hand_container.get_child(child_idx).size_flags_vertical = Control.SIZE_SHRINK_END
			
			hand_container.add_child(slot)
		else:
			var hand_card_to_display = TextureRect.new()
			hand_card_to_display.set_script(card_display_script)
			# ISSUE #46 FIX (retest): during the player retreat energy-selection screen, the small
			# energy cards sat with their bottoms on the Active's HP-label line. Raise them so their
			# centre lines up with the enlarged Active card's centre by bottom-aligning them in a
			# VBox with a RETREAT_ENERGY_RAISE_PX spacer beneath. Only these energy cards (the else
			# branch, in retreat pokemon-selection mode) are affected — not normal hand cards.
			# ISSUE #80: the single-card preview raises its energy/tool cards the same way as retreat so
			# they line up with the enlarged focus Pokémon beside them.
			if (retreat_mode_active or pokemon_preview_active) and is_pokemon_selection_mode:
				var raise_wrap = VBoxContainer.new()
				raise_wrap.size_flags_vertical = Control.SIZE_SHRINK_END
				raise_wrap.mouse_filter = MOUSE_FILTER_IGNORE
				raise_wrap.add_child(hand_card_to_display)
				var raise_pad = Control.new()
				raise_pad.custom_minimum_size = Vector2(0, RETREAT_ENERGY_RAISE_PX)
				raise_pad.mouse_filter = MOUSE_FILTER_IGNORE
				raise_wrap.add_child(raise_pad)
				hand_container.add_child(raise_wrap)
			else:
				hand_container.add_child(hand_card_to_display)
			hand_card_to_display.load_card_image(this_card_in_hand.uid, card_size, this_card_in_hand, face_down, sleeve_path)
			hand_card_to_display.card_clicked.connect(this_card_clicked)
						

# ============================================================
# BOARD LAYOUT (UI overhaul, stage 6)
# ============================================================
# The board is three horizontal bands and three vertical ones.
#
#   0 .. 92     top bar    - opponent's hand, the turn chip, the stadium
#   92 .. 918   field      - the play area
#   918 .. 1080 bottom bar - your hand and End Turn (162px, the only match-sized footer)
#
#   29 .. 209    left rail   - OPPONENT deck+discard (top), YOUR prizes (bottom)
#   232 .. 1688  centre      - opponent bench / duel row / your bench
#   1711 .. 1891 right rail  - OPPONENT prizes (top), YOUR deck+discard (bottom)
#
# THE RAILS ARE 180 DEGREE ROTATIONAL, NOT MIRRORED. The opponent sits opposite
# you, so their piles are diagonally opposite yours: your deck is bottom-right,
# theirs is top-left. Reading it as a vertical mirror is the easy mistake.
#
# Everything here is absolute at 1920x1080 and applied in _build_board_layout(),
# which runs once. The scene's own offsets are overwritten wholesale - do not try
# to keep the two in step, the scene is only a node list now.
# ============================================================

const BOARD_TOP_H    := 92.0
const BOARD_BOT_H    := 162.0
const FIELD_TOP      := BOARD_TOP_H
const FIELD_BOT      := 1080.0 - BOARD_BOT_H

const RAIL_W         := 180.0
const RAIL_PAD       := 29.0
const LEFT_RAIL_X    := RAIL_PAD
const RIGHT_RAIL_X   := 1920.0 - RAIL_PAD - RAIL_W

## Deck and discard piles: SIDE BY SIDE, never stacked. 77x107 with 13 between.
const PILE_SIZE      := Vector2(77.0, 107.0)
## ISSUE #220: 13 -> 24. The deck and the discard were nearly touching.
const PILE_GAP       := 24.0
const PILE_TOP_Y     := 132.0    # opponent's, in the left rail
## ISSUE #261: yours drop to just above the footer, matching the bench. Derived
## from the footer so the two stay in step: pile bottom sits PILE_FOOT_GAP above
## the 162px match footer, and its caption rides 26px above the pile.
const PILE_FOOT_GAP  := 5.0
const PILE_BOT_Y     := 1080.0 - BOARD_BOT_H - PILE_FOOT_GAP - PILE_SIZE.y

## Prize cards: 3 x 2 of the owner's sleeve. Taken ones stay in place, greyed -
## the count is spatial.
## ISSUE #238: +40% (52x72 -> 73x101). The 3-wide block is then 227px against a
## 180px rail, so it deliberately overhangs the rail inward; _place_rails clamps
## it to PRIZE_EDGE_PAD off the screen edge. Nothing shares that band - the piles
## are diagonally opposite and the benches start at x 648 - so the overhang is
## free space.
## ISSUE #260: ONE ROW OF SIX, +20% again (73x101 -> 88x121).
##
## Two rows of three stood 206px tall, and the opponent's block (top right, from
## y 132) reached down to y 338 - straight into their attachment row, which starts
## at y 326 and fans right across the same corner. A single row is 121 tall and
## clears it by 80px, so the +20% is paid for by the shape change rather than
## costing anything. Six across is 548px wide against a 180px rail, so the block
## overhangs INWARD; see the clamp in _place_rails.
## ISSUE #260 (retest): -20% again (88x121 -> 70x97). The one-row shape stays -
## that is what cleared the opponent's attachment fan - it is only the cards that
## come back down. The caption over each row shrinks by the same 20% (see
## PRIZE_LABEL_SCALE) so the block still reads as one object.
const PRIZE_SIZE     := Vector2(70.0, 97.0)
## ISSUE #272: 0.8 -> 1.0. #260 shrank these two captions with the cards; the
## retest wanted them back at the same size as every other heading on the board
## ("Opponent", "You", the attachment captions), which is what small_label gives
## at scale 1. Kept as a constant rather than deleted - it is the one dial if the
## prize headings ever need to differ from the rest again.
const PRIZE_LABEL_SCALE := 1.0
const PRIZE_GAP      := 4.0
## Smallest gap between the prize block and the edge of the screen.
const PRIZE_EDGE_PAD := 8.0
const PRIZE_COLUMNS  := 6   # ISSUE #260: one row, filled left to right
## How visible a taken prize's empty slot is.
const PRIZE_TAKEN_ALPHA := 0.45
const PRIZE_TOP_Y    := 132.0    # opponent's, in the right rail
## ISSUE #260 (retest): YOURS DROP TO THE FOOTER. At a fixed 690 the block sat
## mid-rail with 130px of dead field under it, while the opponent's was flush with
## the top of the screen - the two were not the mirror image they read as. Derived
## from the footer exactly like PILE_BOT_Y beside it, so a change to either the
## footer height or the card size keeps the gap.
const PRIZE_FOOT_GAP := 5.0
const PRIZE_BOT_Y    := 1080.0 - BOARD_BOT_H - PRIZE_FOOT_GAP - PRIZE_SIZE.y
## ISSUE #247: how far each side's whole column - active card, HP, damage
## counters, status icons, action rows and attachment stacks - moves OUTWARD from
## the centre line. It buys clearance from the bench rows above and below, whose
## attached-energy stacks fan up out of the outermost bench slot and were
## catching the edge of the action panel. TWEAKABLE.
## ISSUE #267: 10 -> 20. Part of the same pass that grew the actives inward; the
## whole column - card, HP blocks, status row, action panel and attachments -
## leans 10px further out on each side, which is where the extra 20px of centre
## clearance for the bigger cards comes from.
## ISSUE #277: 20 -> 25. "Move the player's active Pokemon and all of its details
## left 5 pixels and the opponent's right 5 pixels" is exactly this dial - it is
## the ONE number that moves the card, the HP readout, the status row, the action
## rows and the attachment stacks together, which is what "all of its details"
## means. Moving any of them on its own would break the straight edge #233 built.
const DUEL_SIDE_SHIFT := 25.0

## Benches: five slots, centred in the centre column.
## ISSUE #234: cards -10% (119x165 -> 107x148) and the horizontal gap -25%
## (29 -> 22), which buys back ~120px of board width. The bench slot no longer
## carries an HP NUMBER either - only the damage-counter blocks - so the row is
## shorter as well as narrower; see display_pokemon / BENCH_SLOT_SEP.
const BENCH_CARD     := Vector2(107.0, 148.0)
## ISSUE #234: ~2px between the bottom of the card and the top of the counters.
const BENCH_SLOT_SEP := 2
## ISSUE #234: the height a bench slot's counter row occupies under the card,
## used to size the empty slots so they line up with the real ones (#231).
const BENCH_COUNTER_H := 15.0
## ISSUE #213: how many slots a bench row always shows, filled or empty.
const BENCH_SLOTS    := 5
const BENCH_GAP      := 22
## ISSUE #234: the player's bench drops so its counters finish ~5px above the
## 162px footer (top edge y = 918). Slot content is card + BENCH_SLOT_SEP +
## counters; BENCH_ROW_H is that plus room for a bench power button.
const BENCH_ROW_H    := BENCH_CARD.y + 44.0
## ISSUE #259: +10.
const OPP_BENCH_Y    := 116.0
const PLAYER_BENCH_Y := 1080.0 - BOARD_BOT_H - 5.0 - BENCH_ROW_H

## The duel row. Seven columns; see the diagram above. You are on the LEFT.
## ISSUE #219: 470 -> 486. The opponent's bench damage counters hang 22px below
## their cards (dmg_bench_drop) and the top of the active card was landing on
## them. There is spare field under the actives, so the whole duel row drops 16px
## rather than the counters moving up into the card art.
const DUEL_MID_Y     := 486.0
## ISSUE #267: THE CARD IS BIGGER THAN ITS COLUMN, ON PURPOSE.
##
## +15% (230x319 -> 265x367), and it has to grow INWARD - the player's active to
## the RIGHT, the opponent's to the LEFT - so the info columns beside them, which
## hold the HP blocks and the attack rows, do not move at all. The seven-column
## arithmetic is therefore still done with the OLD width (ACTIVE_COL_W): if the
## column grew, the whole row would re-centre and each card would end up
## expanding OUTWARD across its own attack buttons, which is the opposite of what
## was asked. The extra 35px per side comes out of the 88px divider column and the
## widened DUEL_SIDE_SHIFT, leaving ~79px of clear centre for the turn divider.
const ACTIVE_COL_W   := 230.0
const ACTIVE_CARD    := Vector2(265.0, 367.0)
const DUEL_COL_ATTACH := 96.0
const DUEL_COL_INFO   := 322.0
## ISSUE #223: the attack rows are narrower than the info column they sit in, and
## ISSUE #216: they are pushed to the side of that column NEAREST the active
## Pokemon, which is what clears the attachment peek-stack out of their way.
## ISSUE #267: +10% (258 -> 284). This is the number the active HP counters and
## the status row are both sized against - see dmg_active_w in UITheme.METRICS
## and STATUS_ICON_H below - so all three read as one stack of the same width.
const ACTION_PANEL_W  := 284.0
## ISSUE #239: the attachment rows and their new captions, as offsets from the
## top of the active card. TWEAKABLE.
##   energy row sits level with the top of the card (was +10 - "up 10px")
##   tool row drops far enough that the ENERGY stack, which is a whole card tall,
##   cannot reach the TOOLS caption above it. +130 -> +160 rather than the +140 a
##   flat 10px would give, because the caption needs the clearance to exist.
const ATTACH_CAPTION_DY := 26.0     # how far above its row a caption sits
## ISSUE #264: the whole attachment stack drops by exactly one caption height, so
## the "Energy cards" HEADING - not the row of cards under it - is what lines up
## with the top of the active card. It was the row that lined up, which put the
## caption 26px above the card and left it floating against the field.
const ATTACH_ENERGY_DY := ATTACH_CAPTION_DY
const ATTACH_TOOL_DY   := 160.0 + ATTACH_CAPTION_DY
## ISSUE #239: attachment cards -10% (100x138 -> 90x124).
const ATTACH_CARD_SIZE := Vector2(90.0, 124.0)
## How wide an attachment caption may run before it ellipsises.
const ATTACH_CAPTION_W := 150.0
const DUEL_COL_DIVIDE := 88.0
const DUEL_GAP        := 10.5

## Top and bottom bar furniture.
const HAND_X         := 40.0
const PLAYER_HAND_Y  := 936.0
## ISSUE #244: the player's hand is CENTRED on the footer rather than starting at
## HAND_X. It was laid out as a 1300px box at x=40, so its middle sat at x=690 -
## 270px left of the screen centre, which is the "might as well be central".
const PLAYER_HAND_W  := 1300.0
const PLAYER_HAND_X  := (1920.0 - PLAYER_HAND_W) * 0.5
## The opponent's fan is centred on its own box the same way.
const OPP_HAND_W     := 420.0
const STADIUM_SIZE   := Vector2(48.0, 66.0)
## ISSUE #266: 1740 -> 1848, i.e. hard against the right end of the header
## (STADIUM_EDGE_PAD clear of the screen edge) instead of 132px short of it. Its
## caption is right-aligned in the 120px immediately to its left, so the pair
## still reads as one label-and-slot unit.
const STADIUM_EDGE_PAD := 24.0
const STADIUM_X      := 1920.0 - STADIUM_EDGE_PAD - STADIUM_SIZE.x
const STADIUM_Y      := 13.0

## The opponent's hand is a fan of face-down sleeves on the top bar, so it is
## smaller than yours.
## ISSUE #269: +20% (36x50 -> 43x60), then (retest) +10% -> 47x66, then (retest
## 2) +10% again -> 52x73. The last step is only possible because OPP_HAND_Y is
## DERIVED now rather than fixed at 20 - see below.
const OPP_HAND_CARD  := Vector2(52.0, 73.0)
## ISSUE #269 (retest 2): "equal distance from the top of the card to the top of
## the screen and from the bottom of the card to the bottom of the header." That
## is a derivation, not a number: whatever the card grows to, the header height
## left over is split evenly above and below it. A hardcoded 20 is what made
## every previous size step run out of room at the bottom of the 92px bar.
const OPP_HAND_Y     := (BOARD_TOP_H - OPP_HAND_CARD.y) * 0.5
## ISSUE #258 (retest): TOP LEFT, not top right. The fan is left-anchored inside
## its box and the box starts at HAND_X, so the first sleeve sits in the corner of
## the header and every card drawn after it is added to the RIGHT of the last -
## nothing already on screen ever moves. The right-hand corner belongs to the
## stadium slot and its caption (#266), which is why the fan was put there in the
## first place; it is out of their way entirely now.
const OPP_HAND_X     := HAND_X


## Lays the whole board out and swaps the old scrolling background for the new
## chrome. Called once from _ready.
func _build_board_layout() -> void:
	# The old background was a scrolling border texture behind everything. The
	# field and the two bars replace it; the match footer is the 162px variant,
	# which is the ONLY place in the game that uses it.
	var bg := get_node_or_null("match_background")
	if bg != null:
		remove_child(bg)
		bg.free()

	UIKit.add_field(self)
	_board_header = UIKit.add_header(self)
	_board_footer = UIKit.add_footer(self, true)
	# ISSUE #270: the footer's three layout slots must be un-pickable, or the two
	# EXPAND_FILL side ones lie across the middle of the hand. Fixed in
	# UIKit._bar_slot; asserted here because this is the screen it was breaking.

	# The turn chip is the primary turn indicator alongside the duel divider.
	_turn_chip_holder = _board_header.centre
	_refresh_turn_chip()

	_place_duel_row()
	_place_rails()
	_place_benches()
	_place_bars()
	_place_turn_divider()
	_style_selection_labels()
	_raise_bar_content()
	_style_trainer_screen()
	_fix_button_pick_order()


## ISSUE #246: SOMETHING WAS EATING THE RIGHT HALF OF THE ACTION BUTTON.
##
## Godot picks GUI input by walking siblings in REVERSE ORDER and ignores
## z_index entirely (the trap behind #186 and #201). BUTTONS sits fifth in the
## scene root while CARD_COLLECTIONS, ACTIVE_POKEMON, SELECTION_MODE and the
## chrome added at runtime all come after it - so any of those whose rect happens
## to overlap the footer swallows the press before the button ever sees it, and
## it only takes a partial overlap to kill exactly half a button.
##
## Two things fix it for good:
##   1. the bare grouping Controls (which exist only to namespace their children
##      and paint nothing) become MOUSE_FILTER_IGNORE, so they are skipped;
##   2. BUTTONS and the secondary button are moved to the END of the root's child
##      list, which puts them FIRST in the reverse walk. Nothing can cover them.
func _fix_button_pick_order() -> void:
	# ISSUE #246 (retest): THE TWO RETIRED FOOTER ROWS WERE THE NEW BLOCKER.
	#
	# main_screen_buttons_container and main_screen_attack_buttons_container are
	# HBoxContainers spanning x 64..1964 of the footer band. Their BUTTONS are
	# hidden (ATTACK / POWER / RETREAT retired in stage 7, End Turn reparented into
	# the bar) but the CONTAINERS are still visible, still MOUSE_FILTER_STOP, and
	# still 1900px wide - and moving BUTTONS last in the pick order put them in
	# FRONT of everything. That is exactly "something blocking the entire centre of
	# the footer": End Turn dead, and the hand clickable only above y 963 and below
	# y 1035, which is the band those two containers do not cover.
	#
	# A layout container that paints nothing should never be pickable, so they join
	# the grouping Controls below. Their own children keep MOUSE_FILTER_STOP.
	for path in ["CARD_COLLECTIONS", "CARD_COLLECTIONS/PLAYER", "CARD_COLLECTIONS/OPPONENT",
			"ACTIVE_POKEMON", "ACTIVE_POKEMON/PLAYER", "ACTIVE_POKEMON/OPPONENT",
			"SCREEN_LABELS", "SCREEN_LABELS/PLAYER", "SCREEN_LABELS/OPPONENT",
			"SCREEN_LABELS/MAIN_LABELS", "SELECTION_MODE",
			"BUTTONS", "BUTTONS/SELECTION_BUTTONS",
			"BUTTONS/main_screen_buttons_container",
			"BUTTONS/main_screen_attack_buttons_container"]:
		var node := get_node_or_null(path)
		if node is Control:
			(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ISSUE #217 (retest) / ISSUE #253: A BLOCKER THAT IS NOT LAST BLOCKS NOTHING.
	#
	# perform_attack() has always raised opponent_blocker on its very first line,
	# and that is meant to be the answer to "the attack button is spammable". It
	# never worked, for the same reason as everything else in this area: picking
	# walks siblings in REVERSE, and the blocker is a SCENE node while the action
	# panels are added at RUNTIME by _make_action_holder - so the panels sit after
	# it in the child list and were picked in front of the full-screen blocker that
	# was supposed to be covering them. Every click landed on the attack row.
	#
	# So the order is set explicitly here, once, last thing in the build. Read it
	# bottom-up, because that is the order picking sees it:
	#   opponent_blocker   - it is the opponent's turn: nothing at all is clickable
	#   animation_blocker  - a card is in flight: same
	#   trainer screen     - a card is being shown: same
	#   BUTTONS / cancel   - the footer pair, in front of the board (#246)
	#   buttons_only_blocker - board dead, footer live (it stops 100px short)
	# Anything added to this scene later that must block input goes at the END.
	var order: Array = [buttons_only_blocker, get_node_or_null("BUTTONS"), cancel_button,
		trainer_block_container, animation_blocker, opponent_blocker]
	for node in order:
		if node != null and is_instance_valid(node) and node.get_parent() == self:
			move_child(node, -1)


## ISSUE #213: THE HANDS AND THE MESSAGE BOX WERE UNDER THE CHROME BARS.
##
## Both hands live ON a bar — yours on the 162px footer, the opponent's on the
## 92px header — and the message box sits over the bottom of the board. The bars
## draw at Z_CHROME (200) and every one of these is a plain SIBLING of them, so
## all three were painted over: "hand can't be seen", "messagebox can't be seen".
##
## This is the same trap End Turn hit in stage 7, where the fix was to REPARENT
## into the bar. These four cannot be reparented — the hand containers are
## addressed by path all over the file and the message box is a scene node — so
## they are lifted above the bar's z band instead. Anything else added to a bar
## later needs one or the other.
func _raise_bar_content() -> void:
	var raised := {
		"hands": [player_hand_container, opponent_hand_container],
		"message box": [msgbox_container],
		"coin flip": [coin_container],
	}
	for what in raised:
		for node in raised[what]:
			if node != null and is_instance_valid(node) and node is CanvasItem:
				(node as CanvasItem).z_index = UIKit.Z_CHROME + 5


## ISSUE #214: the trainer-played screen is the FIELD, not a white sheet.
##
## trainer_block_screen_container is a bare ColorRect, which defaults to white,
## and it only covered y 166..922 — so playing a trainer flashed a white band
## across the middle of the board with the rest of the match showing round it.
## It is the full screen in the field colour now, so everything behind it is
## simply hidden and the card is read on the same background as every other
## screen. It stays BELOW the chrome bars (default z) so the header and footer
## still frame it.
func _style_trainer_screen() -> void:
	if trainer_block_container == null or not is_instance_valid(trainer_block_container):
		return
	# ISSUE #214 (retest): NOT A BACKGROUND AT ALL ANY MORE.
	#
	# Painting it the field colour still left a rectangle drawn over the board -
	# the right colour, but a sheet all the same, and it had to be the exact size
	# of the screen forever to stay invisible. What the card actually wants is the
	# field that is ALREADY there, with everything else taken off it. So the rect
	# is fully transparent now and exists purely to block clicks while a card is
	# up; set_card_showcase_visible() does the hiding.
	if trainer_block_container is ColorRect:
		(trainer_block_container as ColorRect).color = Color(0, 0, 0, 0)
	var old_top: float = trainer_block_container.offset_top
	trainer_block_container.offset_left   = 0.0
	trainer_block_container.offset_top    = 0.0
	trainer_block_container.offset_right  = 1920.0
	trainer_block_container.offset_bottom = 1080.0
	# The card container is positioned RELATIVE to the rect that just moved, so it
	# is pushed back down by the same amount and lands where it always did.
	if played_trainer_container != null and is_instance_valid(played_trainer_container):
		played_trainer_container.offset_top += old_top
		played_trainer_container.offset_bottom += old_top


## ISSUE #214 / #235: SHOW ONE CARD, ON THE BOARD'S OWN BACKGROUND.
##
## Every "hold this card up" moment - a Trainer being played, a card revealed to
## the opponent - used to hide a hand-written list of nodes (the hand and the
## four pile icons) and cover the rest with a sheet. Everything the list missed
## stayed on screen: the actives, both benches, the prizes, the HP readouts, the
## status icons and - the one that was reported - the attack rows beside the
## active Pokemon, which sat there over the card being played.
##
## THIS IS THE ONE PLACE the board is hidden for a card showcase. Any new caller
## uses it rather than growing another list, and any new board furniture is added
## here (or to _set_board_furniture_visible) rather than being forgotten again.
func set_card_showcase_visible(shown: bool) -> void:
	_card_showcase_active = shown
	var board_visible := not shown

	# The furniture set already covers the turn chip, the divider, the stadium,
	# the attachment captions, BOTH action panels and End Turn.
	_set_board_furniture_visible(board_visible)

	for node in [player_hand_container, opponent_hand_container,
			player_active_container, opponent_active_container,
			player_bench_container, opponent_bench_container,
			player_energy_container, opponent_energy_container,
			player_hp_container, opponent_hp_container,
			player_status_container, opponent_status_container,
			player_attached_cards_container, opponent_attached_cards_container,
			player_prize_container, opponent_prize_container,
			player_deck_icon, opponent_deck_icon,
			player_discard_icon, opponent_discard_icon]:
		if node != null and is_instance_valid(node):
			node.visible = board_visible

	for label_path in ["SCREEN_LABELS/OPPONENT/opponent_bench_cards_label",
			"SCREEN_LABELS/PLAYER/player_bench_cards_label",
			"SCREEN_LABELS/OPPONENT/opponent_prize_cards_label",
			"SCREEN_LABELS/PLAYER/player_prize_cards_label"]:
		var lbl := get_node_or_null(label_path)
		if lbl is Control:
			(lbl as Control).visible = board_visible

	trainer_block_container.visible = shown


## ISSUE #212: board furniture that must not show over a selection screen.
##
## The turn chip, the turn divider, the stadium slot and its caption, and both
## action panels are BOARD furniture. They were built once and left visible, so
## the mulligan screen — which shows the hand full-screen and hides the board —
## still had "Turn 1", the divider, the stadium placeholder and, once a Pokemon
## was placed, a full column of attack rows painted over it.
##
## Called from the same two places that hide and show the rest of the board:
## show_enlarged_array_selection_mode() and hide_selection_mode_display_main().
func _set_board_furniture_visible(shown: bool) -> void:
	for node in [_turn_chip, _turn_divider_label, _stadium_slot, _stadium_caption,
			_player_action_panel, _opp_action_panel]:
		if node != null and is_instance_valid(node):
			node.visible = shown
	for rule in _turn_divider_rules:
		if rule != null and is_instance_valid(rule):
			rule.visible = shown
	# ISSUE #239: the attachment captions belong to the board, so they go with it.
	for cap in _attach_captions:
		if cap != null and is_instance_valid(cap):
			cap.visible = shown
	# ISSUE #229: End Turn is REPARENTED INTO the footer bar, so it is no longer a
	# child of main_buttons_container and the wholesale
	# `main_buttons_container.visible = false` that hides the rest of the footer
	# never touched it. That is why it sat there, live, over the mulligan screen
	# and over every selection screen.
	if _end_turn_btn != null and is_instance_valid(_end_turn_btn):
		_end_turn_btn.visible = shown and not match_just_started_basic_pokemon_required \
			and not bench_setup_phase_active
	var stadium := get_node_or_null("CARD_COLLECTIONS/stadium_card")
	if stadium is Control:
		(stadium as Control).visible = shown and current_stadium_card != null


## The seven duel columns. Only the two actives and their attachment/info columns
## are placed here; what GOES in the info columns is stage 7's job.
func _place_duel_row() -> void:
	# ISSUE #267: ACTIVE_COL_W, not ACTIVE_CARD.x. The card is 15% wider than the
	# column it sits in and grows INWARD out of it; if the column grew with it the
	# whole row would re-centre and each card would expand outward across its own
	# attack buttons instead.
	var total := (DUEL_COL_ATTACH * 2.0 + DUEL_COL_INFO * 2.0 + ACTIVE_COL_W * 2.0
		+ DUEL_COL_DIVIDE + DUEL_GAP * 6.0)
	var x := (1920.0 - total) * 0.5

	# ISSUE #247: EVERY column on the player's side moves DUEL_SIDE_SHIFT left and
	# every column on the opponent's the same distance right. The bench rows sit
	# directly above and below this band and their attached-energy stacks fan
	# UPWARD out of the outermost slot, which was clipping the near edge of the
	# action panel; widening the middle is what clears it. The divider column stays
	# put, so the two sides simply lean away from each other.
	var you_attach_x := x - DUEL_SIDE_SHIFT
	x += DUEL_COL_ATTACH + DUEL_GAP
	var you_info_x := x - DUEL_SIDE_SHIFT
	x += DUEL_COL_INFO + DUEL_GAP
	var you_active_x := x - DUEL_SIDE_SHIFT
	x += ACTIVE_COL_W + DUEL_GAP
	_duel_divider_x = x
	x += DUEL_COL_DIVIDE + DUEL_GAP
	var opp_active_x := x + DUEL_SIDE_SHIFT
	x += ACTIVE_COL_W + DUEL_GAP
	var opp_info_x := x + DUEL_SIDE_SHIFT
	x += DUEL_COL_INFO + DUEL_GAP
	var opp_attach_x := x + DUEL_SIDE_SHIFT

	var active_y := DUEL_MID_Y - ACTIVE_CARD.y * 0.5

	# ISSUE #267: the extra width goes INWARD. Yours keeps its left edge and grows
	# right; theirs keeps its RIGHT edge (column x + old column width) and grows
	# left. Both therefore lean into the divider column, and neither one moves over
	# the info column that holds its own HP blocks and attack rows.
	var active_overhang := ACTIVE_CARD.x - ACTIVE_COL_W
	_set_rect(player_active_container, Vector2(you_active_x, active_y), ACTIVE_CARD)
	_set_rect(opponent_active_container,
		Vector2(opp_active_x - active_overhang, active_y), ACTIVE_CARD)

	# Attachments keep the existing peek-stack rendering (the mockup's two-group
	# whole-card layout was dropped); they just move to the outboard columns.
	# ISSUE #216: the player's stacks sat at the INNER edge of their attach column
	# (x + 36), so the peek-stack fanned right, straight across the attack rows in
	# the info column beside it. They start at the outer edge now, like the
	# opponent's do on their side.
	var you_attach_row_x := you_attach_x + 4.0
	var opp_attach_row_x := opp_attach_x + 18.0
	_set_rect($"ACTIVE_POKEMON/PLAYER/player_active_pokemon_energies",
		Vector2(you_attach_row_x, active_y + ATTACH_ENERGY_DY), Vector2(43, 28))
	_set_rect($"ACTIVE_POKEMON/PLAYER/player_active_pokemon_attached_cards",
		Vector2(you_attach_row_x, active_y + ATTACH_TOOL_DY), Vector2(43, 28))
	_set_rect($"ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_energies",
		Vector2(opp_attach_row_x, active_y + ATTACH_ENERGY_DY), Vector2(43, 28))
	_set_rect($"ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_attached_cards",
		Vector2(opp_attach_row_x, active_y + ATTACH_TOOL_DY), Vector2(43, 28))

	# ISSUE #239: the attachment rows get captions, like the prizes and the piles
	# already had. Without one a lone Rainbow Energy beside the active reads as a
	# loose card rather than as "what is attached to this Pokemon".
	_add_attach_caption("Energy cards", you_attach_row_x, active_y + ATTACH_ENERGY_DY, false)
	_add_attach_caption("Tools", you_attach_row_x, active_y + ATTACH_TOOL_DY, false)
	_add_attach_caption("Energy cards", opp_attach_row_x, active_y + ATTACH_ENERGY_DY, true)
	_add_attach_caption("Tools", opp_attach_row_x, active_y + ATTACH_TOOL_DY, true)

	# ISSUE #233: HP blocks and status chips share the ACTION PANEL's left edge
	# rather than the whole info column's, so the readout, the counters and the
	# attack rows form one straight edge beside the card instead of the numbers
	# floating 64px further out than the buttons under them.
	var you_col_x := you_info_x + DUEL_COL_INFO - ACTION_PANEL_W
	_set_rect($"ACTIVE_POKEMON/PLAYER/player_active_pokemon_hp_container",
		Vector2(you_col_x, active_y), Vector2(ACTION_PANEL_W, 60.0))
	_set_rect($"ACTIVE_POKEMON/PLAYER/player_active_pokemon_status_container",
		Vector2(you_col_x, active_y + 76.0), Vector2(ACTION_PANEL_W, 60.0))
	_set_rect($"ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_hp_container",
		Vector2(opp_info_x, active_y), Vector2(ACTION_PANEL_W, 60.0))
	_set_rect($"ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_status_container",
		Vector2(opp_info_x, active_y + 76.0), Vector2(ACTION_PANEL_W, 60.0))

	# The action panels sit under the HP and status rows, filling the rest of the
	# info column. They have room to grow downward and scroll past that.
	var panel_top := active_y + ACTION_PANEL_TOP
	# ISSUE #247: THE COLUMN WAS SHORTER THAN THE ROWS IT PROMISES TO SHOW.
	#
	# ACTION_MAX_ROWS was 5, and five 44px rows with four 6px gaps need 244px - but
	# the holder was 235 (card height minus the top inset plus a fixed overhang)
	# and clip_contents is on, so the bottom of the fifth row (usually Retreat) was
	# sliced off. The height is DERIVED from the row metrics now, so it can never
	# drift out of step with them again; the overhang is only a floor.
	var rows_h: float = ACTION_ROW_H * float(ACTION_MAX_ROWS) \
		+ float(ACTION_ROW_GAP) * float(ACTION_MAX_ROWS - 1) + ACTION_ROW_SLACK
	var panel_h := maxf(ACTIVE_CARD.y - ACTION_PANEL_TOP + ACTION_PANEL_OVERHANG, rows_h)
	# ISSUE #223 / #216: ACTION_PANEL_W wide, pinned to the side of the info column
	# that touches the active card — right for you, left for the opponent.
	_player_action_panel = _make_action_holder(
		Vector2(you_info_x + DUEL_COL_INFO - ACTION_PANEL_W, panel_top),
		Vector2(ACTION_PANEL_W, panel_h))
	_opp_action_panel = _make_action_holder(Vector2(opp_info_x, panel_top),
		Vector2(ACTION_PANEL_W, panel_h))


## ISSUE #239: one caption over an attachment row.
##
## The stacks fan AWAY from the active Pokemon - left for you, right for the
## opponent - so the caption is anchored at the row origin and grows the same
## way, or it would sit over the board on one side and off the screen on the
## other. Registered as board furniture so a selection screen hides it (#212).
func _add_attach_caption(text: String, row_x: float, row_y: float, is_opponent: bool) -> void:
	var lbl := Label.new()
	lbl.theme = null
	UIKit.set_label(lbl, "small_label", text, "field_mute")
	lbl.size = Vector2(ATTACH_CAPTION_W, 22.0)
	lbl.position = Vector2(row_x if is_opponent else row_x + ATTACH_CARD_SIZE.x - ATTACH_CAPTION_W,
		row_y - ATTACH_CAPTION_DY)
	lbl.horizontal_alignment = (HORIZONTAL_ALIGNMENT_LEFT if is_opponent
		else HORIZONTAL_ALIGNMENT_RIGHT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	_attach_captions.append(lbl)


## Deck, discard and prizes, in 180-degree rotational symmetry.
func _place_rails() -> void:
	var pile_row_w := PILE_SIZE.x * 2.0 + PILE_GAP
	var left_pile_x := LEFT_RAIL_X + (RAIL_W - pile_row_w) * 0.5
	var right_pile_x := RIGHT_RAIL_X + (RAIL_W - pile_row_w) * 0.5

	# OPPONENT's piles, top LEFT.
	_set_rect(opponent_deck_icon, Vector2(left_pile_x, PILE_TOP_Y), PILE_SIZE)
	_set_rect(opponent_discard_icon,
		Vector2(left_pile_x + PILE_SIZE.x + PILE_GAP, PILE_TOP_Y), PILE_SIZE)
	# YOURS, bottom RIGHT - diagonally opposite, not mirrored.
	_set_rect(player_deck_icon, Vector2(right_pile_x, PILE_BOT_Y), PILE_SIZE)
	_set_rect(player_discard_icon,
		Vector2(right_pile_x + PILE_SIZE.x + PILE_GAP, PILE_BOT_Y), PILE_SIZE)

	# 3 x 2, not a row of six. The containers are GridContainers for this reason;
	# as HBoxContainers they laid all six out in one 304px line and burst the rail.
	for pc in [opponent_prize_container, player_prize_container]:
		if pc is GridContainer:
			(pc as GridContainer).columns = PRIZE_COLUMNS
			(pc as GridContainer).add_theme_constant_override("h_separation", int(PRIZE_GAP))
			(pc as GridContainer).add_theme_constant_override("v_separation", int(PRIZE_GAP))

	var prize_row_w := PRIZE_SIZE.x * float(PRIZE_COLUMNS) + PRIZE_GAP * float(PRIZE_COLUMNS - 1)
	# ISSUE #260: ONE row of six, so the height is one card, not two plus a gap.
	var prize_h := PRIZE_SIZE.y
	# OPPONENT's prizes top RIGHT, yours bottom LEFT.
	# ISSUE #238: at +40% the block is wider than the 180px rail, so centring it
	# on the rail alone would push it off the screen. It is centred and then
	# clamped to PRIZE_EDGE_PAD, which lets it overhang INWARD into the empty band
	# beside the rail instead.
	var opp_prize_x: float = minf(RIGHT_RAIL_X + (RAIL_W - prize_row_w) * 0.5,
		1920.0 - PRIZE_EDGE_PAD - prize_row_w)
	var you_prize_x: float = maxf(LEFT_RAIL_X + (RAIL_W - prize_row_w) * 0.5, PRIZE_EDGE_PAD)
	_set_rect(opponent_prize_container, Vector2(opp_prize_x, PRIZE_TOP_Y),
		Vector2(prize_row_w, prize_h))
	_set_rect(player_prize_container, Vector2(you_prize_x, PRIZE_BOT_Y),
		Vector2(prize_row_w, prize_h))

	# The four rail captions. ISSUE #260: the two PRIZE captions span the six-card
	# row rather than the 180px rail, which the row is three times wider than.
	# ISSUE #260 (retest): the two prize captions take PRIZE_LABEL_SCALE, so the
	# heading shrinks by the same 20% the cards did and the block stays one object.
	_place_rail_label($"SCREEN_LABELS/OPPONENT/opponent_prize_cards_label",
		"Opponent's prizes", opp_prize_x, PRIZE_TOP_Y - 26.0, prize_row_w,
		PRIZE_LABEL_SCALE)   # ISSUE #251
	_place_rail_label($"SCREEN_LABELS/PLAYER/player_prize_cards_label",
		"Your prizes", you_prize_x, PRIZE_BOT_Y - 26.0, prize_row_w, PRIZE_LABEL_SCALE)
	_place_rail_label($"SCREEN_LABELS/OPPONENT/opponent_bench_cards_label",
		"Opponent", LEFT_RAIL_X, PILE_TOP_Y - 26.0)
	_place_rail_label($"SCREEN_LABELS/PLAYER/player_bench_cards_label",
		"You", RIGHT_RAIL_X, PILE_BOT_Y - 26.0)


func _place_rail_label(lbl: Label, text: String, x: float, y: float, w: float = RAIL_W,
		font_scale: float = 1.0) -> void:
	if lbl == null:
		return
	lbl.theme = null
	UIKit.set_label(lbl, "small_label", text, "field_mute")
	# ISSUE #260: a caption that labels a resized block scales with it.
	if not is_equal_approx(font_scale, 1.0):
		lbl.add_theme_font_size_override("font_size",
			int(round(float(UITheme.size("small_label")) * font_scale)))
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(w, 22.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Five slots each, centred, opponent above and you below.
func _place_benches() -> void:
	var row_w := BENCH_CARD.x * 5.0 + float(BENCH_GAP) * 4.0
	var x := (1920.0 - row_w) * 0.5
	for c in [opponent_bench_container, player_bench_container]:
		if c is HBoxContainer:
			(c as HBoxContainer).add_theme_constant_override("separation", BENCH_GAP)
			(c as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_set_rect(opponent_bench_container, Vector2(x, OPP_BENCH_Y),
		Vector2(row_w, BENCH_ROW_H))
	_set_rect(player_bench_container, Vector2(x, PLAYER_BENCH_Y),
		Vector2(row_w, BENCH_ROW_H))


## Hands, turn chip and stadium, on the two chrome bars.
func _place_bars() -> void:
	# ISSUE #244: the hand is CENTRED on the footer, and the row inside it is
	# centred too. Both halves are needed - a centred box whose HBox still starts
	# at its left edge only moves the problem.
	# ISSUE #258 (retest): the opponent's fan sits in the TOP LEFT corner of the
	# header and is left-anchored inside its box, so the first sleeve never moves
	# and each new card is added to the RIGHT of the last one. Centring it (which
	# is right for YOUR hand, where the whole row is the object) meant every
	# existing card shuffled sideways whenever they drew.
	# ISSUE #269 (retest 2): the box is exactly one card tall, so the derived
	# OPP_HAND_Y really does leave the same gap above the fan as below it. At a
	# fixed 56 the box was shorter than the 73px card and the "centring" was a lie.
	_set_rect(opponent_hand_container, Vector2(OPP_HAND_X, OPP_HAND_Y),
		Vector2(OPP_HAND_W, OPP_HAND_CARD.y))
	_set_rect(player_hand_container, Vector2(PLAYER_HAND_X, PLAYER_HAND_Y),
		Vector2(PLAYER_HAND_W, 140.0))
	if player_hand_container is HBoxContainer:
		(player_hand_container as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	if opponent_hand_container is HBoxContainer:
		(opponent_hand_container as HBoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN

	# The stadium gets a caption and a slot in the top right, which is the one
	# piece of empty chrome on the board. Clicking it is stage 7.
	# An empty slot behind the stadium, so the corner reads as a place a card goes
	# rather than as blank chrome when none is in play.
	var stadium_slot := UIKit.make_slot(STADIUM_SIZE)
	stadium_slot.position = Vector2(STADIUM_X, STADIUM_Y)
	stadium_slot.z_index = UIKit.Z_CHROME + 1
	stadium_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stadium_slot)
	_stadium_slot = stadium_slot   # ISSUE #212

	var stadium := get_node_or_null("CARD_COLLECTIONS/stadium_card")
	if stadium is Control:
		# Clickable: at 48x66 the card is unreadable, so pressing it opens a full
		# view with any activatable ability as a button — the same shape the bench
		# power buttons use.
		(stadium as Control).mouse_filter = Control.MOUSE_FILTER_STOP
		(stadium as Control).gui_input.connect(_on_stadium_slot_input)
		# The scene left scale = (0.4, 0.4) on this node from when it sat mid-board
		# at full card size. Sized properly now, so the shrink has to go.
		(stadium as Control).scale = Vector2.ONE
		_set_rect(stadium as Control, Vector2(STADIUM_X, STADIUM_Y), STADIUM_SIZE)
		(stadium as Control).z_index = UIKit.Z_CHROME + 1

	var caption := Label.new()
	UIKit.set_label(caption, "small_label", "Stadium", "chrome_fg")
	caption.position = Vector2(STADIUM_X - 130.0, STADIUM_Y + 20.0)
	caption.size = Vector2(120.0, 22.0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.z_index = UIKit.Z_CHROME + 1
	add_child(caption)
	_stadium_caption = caption   # ISSUE #212
	print("ISSUE #269 FIX ACTIVE: opponent hand cards ", OPP_HAND_CARD,
		" at y ", OPP_HAND_Y, " - header ", BOARD_TOP_H,
		", so ", OPP_HAND_Y, "px clear above and below")

	# ATTACK, POWER and RETREAT are gone from the footer — they are rows on the
	# Pokemon now. Only End Turn is left, and it is REPARENTED INTO the footer bar
	# rather than floated over it: the bar draws at Z_CHROME, and a sibling laid on
	# top of it is one z-order slip away from being invisible, which is exactly
	# what happened on the first pass.
	# DO NOT ZERO THIS NODE. The selection confirm button (card_action_button) and
	# the attack-mode row are positioned by NEGATIVE offsets relative to BUTTONS,
	# which the scene parks at (1907, 961). Zeroing it put the confirm button at
	# x = -1186 - off the left edge - which is why the mulligan screen had nothing
	# to press. Its authored position already lands those children inside the new
	# 162px footer band, so it is left exactly where it is.
	#
	# It does need to draw ABOVE the footer bar though: the bar is at Z_CHROME and
	# these are siblings, the same trap End Turn hit.
	var buttons := get_node_or_null("BUTTONS")
	if buttons is Control:
		(buttons as Control).z_index = UIKit.Z_CHROME + 10
		# ISSUE #211: the selection buttons (Place as active / Place on bench /
		# Done) were centred on y=1022, 23px below the 162px footer's midline at
		# y=999, so they sat low in the bar. Only the VERTICAL offsets move: the
		# node's x is what lands its negative-offset children on screen at all, and
		# zeroing it is what broke the mulligan screen the first time round.
		(buttons as Control).offset_top -= FOOTER_BUTTON_RAISE
		(buttons as Control).offset_bottom -= FOOTER_BUTTON_RAISE
	if main_buttons_container != null:
		for retired in ["button_main_attack", "button_main_power", "button_main_retreat"]:
			var b := main_buttons_container.get_node_or_null(retired)
			if b != null:
				b.visible = false
		# The selection buttons keep their geometry but take the new skin.
		if action_button is Button:
			UIKit.style_button(action_button as Button, "primary")
		if cancel_button is Button:
			(cancel_button as Button).z_index = UIKit.Z_CHROME + 10
			UIKit.style_button(cancel_button as Button, "secondary")
			# ISSUE #230: the secondary button (Done / Cancel) is NOT a child of
			# BUTTONS - it is a root-level node with its own bottom anchor - so the
			# FOOTER_BUTTON_RAISE that lifted the primary button onto the footer's
			# midline in #211 never reached it, and the pair ended up 23px out of
			# line with each other. Same lift, applied to the node that missed it.
			(cancel_button as Button).offset_top -= FOOTER_BUTTON_RAISE
			(cancel_button as Button).offset_bottom -= FOOTER_BUTTON_RAISE
		var attack_cancel := attack_buttons_container.get_node_or_null("cancel_attack_mode_button")
		if attack_cancel is Button:
			UIKit.style_button(attack_cancel as Button, "secondary")

		var end_turn := main_buttons_container.get_node_or_null("button_main_endturn")
		if end_turn is Button:
			_end_turn_btn = end_turn as Button
			_end_turn_btn.text = "End turn"
			UIKit.adopt_button(_end_turn_btn, _board_footer.right, "primary")


## The big instruction and its hint, used by every selection and target screen.
##
## They were authored at y 17 and y 94 - under the 92px header bar now - and were
## still in the Kenney face at font 61. Moved below the bar and restyled as a
## title with a subtitle beneath it.
func _style_selection_labels() -> void:
	if header_label != null and is_instance_valid(header_label):
		header_label.theme = null
		UIKit.style_label(header_label, "title", "field_fg")
		header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_rect(header_label, Vector2(0.0, SELECT_TITLE_Y), Vector2(1920.0, 44.0))
		header_label.z_index = UIKit.Z_CHROME + 5
	if hint_label != null and is_instance_valid(hint_label):
		hint_label.theme = null
		UIKit.style_label(hint_label, "subtitle", "field_mute")
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_rect(hint_label, Vector2(0.0, SELECT_HINT_Y), Vector2(1920.0, 34.0))
		hint_label.z_index = UIKit.Z_CHROME + 5


## The thin rule and label that splits the field between the two actives.
func _place_turn_divider() -> void:
	var mid_x := _duel_divider_x + DUEL_COL_DIVIDE * 0.5
	var half := ACTIVE_CARD.y * 0.5

	# ISSUE #221: SHORTER, THICKER, CLOSER. They were 2x76 rules starting 46px
	# clear of the card, which read as two long hairlines with a caption stranded
	# between them rather than as a rule broken by a label.
	for dy in [-DIVIDER_RULE_H - DIVIDER_RULE_GAP, DIVIDER_RULE_GAP]:
		var rule := ColorRect.new()
		rule.color = UITheme.col("line")
		rule.position = Vector2(mid_x - DIVIDER_RULE_W * 0.5, DUEL_MID_Y + dy)
		rule.size = Vector2(DIVIDER_RULE_W, DIVIDER_RULE_H)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rule.z_index = DUEL_DIVIDER_Z
		add_child(rule)
		_turn_divider_rules.append(rule)   # ISSUE #212

	_turn_divider_label = Label.new()
	# ISSUE #252: the label is two lines now ("Your" over "Turn"), so it needs the
	# height for a second line - a 60px box with 30px of lead clipped the descender
	# off the first line the moment the text wrapped.
	_turn_divider_label.position = Vector2(mid_x - DUEL_COL_DIVIDE * 0.5, DUEL_MID_Y - 34.0)
	_turn_divider_label.size = Vector2(DUEL_COL_DIVIDE, 68.0)
	_turn_divider_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_divider_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_divider_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	UIKit.set_label(_turn_divider_label, "small_label", TURN_LABEL_YOURS, "accent")
	_turn_divider_label.z_index = DUEL_DIVIDER_Z
	add_child(_turn_divider_label)
	_refresh_turn_divider()


## Repaints the divider label for whoever is to move.
func _refresh_turn_divider() -> void:
	if _turn_divider_label == null or not is_instance_valid(_turn_divider_label):
		return
	var theirs := opponents_turn_active
	UIKit.set_label(_turn_divider_label, "small_label",
		TURN_LABEL_THEIRS if theirs else TURN_LABEL_YOURS,
		"accent_2" if theirs else "accent")


## The "Turn 6" chip in the top bar.
func _refresh_turn_chip() -> void:
	if _turn_chip_holder == null or not is_instance_valid(_turn_chip_holder):
		return
	if _turn_chip != null and is_instance_valid(_turn_chip):
		_turn_chip.queue_free()
	_turn_chip = UIKit.make_chip("Turn %d" % maxi(turn_number, 1), "on_chrome")
	# ISSUE #212: a rebuilt chip must not reappear over a selection screen.
	_turn_chip.visible = not card_selection_mode_enabled
	_turn_chip_holder.add_child(_turn_chip)


## Opens the stadium reader. Called from the top-right slot.
func _on_stadium_slot_input(event: InputEvent) -> void:
	if not UIInput.is_click(event):
		return
	if current_stadium_card == null or _stadium_overlay != null:
		return
	_show_stadium_detail()


## The stadium at a readable size, with its activatable ability (if any) as a
## button above it.
##
## At 48x66 in the header the card is a coloured stamp — legible enough to say
## "a stadium is in play", nowhere near enough to read its rules text. This is
## where you read it.
func _show_stadium_detail() -> void:
	_stadium_overlay = Control.new()
	_stadium_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stadium_overlay.z_index = STADIUM_OVERLAY_Z
	add_child(_stadium_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if UIInput.is_click(e): _close_stadium_detail())
	_stadium_overlay.add_child(dim)

	var card := TextureRect.new()
	card.texture = get_card_texture(current_stadium_card)
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.size = STADIUM_DETAIL_SIZE
	card.position = Vector2((1920.0 - STADIUM_DETAIL_SIZE.x) * 0.5, STADIUM_DETAIL_Y)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stadium_overlay.add_child(card)

	# Any activatable ability, in the same accent_2 row style the bench uses.
	var y := STADIUM_DETAIL_Y - 70.0
	if powers_and_bodies != null:
		for entry in powers_and_bodies.printed_powers_for(current_stadium_card):
			var ability: Dictionary = entry["ability"]
			var btn := _make_bench_power_button(current_stadium_card, entry,
				Vector2(STADIUM_DETAIL_SIZE.x, 0.0))
			btn.custom_minimum_size = Vector2(STADIUM_DETAIL_SIZE.x, 48.0)
			btn.position = Vector2(card.position.x, y)
			btn.size = Vector2(STADIUM_DETAIL_SIZE.x, 48.0)
			btn.pressed.connect(_close_stadium_detail)
			_stadium_overlay.add_child(btn)
			y -= 56.0

	var close := UIKit.make_footer_button("Close", "secondary")
	close.position = Vector2((1920.0 - UIKit.FOOTER_BTN_W) * 0.5,
		STADIUM_DETAIL_Y + STADIUM_DETAIL_SIZE.y + 24.0)
	close.pressed.connect(_close_stadium_detail)
	_stadium_overlay.add_child(close)


func _close_stadium_detail() -> void:
	if _stadium_overlay != null and is_instance_valid(_stadium_overlay):
		_stadium_overlay.queue_free()
	_stadium_overlay = null


## A free-layout Control the action rows are built into.
func _make_action_holder(pos: Vector2, holder_size: Vector2) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.size = holder_size
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(holder)
	return holder


## Absolute place-and-size for a board node. Every board node is a free-layout
## child, so anchors are cleared on the way through.
func _set_rect(node: Control, pos: Vector2, node_size: Vector2) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.position = pos
	node.size = node_size
	node.custom_minimum_size = Vector2.ZERO



# ============================================================
# ACTION PANEL (UI overhaul, stage 7)
# ============================================================
# Attacks, Poke-Powers and Retreat live ON the Pokemon now, as a column of rows
# in the info panel beside each active. The footer's ATTACK / POWER / RETREAT
# buttons are gone; only End Turn is left.
#
# Row order, top to bottom:
#   Poke-Power   accent_2 border, transparent fill. Only if the card has one.
#   Attack       cost pips, name, damage. One row each.
#   Retreat      DASHED border, so it never reads as a fourth attack.
#
# WHY RETREAT BELONGS HERE: it costs energy, it is paid by the active Pokemon,
# and it competes with attacking for the same turn. Putting it in the panel makes
# that competition visible and gives it somewhere to show its cost as pips, which
# a footer button never could.
#
# THE OPPONENT GETS THE SAME PANEL, always dimmed and never interactive. It is
# there so you can read the threat before committing your turn.
#
# ── THE LIST HAS NO UPPER BOUND ──────────────────────────────
# A card's attacks are not the attacks it was printed with: every Technical
# Machine adds or replaces one, Meteor Falls and gym1 Recall add the whole
# pre-evolution chain, and ex12 Versatile adds the attacks of every Pokemon in
# play. Past ACTION_MAX_ROWS the column becomes a ScrollContainer rather than
# growing into the bench.
# ============================================================

## Rows are as wide as the info column so nearly every attack name fits on one
## line — the whole point of moving them off a crowded horizontal footer.
## ISSUE #247: -5% (46 -> 44). ISSUE #267 (retest): -5% again (44 -> 41.8), which
## is what buys the SIXTH row below - six 41.8px rows with five 6px gaps need
## 284.8px against the five-row 254, and the holder is derived from these numbers
## so it grew to hold them without anything else moving.
const ACTION_ROW_H     := 41.8
## ISSUE #247: how far the rows pull back from the side the scrollbar appears on
## once there are more than ACTION_MAX_ROWS of them - the card side for each
## player. Only applied when the column actually scrolls.
const ACTION_SCROLL_PAD := 4
## ISSUE #247: breathing room under the last row inside the holder.
const ACTION_ROW_SLACK := 4.0
const ACTION_ROW_GAP   := 6
const ACTION_PAD       := 10.0
const ACTION_PIP       := 20.0
const ACTION_PIP_GAP   := 3.0
const ACTION_NAME_FONT := 16
const ACTION_DMG_FONT  := 19
## Beyond this the column scrolls instead of running into the bench.
## ISSUE #267 (retest): 5 -> 6. Five was one short of the common worst case - four
## attacks plus a Poke-Power plus Retreat - so a scrollbar appeared on Pokemon
## that are not unusual at all. Six covers effectively all real play; the
## ScrollContainer is still there for a Technical Machine or ex12 Versatile
## stacking extra attacks on top of that.
const ACTION_MAX_ROWS  := 6
## Where the action column starts inside the info column, measured from the top
## of the active card — below the name, HP and status rows.
const ACTION_PANEL_TOP := 140.0
## How far past the bottom of the active card the column may run before it
## scrolls. Kept clear of the bench rows above and below.
const ACTION_PANEL_OVERHANG := 56.0

## The power button above a benched Pokemon.
const BENCH_POWER_H    := 26.0
const BENCH_POWER_FONT := 13

## The stadium reader opened by clicking the header slot.
const STADIUM_DETAIL_SIZE := Vector2(400.0, 550.0)
const STADIUM_DETAIL_Y    := 210.0
const STADIUM_OVERLAY_Z   := 300

## The selection screens' title and hint, just below the header bar.
## ISSUE #211: how far the BUTTONS node lifts so its children centre on the
## match footer's midline. Measured: children centre on 1022, the bar's middle is
## at 918 + 162/2 = 999.
const FOOTER_BUTTON_RAISE := 23.0

const SELECT_TITLE_Y := 104.0
const SELECT_HINT_Y  := 150.0

## ISSUE #237: the small selection row's horizontal box, in the container's own
## anchor space. Its parent SELECTION_MODE is the usual 40x40 scene stub, so its
## centre anchor resolves to x = 20 - hence -20 and 1900 for a 0..1920 box.
const SELECT_ROW_LEFT  := -20.0
const SELECT_ROW_RIGHT := 1900.0
## The widest a row may be before its cards are shrunk to fit.
const SELECT_ROW_MAX_W := 1860.0
## Slack left for the focus Pokemon's 1.05x blow-up and its 25px spacer.
const SELECT_FOCUS_EXTRA := 60.0

## The turn divider is board furniture: above the field, BELOW every card, so a
## selection row laid over the board does not have it showing through.
const DUEL_DIVIDER_Z := -1

## ISSUE #221: the two rules that bracket the YOUR TURN / THEIR TURN label.
## TWEAKABLE — width is the thickness, height the length, gap the clearance from
## the label's own box.
const DIVIDER_RULE_W   := 5.0
const DIVIDER_RULE_H   := 34.0
const DIVIDER_RULE_GAP := 32.0

## ISSUE #251 / #252: "Their turn" became "Opponent's turn" (the board says
## "Opponent" everywhere else, so "their" was the odd one out), and both are
## broken over TWO LINES with the possessive on top - which is also the only way
## "Opponent's turn" fits an 88px divider column at all.
## ISSUE #278: the possessive goes - "Opponent turn", not "Opponent's turn".
const TURN_LABEL_YOURS  := "Your\nturn"
const TURN_LABEL_THEIRS := "Opponent\nturn"


## The little power button that sits over a benched Pokemon.
##
## Shows the power's NAME, not the word "power": with five of them on screen the
## player is choosing between abilities, not discovering that one exists.
func _make_bench_power_button(mon: card_object, entry: Dictionary,
		card_size: Vector2) -> Button:
	var ability: Dictionary = entry["ability"]
	var usable: bool = powers_and_bodies.is_power_usable(mon, ability) \
		and not opponents_turn_active

	var btn := Button.new()
	btn.text = String(ability.get("name", "Power"))
	btn.custom_minimum_size = Vector2(card_size.x, BENCH_POWER_H)
	btn.disabled = not usable
	btn.focus_mode = Control.FOCUS_NONE
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.clip_text = true
	btn.add_theme_font_override("font", UITheme.font("attack_name"))
	btn.add_theme_font_size_override("font_size", BENCH_POWER_FONT)
	btn.add_theme_color_override("font_color", UITheme.col("accent_2"))
	btn.add_theme_color_override("font_disabled_color",
		UITheme.col_a("accent_2", 0.35))

	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UITheme.col_a("accent_2", 0.16 if (state == "hover" and usable) else 0.06)
		sb.set_border_width_all(1)
		sb.border_color = UITheme.col_a("accent_2", 0.85 if usable else 0.30)
		sb.set_corner_radius_all(6)
		sb.anti_aliasing = true
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if usable:
		btn.pressed.connect(func(): powers_and_bodies.activate_power(mon, ability))
	return btn


## ISSUE #217: TRUE only when it is the player's turn and no other screen owns
## the board. Every action row on the player's panel goes through this first.
##
## The list mirrors update_main_screen_buttons()'s `should_disable` — the End Turn
## button and the action rows must never disagree about whose turn it is — plus
## is_pokemon_selection_mode_active(), which covers the target-picking modes.
func _player_can_act_now() -> bool:
	if game_is_over or opponents_turn_active:
		return false
	if match_just_started_basic_pokemon_required or bench_setup_phase_active:
		return false
	if card_selection_mode_enabled or power_menu_active:
		return false
	if trainer_card_mode_active or trainer_discard_selection_active \
			or trainer_deck_search_active or yes_no_prompt_active:
		return false
	if prize_card_selection_active or knockout_bench_selection_active:
		return false
	if is_pokemon_selection_mode_active():
		return false
	return true


## ISSUE #217: _player_can_act_now() plus the rules specific to ATTACKING.
##
## Turn 1 cannot attack, a Paralyzed or Asleep Pokemon cannot attack, and an
## attack already made this turn ends the turn — pressing a second one used to
## deal its damage anyway, which is the "keep hitting the attack button" the user
## saw. show_attack_buttons() enforces the first three with messages; this is the
## silent version the rows disable themselves with.
func _player_can_attack_now() -> bool:
	if not _player_can_act_now():
		return false
	if turn_number <= 1:
		return false
	if player_attacked_this_turn:
		return false
	if player_active_pokemon == null:
		return false
	return player_active_pokemon.special_condition not in ["Paralyzed", "Asleep"]


## ISSUE #265: why THIS attack row is dead, in the order the player would ask.
##
## An empty string means "say nothing": the board is not the player's to act on
## right now (the opponent's turn, a selection screen, a message box open), and a
## popup explaining that on every stray click would be noise rather than help.
##
## The wording matches show_attack_buttons() line for line, so the same rule
## reads the same whichever route the player reaches it by.
func _attack_row_reason(mon: card_object, attack: Dictionary, attack_name: String) -> String:
	if not _player_can_act_now():
		return ""
	# Card-specific first. An attack shut off by an effect is a different sentence
	# from one the Pokemon simply cannot pay for.
	if is_attack_disabled(mon, attack_name):
		return attack_name.to_upper() + " is disabled and can't be used!"
	if not check_attack_requirements(attack, mon):
		return "Energy requirements not met to use " + attack_name.to_upper() + "!"
	if turn_number <= 1:
		return "You cannot attack on the first turn!"
	if player_attacked_this_turn:
		return "You have already attacked this turn!"
	if mon.special_condition == "Paralyzed":
		return mon.metadata.get("name", "").to_upper() + " is Paralyzed and cannot attack!"
	if mon.special_condition == "Asleep":
		return mon.metadata.get("name", "").to_upper() + " is Asleep and cannot attack!"
	return ""


## Rebuilds one side's action panel. Called from display_pokemon(), so it
## refreshes on every board change without a second hook.
func _build_action_panel(is_opponent: bool) -> void:
	var holder: Control = _opp_action_panel if is_opponent else _player_action_panel
	if holder == null or not is_instance_valid(holder):
		return
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()

	var mon: card_object = opponent_active_pokemon if is_opponent else player_active_pokemon
	if mon == null:
		return

	var rows: Array = []

	# ── Powers ──
	if powers_and_bodies != null:
		for entry in powers_and_bodies.printed_powers_for(mon):
			var ability: Dictionary = entry["ability"]
			var live: bool = (not is_opponent) and powers_and_bodies.is_power_usable(mon, ability)
			rows.append({
				"kind": "power",
				"text": String(ability.get("name", "Power")),
				"enabled": live,
				"action": func(): powers_and_bodies.activate_power(mon, ability),
			})

	# ── Attacks ──
	var attacks := get_attacks_for_card(mon)
	for i in attacks.size():
		var attack: Dictionary = attacks[i]
		var attack_name: String = attack.get("name", "Attack")
		var usable := false
		var why := ""
		if not is_opponent:
			# ISSUE #217: _player_can_attack_now() is the WHOLE gate. The row used to
			# check only "is this attack legal for this Pokemon", which meant it stayed
			# live during the opponent's turn, during every selection screen and after
			# the player had already attacked - so it could be pressed over and over.
			usable = (_player_can_attack_now()
				and (not is_attack_disabled(mon, attack_name))
				and check_attack_requirements(attack, mon))
			# ISSUE #265: and if it is dead, WHY it is dead.
			if not usable:
				why = _attack_row_reason(mon, attack, attack_name)
		rows.append({
			"kind": "attack",
			"text": attack_name,
			"attack": attack,
			"enabled": usable,
			"disabled_reason": why,
			"action": func(): perform_attack(i),
		})

	# ── Retreat ── the opponent's panel has none: it is not your decision.
	if not is_opponent:
		# ISSUE #265: THE ROW IS GATED ON THE REAL RULE, NOT A SUBSET OF IT.
		#
		# It used to test three of can_retreat()'s eleven blockers, so a Pokemon that
		# was Asleep, short of Energy, held by Boost Energy or facing a Snorlax still
		# had a live-looking Retreat row that only failed once it was pressed.
		# can_retreat() IS the rule, so the row asks it - and the same call supplies
		# the sentence the player gets if they press it anyway.
		var retreat_ok := _player_can_act_now()
		var retreat_why := ""
		if retreat_ok:
			var rc := can_retreat(false)
			retreat_ok = bool(rc["can_retreat"])
			if not retreat_ok:
				retreat_why = String(rc["reason"])
		rows.append({
			"kind": "retreat",
			"text": "Retreat",
			"enabled": retreat_ok,
			"disabled_reason": retreat_why,
			"action": start_retreat,
		})

	_render_action_rows(holder, rows, is_opponent)


## Lays the rows out, wrapping them in a scroller once there are too many to fit.
func _render_action_rows(holder: Control, rows: Array, is_opponent: bool) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ACTION_ROW_GAP)

	if rows.size() > ACTION_MAX_ROWS:
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		holder.add_child(scroll)
		# ISSUE #247: a vertical scrollbar is drawn INSIDE the ScrollContainer, at
		# its right edge - which on the player's side is the edge facing the active
		# card, so it landed on top of the attack rows. The rows pull back
		# ACTION_SCROLL_PAD from whichever edge that is for this side.
		var pad := MarginContainer.new()
		pad.set_anchors_preset(Control.PRESET_FULL_RECT)
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_theme_constant_override(
			"margin_left" if is_opponent else "margin_right", ACTION_SCROLL_PAD)
		scroll.add_child(pad)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_child(col)
	else:
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(col)

	for r in rows:
		col.add_child(_make_action_row(r, is_opponent))


## One row. A Button so it keeps focus, hover and the press-to-fire behaviour
## every other button in the game has.
func _make_action_row(row: Dictionary, is_opponent: bool) -> Button:
	var kind: String = row["kind"]
	var enabled: bool = bool(row["enabled"]) and not is_opponent

	var btn := Button.new()
	btn.text = ""
	btn.custom_minimum_size = Vector2(0, ACTION_ROW_H)
	btn.disabled = not enabled
	btn.focus_mode = Control.FOCUS_NONE
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	btn.add_theme_stylebox_override("normal", _action_row_box(kind, enabled, false))
	btn.add_theme_stylebox_override("hover", _action_row_box(kind, enabled, true))
	btn.add_theme_stylebox_override("pressed", _action_row_box(kind, enabled, true))
	btn.add_theme_stylebox_override("disabled", _action_row_box(kind, false, false))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# The opponent's rows exist to be READ, never pressed.
	if is_opponent:
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.modulate.a = 0.75
	elif enabled and row.has("action"):
		# ISSUE #217 (retest): "Button pressed = disabled", before anything else
		# happens. The blocker fix above closes the hole properly, but the press
		# itself must not be repeatable either: a disabled Button emits no `pressed`
		# at all, so killing the whole row set on the way IN is a hard stop that
		# does not depend on how fast the rest of the turn gets going.
		btn.pressed.connect(_run_action_row.bind(row))
	elif String(row.get("disabled_reason", "")) != "":
		# ISSUE #265: dead, but not silent.
		_add_disabled_reason_catcher(btn, String(row["disabled_reason"]))

	_fill_action_row(btn, row, enabled)
	return btn


## ISSUE #265: lets a DISABLED action row still explain itself when it is pressed.
##
## The button really is `disabled` - it emits no `pressed`, so #217's "one action
## per turn" hard stop is untouched and no dead row can ever fire its action. The
## explanation comes from a transparent Control laid over the button instead: a
## child Control is picked by the GUI ahead of its parent, and a parent being
## disabled does not stop it from receiving the click.
##
## Only ever added to a row that is dead AND has something worth saying - never
## to a live one, where it would swallow the real press, and never when the reason
## is empty, which is how "the board is not yours to act on right now" is spelled.
func _add_disabled_reason_catcher(btn: Button, reason: String) -> void:
	if reason.strip_edges() == "":
		return
	var catcher := Control.new()
	catcher.name = "disabled_reason_catcher"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.set_meta("disabled_reason", reason)
	catcher.gui_input.connect(_on_disabled_row_input.bind(catcher))
	btn.add_child(catcher)


## ISSUE #265: one message per press, never a queue of them.
func _on_disabled_row_input(event: InputEvent, catcher: Control) -> void:
	# UIInput.is_click, never a raw button test - the mouse WHEEL is a mouse button
	# event too, and scrolling a long action panel must not fire this.
	if not UIInput.is_click(event):
		return
	catcher.accept_event()
	if _disabled_reason_showing:
		return
	var reason := String(catcher.get_meta("disabled_reason", ""))
	if reason == "":
		return
	_disabled_reason_showing = true
	await show_message(reason.to_upper())
	_disabled_reason_showing = false


## ISSUE #217: fires one action row and kills every row on the way in.
##
## The rows are rebuilt from scratch by _build_action_panel on the next board
## refresh (and on every turn transition, see _refresh_action_panels), so nothing
## has to remember to switch them back on - they come back in whatever state the
## new turn state says they should be in.
func _run_action_row(row: Dictionary) -> void:
	set_action_rows_disabled(true)
	if row.has("action"):
		row["action"].call()


## ISSUE #217: hard-disable every action row on both panels, this frame.
##
## Also used by End Turn: pressing it commits the turn, so the rows must go dead
## at the same instant rather than staying live through the hand-over.
func set_action_rows_disabled(off: bool) -> void:
	for panel in [_player_action_panel, _opp_action_panel]:
		if panel == null or not is_instance_valid(panel):
			continue
		for btn in _all_buttons_under(panel):
			btn.disabled = off


func _all_buttons_under(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_all_buttons_under(child))
	return out


## Border and fill per row kind. Retreat is DASHED-looking (a lighter, inset
## border) so it never reads as a fourth attack; powers take accent_2.
func _action_row_box(kind: String, enabled: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(UITheme.mi("corner_radius"))
	sb.anti_aliasing = true
	sb.content_margin_left = ACTION_PAD
	sb.content_margin_right = ACTION_PAD
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.set_border_width_all(1)

	match kind:
		"power":
			sb.bg_color = UITheme.col_a("accent_2", 0.10 if hover else 0.04)
			sb.border_color = UITheme.col_a("accent_2", 0.85 if enabled else 0.35)
		"retreat":
			sb.bg_color = UITheme.col_a("line", 0.06 if hover else 0.02)
			sb.border_color = UITheme.col_a("field_mute", 0.55 if enabled else 0.25)
		_:
			sb.bg_color = UITheme.col("panel") if not hover else UITheme.col_a("accent", 0.10)
			# A PAYABLE attack takes the accent border; the rest keep the quiet line.
			sb.border_color = UITheme.col("accent") if enabled else UITheme.col("line")
	return sb


## ISSUE #215: ONE COST PIP — the printed energy symbol, not a coloured dot.
##
## The attack-mode buttons have always drawn the real icons out of
## ENERGY_ICON_DIR (_build_attack_button_content); the action rows that replaced
## them in stage 7 were built with flat coloured Panels instead, so the board had
## two different vocabularies for the same thing. A type with no art on disk
## still falls back to the coloured disc rather than leaving a gap.
func _make_cost_pip(energy_type: String, alpha: float) -> Control:
	var path := ENERGY_ICON_DIR + "color_icon_" + energy_type.to_lower() + ".png"
	if ResourceLoader.exists(path):
		var icon := TextureRect.new()
		icon.texture = load(path)
		icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(ACTION_PIP, ACTION_PIP)
		icon.modulate.a = alpha
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return icon

	var pip := Panel.new()
	pip.custom_minimum_size = Vector2(ACTION_PIP, ACTION_PIP)
	var psb := StyleBoxFlat.new()
	psb.bg_color = UITheme.energy_colour(energy_type)
	psb.set_corner_radius_all(int(ACTION_PIP * 0.5))
	psb.anti_aliasing = true
	pip.add_theme_stylebox_override("panel", psb)
	pip.modulate.a = alpha
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pip


## Cost pips, then the name, then the damage — laid out as anchored children,
## because the Button's own text would draw centred over the pips.
func _fill_action_row(btn: Button, row: Dictionary, enabled: bool) -> void:
	var kind: String = row["kind"]
	var alpha := 1.0 if enabled else ATTACK_DISABLED_ALPHA

	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = ACTION_PAD
	box.offset_right = -ACTION_PAD
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	# Cost pips. Attacks read theirs from the attack dict (ex11's Delta Aura
	# rewrites it), retreat from the card's retreat cost.
	var cost: Array = []
	if kind == "attack":
		cost = (row["attack"] as Dictionary).get("cost", [])
	elif kind == "retreat" and player_active_pokemon != null:
		var retreat_n: int = int(player_active_pokemon.metadata.get("convertedRetreatCost", 0))
		for _i in retreat_n:
			cost.append("Colorless")

	if not cost.is_empty():
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", int(ACTION_PIP_GAP))
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pips)
		for energy_type in cost:
			pips.add_child(_make_cost_pip(String(energy_type), alpha))

	var name_lbl := Label.new()
	var display_name: String = row["text"]
	if kind == "power":
		display_name = "Poké-Power · " + display_name
	UIKit.set_label(name_lbl, "attack_name", display_name,
		"accent_2" if kind == "power" else "field_fg")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ISSUE #222: centred in whatever is left between the pips and the damage, so
	# the names line up down the column instead of jogging sideways with each
	# attack's cost count. Same rule the old footer buttons followed.
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	name_lbl.modulate.a = alpha
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_lbl)

	if kind == "attack":
		var dmg: String = String((row["attack"] as Dictionary).get("damage", ""))
		if dmg != "":
			var dmg_lbl := Label.new()
			UIKit.set_label(dmg_lbl, "attack_damage", dmg,
				"accent" if enabled else "field_mute")
			dmg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			dmg_lbl.modulate.a = alpha
			dmg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(dmg_lbl)


# Refreshes the hand display for either player or opponent using standard sizes and containers
func refresh_hand_display(is_opponent: bool) -> void:
	if is_opponent:
		display_hand_cards_array(opponent_hand, opponent_hand_container, OPP_HAND_CARD, hide_hidden_cards, 400, 7, opponent_sleeve_small)
	else:
		display_hand_cards_array(player_hand, player_hand_container, card_scales[11])

# Display active and bench pokemon for either player or opponent. is_opponent: true for opponent, false for player
func display_pokemon(is_opponent: bool) -> void:
	var active_pokemon = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench_pokemon_array = opponent_bench if is_opponent else player_bench
	var active_container = opponent_active_container if is_opponent else player_active_container
	var bench_container = opponent_bench_container if is_opponent else player_bench_container
	
	# Clear active pokemon container. ISSUE #170: detach first.
	for child in active_container.get_children():
		active_container.remove_child(child)
		child.queue_free()
	
	# Display active pokemon if exists
	if active_pokemon != null:

		var active_card_display = TextureRect.new()
		active_card_display.set_script(card_display_script)
		active_container.add_child(active_card_display)
		active_card_display.load_card_image(active_pokemon.uid, ACTIVE_CARD, active_pokemon)
		active_card_display.card_clicked.connect(this_card_clicked)
	else:
		# ISSUE #213: an EMPTY SLOT, not a hole in the board. A slot the player can
		# see is information — "a Pokemon goes here" — where blank field is a bug
		# they have to rule out. Same component the collection walls use.
		var empty_active := UIKit.make_slot(ACTIVE_CARD)
		empty_active.mouse_filter = Control.MOUSE_FILTER_IGNORE
		active_container.add_child(empty_active)
	
	# Clear bench container. ISSUE #170: detach first — see display_hand_cards_array.
	for child in bench_container.get_children():
		bench_container.remove_child(child)
		child.queue_free()
	
	# Display bench pokemon
	# Each bench pokemon is wrapped in a VBoxContainer slot containing:
	#   - a Control card_area (free-layout) with energy cards stacked behind the pokemon card
	#   - a Label showing current/max HP
	# bench_container is an HBoxContainer so slots are laid out horizontally.
	if bench_pokemon_array.size() > 0:
		for bench_pokemon in bench_pokemon_array:
			# ISSUE #234: no HP NUMBER on the bench, and the counters sit
			# BENCH_SLOT_SEP under the card rather than 4px.
			var slot = build_pokemon_slot_with_energies_and_hp(bench_pokemon, BENCH_CARD, 16,
				false, true, true, false, BENCH_SLOT_SEP)
			bench_container.add_child(slot)

	# ISSUE #213: the rest of the bench is drawn as empty slots, so the row is
	# always five wide and the player can see how much room is left. They are
	# MOUSE_FILTER_IGNORE, so nothing about clicking a real bench Pokemon changes.
	for _i in range(BENCH_SLOTS - bench_pokemon_array.size()):
		bench_container.add_child(_make_empty_bench_slot())
			
	# Display HP circles for active Pokemon
	display_hp_circles_above_align(active_pokemon, is_opponent)

	# Attacks, powers and retreat live on the Pokemon now.
	_build_action_panel(is_opponent)

## ISSUE #231: AN EMPTY BENCH SLOT IS THE SIZE OF A CARD, NOT OF A WHOLE SLOT.
##
## The placeholder used to be a bare UIKit.make_slot(BENCH_CARD) dropped straight
## into the bench HBoxContainer. A BoxContainer stretches its children on the
## cross axis, so the outline was pulled to the FULL row height - card plus the
## HP line plus the damage counters - and read as a much bigger box than the card
## that would go in it.
##
## It is wrapped in the same VBox shape a real slot has instead: a card-sized
## outline, then a spacer standing in for the counter row. The wrapper takes the
## stretching, the outline keeps the card's exact rect, and the empty slots line
## up with the occupied ones on both edges.
func _make_empty_bench_slot() -> Control:
	var wrap := VBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", BENCH_SLOT_SEP)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var outline := UIKit.make_slot(BENCH_CARD)
	outline.custom_minimum_size = BENCH_CARD
	outline.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(outline)

	var counter_gap := Control.new()
	counter_gap.custom_minimum_size = Vector2(BENCH_CARD.x, BENCH_COUNTER_H)
	counter_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(counter_gap)
	return wrap


# Updates the header and hint labels based on what array is being displayed
func update_selection_mode_labels(array_displayed: Array, is_starting_game: bool = false) -> void:
	
	# Special case: if we're in bench setup phase, use specific text
	if bench_setup_phase_active:
		header_label.text = "Build Your Bench"
		hint_label.text = "Select up to 5 Pokémon to place on your bench"
		return
	
	# Determine which array we're displaying and set appropriate text
	if array_displayed == player_hand:
		if is_starting_game:
			header_label.text = "Select a Basic Pokémon"
			hint_label.text = "You must place a Basic Pokémon as your Active Pokémon to start"
		else:
			header_label.text = "Your Hand"
			hint_label.text = "Select a card to play"
	
	elif array_displayed == player_bench:
		header_label.text = "Your Bench"
		hint_label.text = "Select a card to set as your Active Pokémon"
	
	elif array_displayed == opponent_hand:
		header_label.text = "Opponent's Hand"
		hint_label.text = "Viewing opponent's hand"
		
	elif array_displayed == opponent_bench:
		header_label.text = "Opponent's Bench"
		hint_label.text = "Viewing opponent's bench"
		
	elif array_displayed == player_prize_cards:
		header_label.text = "Your Prize Cards"
		hint_label.text = "Viewing your prize cards"
		
	elif array_displayed == opponent_prize_cards:
		header_label.text = "Opponent's prize cards"
		hint_label.text = "Viewing opponent's prize cards"

	elif array_displayed == player_discard_pile:
		header_label.text = "Your Discard Pile"
		hint_label.text = "Viewing your discard pile"
		
	elif array_displayed == opponent_discard_pile:
		header_label.text = "Opponent's Discard Pile"
		hint_label.text = "Viewing opponent's discard pile"

# Function to change the text, enabled mode and function of the action button.
func update_action_button() -> void:
	
	# We need to see what the button can do by running the function get_card_action
	var action_info = get_card_action(selected_card_for_action)
	var action_button = action_button
	var action_type = action_info["action"]
	
	if action_type == "SET_POKEMON" and not match_just_started_basic_pokemon_required:
		if player_bench.size() >= get_max_bench_size():
			action_button.disabled = true
			action_button.text = "BENCH FULL"
			# If no card is selected, disable the button and change the colour to show it can't be clicked	
			action_button.theme = theme_disabled
			return
	
	# If no card is selected then we have no action to perform so disable the button and change text to select the card
	if selected_card_for_action == null:
		
		# Specific requirement for the first turn, ONLY a basic pokemon can be set and nothing else so change text accordingly
		if match_just_started_basic_pokemon_required:
			action_button.text = "Select Basic Pokemon"
		else:
			action_button.text = "Select A Card"
		
		# If no card is selected, disable the button and change the colour to show it can't be clicked	
		action_button.disabled = true
		action_button.theme = theme_disabled
	
	# If the match has just started, ONLY a basic pokemon can be played and SET AS ACTIVE POKEMON pokemon, not placed on bench	
	elif match_just_started_basic_pokemon_required and is_basic_pokemon(selected_card_for_action):
		
		# Match just started AND a basic pokemon is selected so card is set to active
		action_button.text = "SET AS ACTIVE POKEMON"
		
		# Enable the button and change the colour
		action_button.disabled = false
		action_button.theme = theme_green
	
	# If a basic pokemon is needed for turn 1 but any other card or no card is selected then change text to select basic pokemon	
	elif match_just_started_basic_pokemon_required:
		
		# Match just started BUT wrong card or no card type selected
		action_button.text = "Select Basic Pokemon"
		
		# Disable the button and change the colour
		action_button.disabled = true
		action_button.theme = theme_disabled
	
	# If the card selected was an energy card
	elif action_info["action"] == "ATTACH_ENERGY":
		# Energy card is selected and we're ready to attach it
		if player_energy_played_this_turn:
			action_button.text = "ENERGY PLAYED"
			action_button.disabled = true
			action_button.theme = theme_disabled
		else:
			action_button.text = "ATTACH ENERGY"
			action_button.disabled = false
			action_button.theme = theme_green
	
	elif action_info["action"] == "EVOLVE":
		var valid_targets = get_valid_evolution_targets(selected_card_for_action, false)
		if valid_targets.size() > 0:
			action_button.text = "EVOLVE"
			action_button.disabled = false
			action_button.theme = theme_green
		else:
			action_button.text = "CANNOT EVOLVE"
			action_button.disabled = true
			action_button.theme = theme_disabled
	
	# For 99% of other cases, if a card has been selected from the hand AND it isn't turn 1 requiring a basic, then display the action the card can take	
	else:
		# Normal match play - use action_info
		action_button.text = action_info["button_text"]
		
		# Only disable the button if the action avaialable is none
		action_button.disabled = (action_info["action"] == "NONE")
		
		# If the action button is disabled, change the colour. Change colour if it is enabled
		if action_button.disabled:
			action_button.theme = theme_disabled
		else:
			action_button.theme = theme_green

# Displays the prize cards for the specified player in their prize cards container
func display_prize_cards(is_opponent: bool) -> void:
	
	# Get the appropriate container and prize cards array
	# GridContainer since the prizes became a 3 x 2 block; typed loosely so the
	# node type is stated in ONE place (the scene) rather than two.
	var prize_cards_container: Container
	var prize_cards: Array
	
	if is_opponent:
		prize_cards_container = opponent_prize_container
		prize_cards = opponent_prize_cards		
	else:
		prize_cards_container = player_prize_container
		prize_cards = player_prize_cards

	# Clear any existing cards from the container. ISSUE #170: detach first.
	for child in prize_cards_container.get_children():
		prize_cards_container.remove_child(child)
		child.queue_free()
	
	# Remember the count this side STARTED with. Taken prizes leave a greyed slot
	# behind rather than closing the gap: the count is meant to be read spatially,
	# and a block that re-flows every time a prize is taken cannot be.
	if is_opponent:
		opponent_prize_start = maxi(opponent_prize_start, prize_cards.size())
	else:
		player_prize_start = maxi(player_prize_start, prize_cards.size())
	var started_with: int = opponent_prize_start if is_opponent else player_prize_start

	# Display each prize card
	for prize_card in prize_cards:
		var prize_card_display = TextureRect.new()
		
		# Attach the card display script
		prize_card_display.set_script(card_display_script)
		
		# Add to container
		prize_cards_container.add_child(prize_card_display)
		
		# Load the card image with a size appropriate for prize cards
		var prize_sleeve = opponent_sleeve_small if is_opponent else player_sleeve_small
		prize_card_display.load_card_image(prize_card.uid, PRIZE_SIZE, prize_card, hide_hidden_cards, prize_sleeve)
		
		# Connect the signal so prize cards can be clicked if needed
		prize_card_display.card_clicked.connect(this_card_clicked)

	# One empty slot per prize already taken, so the 3 x 2 block keeps its shape.
	#
	# ISSUE #213: and the block is padded out to a full 3 x 2 even when the match
	# STARTED with fewer than six prizes (some opponents are best-of-3 or short
	# matches), so the corner always reads as a prize block rather than as a
	# ragged row of two.
	# ISSUE #260: the row is PRIZE_COLUMNS wide and one deep, so a match started
	# with fewer than six prizes still draws a full row of slots and no more.
	var slots_needed: int = maxi(started_with, PRIZE_COLUMNS)
	for _i in range(slots_needed - prize_cards.size()):
		var taken := UIKit.make_slot(PRIZE_SIZE)
		taken.modulate.a = PRIZE_TAKEN_ALPHA
		taken.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prize_cards_container.add_child(taken)

# Displays attached energy cards next to the active Pokemon, stacking with overlap
func display_active_pokemon_energies(is_opponent: bool = false) -> void:
	var energy_container = opponent_energy_container if is_opponent else player_energy_container
	var active_pokemon = opponent_active_pokemon if is_opponent else player_active_pokemon

	# Always refresh attached trainer cards display (PlusPower, Defender)
	trainer_effects.display_attached_trainer_cards(is_opponent)

	# ISSUE #170: detach before freeing, or the old stack is still parented (and
	# still drawn) while the new one is added over it.
	for child in energy_container.get_children():
		energy_container.remove_child(child)
		child.queue_free()

	if active_pokemon == null:
		return

	if active_pokemon.attached_energies.size() == 0:
		return

	# ISSUE #239: -10% (card_scales[11] 100x138 -> 90x124).
	var energy_card_size = ATTACH_CARD_SIZE
	var card_width = energy_card_size.x
	var n = active_pokemon.attached_energies.size()
	var overlap_offset = _stack_offset(n, card_width)

	for i in range(active_pokemon.attached_energies.size()):
		var attached_energy = active_pokemon.attached_energies[i]
		var energy_display = TextureRect.new()
		energy_display.set_script(card_display_script)
		energy_container.add_child(energy_display)
		energy_display.load_card_image(attached_energy.uid, energy_card_size, attached_energy)
		energy_display.position.x = overlap_offset * i if is_opponent else -(i * overlap_offset)
		
## ISSUE #160: HOW FAR APART THE CARDS IN AN ATTACHMENT PEEK-STACK SIT.
##
## The stack used to step a flat 80px per card and only compress past SIX, and
## even then to a 480px target. Both actives sit in a 96px attachment column near
## the edge of the board, so the FIFTH energy was already ~320px out — off the
## left of the screen for the player and off the right for the opponent. That is
## what "the game never seems to be aware of a 5th energy" actually was: the
## energy was attached and counted, it just could not be seen.
##
## The whole stack is now held inside ATTACH_STACK_SPAN however many cards are on
## it, so the fan gets tighter rather than longer. TWEAKABLE.
## 160, not 210: the attachment column is only DUEL_COL_ATTACH (96) wide and the
## player's stack fans LEFT from it, so anything wider walks into the left rail.
## ISSUE #216 (retest): 160 -> 300. The stacks fan OUTWARD from the attachment
## column into the band between the duel row and the rail, and at the duel row's
## y (326..645) that band is completely empty - the rail's own occupants sit at
## y 132..239 and y 690..767. 160px was throwing away roughly twice as much free
## space as it was using, which is exactly what the retest said.
const ATTACH_STACK_SPAN := 300.0
const ATTACH_STACK_STEP := 80.0

func _stack_offset(count: int, card_width: float) -> float:
	if count <= 1:
		return ATTACH_STACK_STEP
	var natural: float = ATTACH_STACK_STEP * float(count - 1) + card_width
	if natural <= ATTACH_STACK_SPAN:
		return ATTACH_STACK_STEP
	return maxf((ATTACH_STACK_SPAN - card_width) / float(count - 1), 8.0)


# Calculates the total pixel height the tallest energy stack in the array will occupy above
# its pokemon card. Used by display_hand_cards_array to shift small_selection_container down
# so energy cards don't clip into the header area.
# Returns 0.0 if no cards in the array are in play or if pokemon_selection_mode is false.
func _calculate_max_energy_stack_height(card_array: Array, card_size: Vector2, pokemon_selection_mode: bool) -> float:
	if not pokemon_selection_mode:
		return 0.0
	var max_px = 0.0
	for card_obj in card_array:
		var loc = card_obj.current_location
		if loc != "bench" and loc != "active":
			continue
		if not card_obj.metadata.has("hp"):
			continue
		var energy_count = card_obj.attached_energies.size()
		if energy_count == 0:
			continue
		# Mirror the same formula used in build_pokemon_slot_with_energies_and_hp.
		var fraction = 0.12 - (energy_count - 1) * 0.01
		var energy_offset = max(10.0, card_size.y * fraction)
		# Total stack height = sum of all offsets = energy_count * energy_offset
		# (each card peeks by energy_offset, and the stack is energy_count cards deep).
		var stack_height = energy_count * energy_offset
		max_px = max(max_px, stack_height)
	return max_px

# Builds a VBoxContainer wrapping a pokemon card with stacked energy behind it and an HP label below.
# card_obj      : the pokemon card_object
# card_size     : Vector2 pixel size for the pokemon card and each energy card
# label_font_size: font size for the HP label
# show_hp_and_energies: only true when card is on bench or active spot
# Returns the VBoxContainer ready to add to any HBoxContainer / layout parent.
#
# ALIGNMENT: card_area Control has a fixed custom_minimum_size = card_size.
# Energy cards use NEGATIVE y positions to extend upward outside card_area without
# affecting the VBoxContainer's layout height, so the pokemon card and HP label never shift.
var _issue59_zorder_logged: bool = false
## ISSUE #234: `show_hp_number` and `separation` are new. A BENCH slot shows the
## damage-counter blocks but NOT the "30 / 50" line - five of those across the
## board was five numbers nobody reads while the blocks say the same thing at a
## glance - and it sits its counters 2px under the card instead of 4.
func build_pokemon_slot_with_energies_and_hp(card_obj: card_object, card_size: Vector2, label_font_size: int, _is_active: bool = false, show_hp_and_energies: bool = true, show_energies: bool = true, show_hp_number: bool = true, separation: int = 4) -> VBoxContainer:

	var slot = VBoxContainer.new()
	slot.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_theme_constant_override("separation", separation)

	# Bench power button, above the card. Built only for the player's own bench
	# slots — `_is_active` is false there and true for the focus/preview slots the
	# retreat and selection screens build, which must stay plain.
	if not _is_active and show_hp_and_energies and powers_and_bodies != null \
			and card_obj in player_bench:
		var printed: Array = powers_and_bodies.printed_powers_for(card_obj)
		if not printed.is_empty():
			slot.add_child(_make_bench_power_button(card_obj, printed[0], card_size))

	# ISSUE #46: show_energies can suppress the stacked-energy display independently of the HP label
	# (used by the player retreat screen, where energies are already listed as selectable cards).
	var energy_count = card_obj.attached_energies.size() if (show_hp_and_energies and show_energies) else 0
	
	# Per-energy visible strip: starts at 12% of card height, shrinks by 1% per extra energy
	# attached (beyond the first), floored at a hard minimum of 10px so it never disappears.
	# This prevents a large stack from overflowing the UI vertically.
	var base_fraction = 0.12
	var shrink_per_card = 0.01
	var min_px = 10.0
	var energy_offset: float = 0.0
	if energy_count > 0:
		var fraction = base_fraction - (energy_count - 1) * shrink_per_card
		energy_offset = max(min_px, card_size.y * fraction)
	
	# card_area is a fixed-size free-layout Control — energies overflow upward with negative y.
	var card_area = Control.new()
	card_area.custom_minimum_size = card_size
	card_area.mouse_filter = MOUSE_FILTER_PASS
	slot.add_child(card_area)
	
	# ISSUE #59 FIX: show attached tool/trainer cards (Defender, PlusPower, etc.) stacked ABOVE the
	# energy cards for bench Pokémon so they read as attached too. The Active Pokémon shows its tools
	# via display_attached_trainer_cards, so only render them here for bench slots.
	# ISSUE #80: gate the stacked tools on `show_energies` too. Normal bench slots (show_energies=true)
	# keep stacking their tools; the retreat/preview FOCUS Pokémon (show_energies=false) renders its
	# tools as separate cards beside it instead, so it must not ALSO stack them here (double image).
	#
	# ISSUE #59 FIX (retest sub-issue 1 — the real z-order cause): Godot draws siblings in child order,
	# so whatever is added LAST is in FRONT. The whole stack must therefore be built strictly
	# back-to-front: highest tool → lowest tool → highest energy → lowest energy → Pokémon card. The
	# tools used to be added AFTER the energies, which put every tool in front of the topmost energy
	# card even though it sits further up the stack. Reversing the two blocks is the fix; the
	# highest-first iteration inside each block orders the cards within it.
	if show_hp_and_energies and show_energies and card_obj.current_location == "bench" and card_obj.attached_cards.size() > 0:
		var tool_offset = energy_offset if energy_offset > 0 else max(min_px, card_size.y * base_fraction)
		var stack_top = energy_count * energy_offset  # top edge of the energy stack (upward)
		var tool_count = card_obj.attached_cards.size()
		for j in range(tool_count - 1, -1, -1):
			var tool_obj = card_obj.attached_cards[j]
			var tool_display = TextureRect.new()
			tool_display.set_script(card_display_script)
			card_area.add_child(tool_display)
			tool_display.load_card_image(tool_obj.uid, card_size, tool_obj)
			tool_display.position = Vector2(0, -(stack_top + (j + 1) * tool_offset))
			tool_display.mouse_filter = MOUSE_FILTER_IGNORE
		# One-shot: this runs inside the per-slot draw path, called on every board refresh, so an
		# unconditional print would produce dozens of identical lines per attack.
		if not _issue59_zorder_logged:
			_issue59_zorder_logged = true
			print("ISSUE #59 FIX ACTIVE: bench tools now drawn BEFORE energies, so they render behind them")

	if show_hp_and_energies and energy_count > 0:
		# Add energies in REVERSE draw order so energy[0] (first attached) renders on top.
		# i goes from energy_count-1 down to 0.
		# Position formula: -(i + 1) * energy_offset
		#   i = energy_count-1 (added first, drawn under) → position = -(energy_count * offset)  [furthest up]
		#   i = 0             (added last,  drawn on top) → position = -(1 * offset)             [closest to card]
		for i in range(energy_count - 1, -1, -1):
			var energy_obj = card_obj.attached_energies[i]
			var energy_display = TextureRect.new()
			energy_display.set_script(card_display_script)
			card_area.add_child(energy_display)
			energy_display.load_card_image(energy_obj.uid, card_size, energy_obj)
			energy_display.position = Vector2(0, -(i + 1) * energy_offset)
			energy_display.mouse_filter = MOUSE_FILTER_IGNORE

	# Pokemon card at (0, 0) — on top of all energies.
	var card_display = TextureRect.new()
	card_display.set_script(card_display_script)
	card_area.add_child(card_display)
	card_display.load_card_image(card_obj.uid, card_size, card_obj)
	card_display.position = Vector2(0, 0)
	card_display.card_clicked.connect(this_card_clicked)
	
	# HP label only when card is in play (bench or active) and hp metadata exists.
	if show_hp_and_energies and card_obj.metadata.has("hp"):
		var max_hp = int(card_obj.metadata["hp"])
		var current_hp = card_obj.current_hp
		# ISSUE #234: the bench passes show_hp_number = false. The blocks below carry
		# the same information and are what the card text actually keys off.
		if show_hp_number:
			var hp_label = Label.new()
			# "30 / 50", spaced, in the mono face so digits line up down a row.
			hp_label.text = "%d / %d" % [current_hp, max_hp]
			hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UIKit.style_label(hp_label, "hp", "field_fg", label_font_size)
			slot.add_child(hp_label)

		# ONE BLOCK PER 10 HP, never a bar. Attacks and effects in this game key off
		# the NUMBER of damage counters, so the blocks are information, not
		# decoration — see UIKit.make_damage_counters.
		var blocks := UIKit.make_damage_counters(current_hp, max_hp, true)
		blocks.alignment = BoxContainer.ALIGNMENT_CENTER
		if show_hp_number:
			slot.add_child(blocks)
		else:
			# ISSUE #234: a 12-block counter row is wider than a bench card even
			# after the 10% shrink, and a BoxContainer takes its width from its
			# WIDEST child - so the counters, not the card, were setting how far
			# apart the bench slots sat. Asking for 25% less horizontal space while
			# the counters keep dictating it is a contradiction. The row goes in a
			# card-WIDTH holder and overflows it symmetrically, so the slot measures
			# the card and the counters still centre under it.
			var holder := Control.new()
			holder.custom_minimum_size = Vector2(card_size.x, BENCH_COUNTER_H)
			holder.mouse_filter = MOUSE_FILTER_IGNORE
			blocks.set_anchors_preset(Control.PRESET_CENTER_TOP)
			blocks.grow_horizontal = Control.GROW_DIRECTION_BOTH
			blocks.mouse_filter = MOUSE_FILTER_IGNORE
			holder.add_child(blocks)
			slot.add_child(holder)
	
	return slot

# ISSUE #87: the HP squares belong to the Active Pokemon, so they must only be on screen while that
# Pokemon's card is actually on screen. Any time the Active card is hidden to fly it somewhere (retreat,
# forced switch, knockout, bench replacement) the squares have to go with it, or they hang in an empty
# slot — sometimes still showing the old Pokemon's HP.
#
# THE ONE PLACE the Active slot's visibility is toggled. Always use this instead of setting
# `active_container.visible` directly, so the two can never get out of step.
## ISSUE #245: it hides the STATUS icons and the ACTION ROWS too.
##
## "When a Pokemon retreats the screen should update as soon as it starts to
## move" - the card and its HP already went with it (#87), but the status icons
## and the attack/power/retreat rows stayed put, describing a Pokemon that was
## visibly halfway to the bench. They belong to that Pokemon exactly as much as
## its HP does, so they travel with it.
func set_active_slot_visible(is_opponent: bool, is_slot_visible: bool) -> void:
	var active_container = opponent_active_container if is_opponent else player_active_container
	var hp_container = opponent_hp_container if is_opponent else player_hp_container
	var status_container = opponent_status_container if is_opponent else player_status_container
	var panel: Control = _opp_action_panel if is_opponent else _player_action_panel
	active_container.visible = is_slot_visible
	hp_container.visible = is_slot_visible
	status_container.visible = is_slot_visible
	if panel != null and is_instance_valid(panel):
		panel.visible = is_slot_visible

## ISSUE #224: the active Pokemon's HP is drawn in the SAME style as the bench's.
##
## This used to be up to 24 hand-rolled 30x30 red/green ColorRects in a
## 12-column grid — the pre-overhaul look, and 12 x 30 = 360px wide against a
## 322px info column, which is also why the blocks ran over the active card
## (ISSUE #213). It is a mono "30 / 50" over UIKit.make_damage_counters() now,
## exactly like every bench slot, at the larger ACTIVE size.
##
## The function keeps its name and signature: it is called from a dozen places.
func display_hp_circles_above_align(active_pokemon: card_object, is_opponent: bool) -> void:
	var hp_grid_container = opponent_hp_container if is_opponent else player_hp_container

	for child in hp_grid_container.get_children():
		child.queue_free()

	# ISSUE #87: no Active Pokemon (knocked out, or mid-swap) -> no HP at all. This
	# also re-reveals it on the next refresh once a replacement has arrived.
	if active_pokemon == null or not active_pokemon.metadata.has("hp"):
		hp_grid_container.visible = false
		return
	hp_grid_container.visible = true
	hp_grid_container.columns = 1

	var max_hp: int = int(active_pokemon.metadata["hp"])
	var current_hp: int = active_pokemon.current_hp

	# ISSUE #233 (retest) / #256 / #257: BOTH ROWS HUG THE ACTIVE CARD.
	#
	# Moving the container in (#233, first pass) was only half of it: the label and
	# the block row were still CENTRED inside a 258px box, so a three-counter row
	# sat ~100px from the card no matter where the box was. They are aligned to the
	# INNER edge now - right for you, left for the opponent - which puts the "120"
	# and the last damage block a few pixels off the card, and means each extra
	# counter is added on the OUTER side (leftwards for you, rightwards for them)
	# exactly as #256 describes. Same rule as the status icons (#262).
	var inner_h: int = HORIZONTAL_ALIGNMENT_LEFT if is_opponent else HORIZONTAL_ALIGNMENT_RIGHT
	var inner_box: int = (BoxContainer.ALIGNMENT_BEGIN if is_opponent
		else BoxContainer.ALIGNMENT_END)

	var hp_label := Label.new()
	hp_label.text = "%d / %d" % [current_hp, max_hp]
	hp_label.horizontal_alignment = inner_h
	UIKit.style_label(hp_label, "hp", "field_fg", ACTIVE_HP_FONT)
	hp_label.custom_minimum_size.x = ACTION_PANEL_W
	hp_grid_container.add_child(hp_label)

	# `false` = the ACTIVE block size (16x27), not the bench's smaller pair.
	var blocks := UIKit.make_damage_counters(current_hp, max_hp, false)
	blocks.alignment = inner_box
	blocks.custom_minimum_size.x = ACTION_PANEL_W
	blocks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_grid_container.add_child(blocks)

	# ISSUE #286: if this redraw is a DROP in HP on the same Pokemon, walk the row
	# back to where it was and take the blocks off one at a time.
	_maybe_animate_hp_deplete(blocks, hp_label, active_pokemon, is_opponent,
		current_hp, max_hp)


## ISSUE #286: THE BLOCKS COME OFF ONE AT A TIME.
##
## display_hp_circles_above_align REBUILDS the whole row on every call, so a
## 60-damage hit simply repainted six blocks between two frames and the counter
## had already finished before the damage figure had finished floating. There is
## nothing to tween - the row is new every time - so the animation has to be
## driven from the DIFFERENCE between what is on screen and what has just been
## drawn, which is what _hp_shown remembers.
##
## Only a DROP animates, and only on the same Pokemon: a heal, a replacement, a
## first draw or a Pokemon swap all snap, because none of them read as damage.
## TWEAKABLE - the gap between blocks, scaled by the match animation-speed preset
## like every other in-match beat (#34), so "slow" spreads it out and reduce
## motion collapses it to nothing.
const HP_BLOCK_STEP := 0.07

var _hp_shown: Dictionary = {}

func _maybe_animate_hp_deplete(blocks: HBoxContainer, hp_label: Label,
		mon: card_object, is_opponent: bool, current_hp: int, max_hp: int) -> void:
	var side := "opp" if is_opponent else "you"
	var total: int = int(ceil(maxf(float(max_hp), 0.0) / 10.0))
	var damaged_now: int = mini(int(ceil(float(maxi(max_hp - current_hp, 0)) / 10.0)), total)
	var prev: Dictionary = _hp_shown.get(side, {})
	_hp_shown[side] = {"mon": mon, "hp": current_hp, "damaged": damaged_now, "total": total}

	if prev.is_empty() or prev.get("mon") != mon or int(prev.get("total", -1)) != total:
		return
	var damaged_was: int = int(prev.get("damaged", damaged_now))
	if damaged_now <= damaged_was:
		return
	var step: float = GameState.match_time(HP_BLOCK_STEP)
	if step <= 0.0:
		return   # reduce motion / instant preset: the row is already correct

	print("ISSUE #286 FIX ACTIVE: HP blocks ", damaged_was, " -> ", damaged_now,
		" of ", total, " on ", mon.metadata.get("name", "?"), ", ", step, "s per block")
	_deplete_hp_blocks(blocks, hp_label, total, damaged_was, damaged_now,
		int(prev.get("hp", current_hp)), current_hp, max_hp, step)


## Repaints the row back to its previous state, then removes the new blocks one
## per `step`. Deliberately NOT awaited by the caller: display_hp_circles_above_align
## is called from a dozen places, most of them not in a coroutine, and a stray
## rebuild while this is running simply frees the row - which every step checks for.
func _deplete_hp_blocks(blocks: HBoxContainer, hp_label: Label, total: int,
		from_damaged: int, to_damaged: int, from_hp: int, to_hp: int, max_hp: int,
		step: float) -> void:
	# UIKit.make_damage_counters greys the LAST `damaged` blocks, so the newly lost
	# ones are the run immediately before the greyed tail, taken from the inside out.
	for i in range(from_damaged, to_damaged):
		_paint_hp_block(blocks, total - 1 - i, false)
	if hp_label != null and is_instance_valid(hp_label):
		hp_label.text = "%d / %d" % [from_hp, max_hp]

	var steps: int = to_damaged - from_damaged
	for i in range(steps):
		await get_tree().create_timer(step).timeout
		if not is_instance_valid(blocks):
			return
		_paint_hp_block(blocks, total - 1 - (from_damaged + i), true)
		if hp_label != null and is_instance_valid(hp_label):
			var frac: float = float(i + 1) / float(steps)
			hp_label.text = "%d / %d" % [
				int(round(lerpf(float(from_hp), float(to_hp), frac))), max_hp]


## One block's fill. Same two colours make_damage_counters uses, so the animated
## row and a freshly built one are indistinguishable once it settles.
func _paint_hp_block(blocks: HBoxContainer, index: int, is_damaged: bool) -> void:
	if not is_instance_valid(blocks) or index < 0 or index >= blocks.get_child_count():
		return
	var block := blocks.get_child(index)
	if not (block is Panel):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.col_a("accent_2", 0.30) if is_damaged else UITheme.col("good")
	sb.set_corner_radius_all(2)
	sb.anti_aliasing = true
	(block as Panel).add_theme_stylebox_override("panel", sb)


# Adds one row of HP circles and spacers to the grid container
# circles_first: if true, circles are drawn before spacers (left-aligned for opponent)
# red_from_right: if true, red fills from the right side of the row (opponent bottom row)
func _add_hp_row(container: GridContainer, circle_count: int, spacer_count: int, red_count: int, circles_first: bool, red_from_right: bool) -> void:
	if circles_first:
		_add_hp_circles(container, circle_count, red_count, red_from_right)
		_add_hp_spacers(container, spacer_count)
	else:
		_add_hp_spacers(container, spacer_count)
		_add_hp_circles(container, circle_count, red_count, red_from_right)

# Draws colored circles into the HP grid, coloring red for damage taken
func _add_hp_circles(container: GridContainer, count: int, red_count: int, red_from_right: bool) -> void:
	for i in range(count):
		var circle = ColorRect.new()
		circle.custom_minimum_size = Vector2(30, 30)
		if red_from_right:
			circle.color = Color.RED if i >= (count - red_count) else Color.GREEN
		else:
			circle.color = Color.RED if i < red_count else Color.GREEN
		container.add_child(circle)

# Draws invisible spacer cells to align HP circles within the 12-column grid
func _add_hp_spacers(container: GridContainer, count: int) -> void:
	for _i in range(count):
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(30, 30)
		container.add_child(spacer)

# Hides the main action buttons and generates one attack button per attack the pokemon has
func show_attack_buttons() -> void:
	if player_active_pokemon == null:
		return
	
	if turn_number <= 1:
		await show_message("You cannot attack on the first turn!")
		hide_attack_buttons()
		return
	if player_active_pokemon.special_condition == "Paralyzed":
		await show_message(player_active_pokemon.metadata.get("name", "").to_upper() + " IS PARALYZED AND CANNOT ATTACK!")
		hide_attack_buttons()
		return
	if player_active_pokemon.special_condition == "Asleep":
		await show_message(player_active_pokemon.metadata.get("name", "").to_upper() + " IS ASLEEP AND CANNOT ATTACK!")
		hide_attack_buttons()
		return
	
	main_buttons_container.visible = false
	attack_buttons_container.visible = true
	
	var attacks = get_attacks_for_card(player_active_pokemon)
	
	if attacks.size() == 0:
		print("Active pokemon has no attacks")
		return
	
	_attack_list = attacks
	_attack_page = 0
	_render_attack_page()


# ============================================================
# ATTACK BUTTON CONTENT — [energy icons] [name] [damage]
# ============================================================
# A Button cannot carry inline images through its `text`, so the row is built as
# child Controls laid out with ANCHORS rather than absolute offsets: the button's
# final size is decided by the HBoxContainer after this runs, and anchored
# children re-flow to whatever it ends up being.
#
# Every child is MOUSE_FILTER_IGNORE, or it would swallow the click meant for the
# button underneath it.
#
# The cost is read from the attack dict handed over by get_attacks_for_card(),
# NOT from the card's own metadata — ex11's Delta Aura rewrites the cost of a
# paired attack on the way through, so the button shows the discounted cost the
# player will actually be charged.

# ── Roomy defaults: what a normal 1-3 attack Pokemon gets ──
# 99% of cards have three attacks or fewer, so these are tuned for that case and
# everything below only kicks in when a card exceeds it.
const ATTACK_BTN_MAX_W: float      = 520.0  # ceiling even when there is room to spare
const ATTACK_BTN_PAD_X: float      = 14.0   # button edge -> first icon / last digit
const ATTACK_COST_ICON: float      = 26.0   # energy icon square
const ATTACK_COST_GAP: float       = 3.0    # between two energy icons
const ATTACK_SECTION_GAP: float    = 12.0   # icons -> name, and name -> damage
const ATTACK_NAME_FONT: int        = 20     # matches the kenneyUI theme's button size
const ATTACK_NAME_MIN_FONT: int    = 9      # hard floor when a long name has to shrink
const ATTACK_DAMAGE_FONT: int      = 24     # the headline number, a touch larger
# Content on a disabled button, dimmed to sit alongside the theme's own
# font_disabled_color rather than staying at full strength over a greyed panel.
const ATTACK_DISABLED_ALPHA: float = 0.35

# ── Crowding: how the row gives ground as attacks are added ──
# A card can end up with far more attacks than it was printed with — every
# Technical Machine attached replaces or adds one, Meteor Falls and gym1 Recall
# add the whole pre-evolution chain, and ex12 Versatile adds the attacks of every
# Pokemon in play. There is no upper bound, so the row has to degrade gracefully
# rather than run off the screen.
#
# Three levers, applied in this order:
#   1. CANCEL shrinks (it is one word in a 350px button)
#   2. separation collapses
#   3. the buttons themselves shrink, and their contents scale with them
# Past ATTACKS_PER_PAGE the buttons would stop being readable, so the row pages
# instead of shrinking any further.
const ATTACK_ROOMY_MAX: int        = 3      # at or below this, keep the generous look
const ATTACKS_PER_PAGE: int        = 5      # most that stay legible on one row
const ATTACK_CANCEL_W_ROOMY: float = 350.0  # CANCEL's authored width
const ATTACK_CANCEL_W_TIGHT: float = 200.0  # CANCEL once the row is crowded
const ATTACK_MORE_BTN_W: float     = 210.0  # the "MORE 1/3" page button
const ATTACK_SEP_BASE: float       = 100.0  # the container's authored separation
const ATTACK_SEP_MIN: float        = 20.0
const ATTACK_BTN_FLOOR_W: float    = 120.0  # absolute floor; only reachable on a tiny row
# Used only if the container's own offsets ever read as zero. Matches the width
# authored in Main_Match_Core_GamePlay_Scene.tscn (offset_left -1843 -> right 57).
const ATTACK_ROW_FALLBACK_W: float = 1900.0
# The project's reference resolution, as used by every other code-built screen
# (DynamicMessageBox.SCREEN_W, CardDetailPanel.SCREEN_W). The row is clamped to
# this because the button container is authored wider than the display.
const ATTACK_SCREEN_W: float = 1920.0
# Contents scale against this width. A button at or above it draws at full size;
# narrower buttons scale their icons, padding and fonts down proportionally.
const ATTACK_SCALE_REF_W: float    = 420.0
const ATTACK_SCALE_MIN: float      = 0.42

const ENERGY_ICON_DIR: String = "res://Image_Assets/Icons/Energy_Icons/"
const ATTACK_BTN_FONT_PATH: String = "res://UI_Themes/ChakraPetch-Bold.ttf"

var _attack_btn_font: Font = null
# The full attack list for the current selection, and which page of it is shown.
# Held so the MORE button can re-render without re-running show_attack_buttons()'s
# guards (which would re-show "cannot attack on the first turn" messages).
var _attack_list: Array = []
var _attack_page: int = 0


func _get_attack_btn_font() -> Font:
	if _attack_btn_font == null:
		_attack_btn_font = load(ATTACK_BTN_FONT_PATH)
	return _attack_btn_font


## Everything the row needs to lay itself out for the current page, worked out in
## one place so the button builder never has to re-derive a size.
##
## Returns: page_count, page_start, shown (attack count on this page), paged,
## btn_w, sep, cancel_w, scale.
func _attack_row_metrics() -> Dictionary:
	var total: int = _attack_list.size()
	var page_count: int = maxi(1, ceili(float(total) / float(ATTACKS_PER_PAGE)))
	_attack_page = clampi(_attack_page, 0, page_count - 1)
	var paged: bool = total > ATTACKS_PER_PAGE
	var page_start: int = _attack_page * ATTACKS_PER_PAGE
	var shown: int = mini(ATTACKS_PER_PAGE, total - page_start) if paged else total

	var m := {
		"page_count": page_count,
		"page_start": page_start,
		"shown": shown,
		"paged": paged,
	}
	if shown <= 0:
		m["btn_w"] = ATTACK_BTN_MAX_W
		m["sep"] = ATTACK_SEP_BASE
		m["cancel_w"] = ATTACK_CANCEL_W_ROOMY
		m["scale"] = 1.0
		return m

	# How much room the row ACTUALLY has, which is not the container's own width.
	#
	# Two traps here, both of which cost a fix each:
	#   1. NOT container.size.x. A BoxContainer's size is max(its own rect, the sum
	#      of its children's minimums), so once a row has overflowed, size.x reports
	#      the OVERFLOWED width and the next layout budgets against a row wider than
	#      the screen — it would never recover.
	#   2. NOT the authored offsets either. The container is 1900 wide but sits at
	#      x=64 (BUTTONS is at offset_left 1907, the container at -1843), so its
	#      right edge is at 1964 — 44px PAST the 1920 screen. Budgeting against 1900
	#      put the last button half off the display no matter how the maths inside
	#      it worked out.
	# So: take the authored width, but clamp it to what fits on screen, mirroring the
	# container's own left inset on the right so the row sits evenly.
	var left_x: float = clampf(attack_buttons_container.global_position.x, 0.0, ATTACK_SCREEN_W)
	var authored: float = attack_buttons_container.offset_right - attack_buttons_container.offset_left
	if authored <= 0.0:
		authored = ATTACK_ROW_FALLBACK_W
	var row_w: float = minf(authored, ATTACK_SCREEN_W - left_x * 2.0)
	if row_w <= 0.0:
		row_w = ATTACK_ROW_FALLBACK_W

	# Lever 1 + 2. Separation eases off rather than snapping, so going from three
	# to four attacks does not visibly jolt the row.
	var cancel_w: float = ATTACK_CANCEL_W_ROOMY if shown <= ATTACK_ROOMY_MAX else ATTACK_CANCEL_W_TIGHT
	var sep: float = ATTACK_SEP_BASE
	if shown > ATTACK_ROOMY_MAX:
		sep = clampf(ATTACK_SEP_BASE / float(shown - ATTACK_ROOMY_MAX + 1),
					 ATTACK_SEP_MIN, ATTACK_SEP_BASE)

	# Children on the row: the attack buttons, CANCEL, and MORE when paging.
	var child_count: int = shown + 1 + (1 if paged else 0)
	var fixed_w: float = cancel_w + (ATTACK_MORE_BTN_W if paged else 0.0)
	var free: float = row_w - fixed_w - sep * float(child_count - 1)
	var btn_w: float = clampf(free / float(shown), ATTACK_BTN_FLOOR_W, ATTACK_BTN_MAX_W)

	m["btn_w"] = btn_w
	m["sep"] = sep
	m["cancel_w"] = cancel_w
	m["scale"] = clampf(btn_w / ATTACK_SCALE_REF_W, ATTACK_SCALE_MIN, 1.0)
	return m


## Builds (or rebuilds) the visible page of attack buttons. Safe to call again on
## a page change — it clears everything except the permanent CANCEL button, which
## is a scene node rather than a generated one.
func _render_attack_page() -> void:
	for child in attack_buttons_container.get_children():
		if child.name == "cancel_attack_mode_button":
			continue
		# remove_child BEFORE queue_free: queue_free only takes effect at the end of
		# the frame, so on a page change the old buttons would still be laid out by
		# the container alongside the new ones and every width would be halved.
		attack_buttons_container.remove_child(child)
		child.queue_free()

	var m := _attack_row_metrics()

	attack_buttons_container.add_theme_constant_override("separation", int(m["sep"]))
	var cancel := attack_buttons_container.get_node_or_null("cancel_attack_mode_button")
	if cancel != null:
		cancel.custom_minimum_size.x = float(m["cancel_w"])

	var page_start: int = m["page_start"]
	for offset in range(int(m["shown"])):
		var index: int = page_start + offset
		var attack = _attack_list[index]
		var btn = Button.new()
		# The label is drawn by _build_attack_button_content() as icons + name +
		# damage, so the Button's own text stays empty -- a Button draws its text
		# centred over the whole rect and it would sit on top of the energy icons.
		btn.text = ""

		# Check if attack is disabled (Farfetch'd permanent, Amnesia, etc.)
		var attack_name = attack.get("name", "")
		var label_text: String = attack_name
		if is_attack_disabled(player_active_pokemon, attack_name):
			btn.disabled = true
			btn.theme = theme_disabled
			label_text = attack_name + " (DISABLED)"
		# Enable and colour green if requirements met, disable and grey out if not
		elif check_attack_requirements(attack, player_active_pokemon):
			btn.disabled = false
			btn.theme = theme_green
		else:
			btn.disabled = true
			btn.theme = theme_disabled

		# ISSUE #287: same press-not-release fix as the forfeit dialog. These are
		# hand-built Buttons carrying the legacy themes, so they never picked up
		# UIKit.style_button's action_mode either.
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.custom_minimum_size = Vector2(float(m["btn_w"]), 50)
		attack_buttons_container.add_child(btn)
		_build_attack_button_content(btn, attack, label_text, float(m["scale"]), float(m["btn_w"]))

		# bind(index) locks the TRUE index into the callable — the index into the
		# whole attack list, not the position on this page, or paging to page 2
		# would fire page 1's attacks.
		btn.pressed.connect(perform_attack.bind(index))

	if m["paged"]:
		attack_buttons_container.add_child(
				_make_attack_page_button(int(m["page_count"]), float(m["sep"])))


## The "MORE 2/3" button. One button that cycles forward and wraps, rather than a
## back/forward pair plus a counter: three children would eat the width the
## attack buttons need, and with only a handful of pages cycling round is quicker
## than reaching for the right arrow anyway.
func _make_attack_page_button(page_count: int, _sep: float) -> Button:
	var btn := Button.new()
	btn.text = "MORE  %d/%d" % [_attack_page + 1, page_count]
	btn.theme = theme_blue
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS   # ISSUE #287
	btn.custom_minimum_size = Vector2(ATTACK_MORE_BTN_W, 50)
	btn.pressed.connect(func():
		_attack_page = (_attack_page + 1) % page_count
		_render_attack_page())
	return btn


## Total width the cost icons occupy at this scale, 0 for a free attack.
func _attack_cost_width(attack: Dictionary, scale: float) -> float:
	var n := _attack_cost_types(attack).size()
	if n == 0:
		return 0.0
	return float(n) * (ATTACK_COST_ICON * scale) + float(n - 1) * (ATTACK_COST_GAP * scale)


## The cost as a list of type names that actually have an icon on disk. An
## unknown type is dropped rather than drawn as a gap, so a data typo shows a
## short cost instead of a hole in the row.
func _attack_cost_types(attack: Dictionary) -> Array:
	var out: Array = []
	for entry in attack.get("cost", []):
		var type_name := String(entry).strip_edges()
		if type_name == "":
			continue
		if ResourceLoader.exists(ENERGY_ICON_DIR + "color_icon_" + type_name.to_lower() + ".png"):
			out.append(type_name)
	return out


func _build_attack_button_content(btn: Button, attack: Dictionary, label_text: String,
								  scale: float, btn_w: float) -> void:
	var font := _get_attack_btn_font()

	# Everything on the row scales together, so a crowded button stays a smaller
	# copy of a roomy one rather than a roomy one with the name squeezed out.
	var pad_x: float   = ATTACK_BTN_PAD_X * scale
	var icon_px: float = ATTACK_COST_ICON * scale
	var sect_gap: float = ATTACK_SECTION_GAP * scale
	# Damage is two to four characters, so it barely needs to give ground — it
	# scales, but off a high floor.
	var dmg_font: int = maxi(14, int(round(float(ATTACK_DAMAGE_FONT) * scale)))
	# The NAME deliberately does NOT scale with the button. It is the one thing on
	# the row you have to be able to read, so it starts at full size and the fit
	# loop below takes it down only as far as this particular name actually needs.
	# Scaling the ceiling too would shrink "COLLECT" on a crowded row for no reason.
	var name_ceiling: int = ATTACK_NAME_FONT

	# One wrapper for everything, so a disabled button dims its whole row with a
	# single modulate instead of every child needing its own colour.
	var content := Control.new()
	content.anchor_right  = 1.0
	content.anchor_bottom = 1.0
	content.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	if btn.disabled:
		content.modulate = Color(1, 1, 1, ATTACK_DISABLED_ALPHA)
	btn.add_child(content)

	# ── Energy cost, pinned left and vertically centred ──
	var cost_types := _attack_cost_types(attack)
	var x := pad_x
	for type_name in cost_types:
		var icon := TextureRect.new()
		icon.texture = load(ENERGY_ICON_DIR + "color_icon_" + String(type_name).to_lower() + ".png")
		icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.anchor_top    = 0.5
		icon.anchor_bottom = 0.5
		icon.offset_left   = x
		icon.offset_right  = x + icon_px
		icon.offset_top    = -icon_px * 0.5
		icon.offset_bottom = icon_px * 0.5
		content.add_child(icon)
		x += icon_px + ATTACK_COST_GAP * scale

	var cost_w := _attack_cost_width(attack, scale)

	# ── Damage, pinned right ──
	var dmg := String(attack.get("damage", ""))
	var dmg_w: float = 0.0
	if dmg != "":
		dmg_w = font.get_string_size(dmg, HORIZONTAL_ALIGNMENT_LEFT, -1, dmg_font).x
		var dmg_lbl := Label.new()
		dmg_lbl.text = dmg
		dmg_lbl.add_theme_font_override("font", font)
		dmg_lbl.add_theme_font_size_override("font_size", dmg_font)
		dmg_lbl.add_theme_color_override("font_color", Color(0, 0, 0, 1))
		dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dmg_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		dmg_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dmg_lbl.anchor_left   = 1.0
		dmg_lbl.anchor_right  = 1.0
		dmg_lbl.anchor_bottom = 1.0
		dmg_lbl.offset_left   = -(pad_x + dmg_w)
		dmg_lbl.offset_right  = -pad_x
		content.add_child(dmg_lbl)

	# ── Name, centred in whatever is left between the two ──
	# Centred rather than left-aligned so names line up down the column of buttons
	# instead of jogging sideways with each attack's cost count — and because that
	# is how the name sits on the printed card.
	var left_edge := pad_x + cost_w + (sect_gap if cost_w > 0.0 else 0.0)
	var right_edge := pad_x + dmg_w + (sect_gap if dmg_w > 0.0 else 0.0)
	var name_space: float = btn_w - left_edge - right_edge

	# Step the size down until the name fits the gap, exactly the way
	# DynamicMessageBox.set_body_text() fits a long line into a fixed panel.
	var name_size := name_ceiling
	while name_size > ATTACK_NAME_MIN_FONT \
			and font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > name_space:
		name_size -= 1

	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.add_theme_font_override("font", font)
	name_lbl.add_theme_font_size_override("font_size", name_size)
	name_lbl.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.anchor_right  = 1.0
	name_lbl.anchor_bottom = 1.0
	name_lbl.offset_left   = left_edge
	name_lbl.offset_right  = -right_edge
	content.add_child(name_lbl)

# Clears generated attack buttons and restores the main action buttons
func hide_attack_buttons() -> void:
	for child in attack_buttons_container.get_children():
		# Skip the cancel button — it's a permanent node, not dynamically generated
		if child.name == "cancel_attack_mode_button":
			continue
		attack_buttons_container.remove_child(child)
		child.queue_free()

	# Put back everything _render_attack_page() may have squeezed for a crowded
	# card, so the next Pokemon starts from the authored layout rather than
	# inheriting the last one's tight spacing.
	attack_buttons_container.add_theme_constant_override("separation", int(ATTACK_SEP_BASE))
	var cancel := attack_buttons_container.get_node_or_null("cancel_attack_mode_button")
	if cancel != null:
		cancel.custom_minimum_size.x = ATTACK_CANCEL_W_ROOMY
	_attack_list = []
	_attack_page = 0

	attack_buttons_container.visible = false
	main_buttons_container.visible = true

# ISSUE #121 FIX: the in-match box was still the old stretched PNG (bluesquaremessagebox.png).
# That art has since been re-cut as a render of the NEW dynamic box -- chip row and all -- so
# stretching it across the bottom of the board drew a huge panel with two dead "header" chips
# baked into its top-left corner. The match now builds a real DynamicMessageBox in its plainest
# form: no chips, no buttons, no speaker -- exactly the box a sign or other interactable gets in
# the overworld -- but wearing the CURRENT OPPONENT'S colour rather than the neutral grey.
#
# Built on first use rather than in _ready() so it cannot race the @onready node lookups above.
func _ensure_match_msgbox() -> DynamicMessageBox:
	if _match_msgbox != null and is_instance_valid(_match_msgbox):
		return _match_msgbox
	_match_msgbox = DynamicMessageBox.new()
	_match_msgbox.configure(MATCH_MSGBOX_HEIGHT, MATCH_MSGBOX_FONT_SIZE, false)
	# show_as_plain() first: it drops both chip rows, which is what keeps the box chipless.
	# apply_theme() after it, because show_as_plain() resets the colour to the default grey.
	_match_msgbox.show_as_plain()
	_match_msgbox.apply_theme(_match_msgbox_theme_key())
	_match_msgbox.visible = true   # msgbox_container's visibility is what gates the box
	msgbox_container.add_child(_match_msgbox)
	msgbox_texture.visible = false
	msgbox_label.visible   = false
	return _match_msgbox

# ISSUE #121 (improve further): the box wears the beaten-in-battle opponent's `message_colour`, the
# same key the outro screen themes its dialogue and reward panels with (Match_End_Outro_Script), so
# the whole match reads as one screen in that trainer's colour. load_opponent_data_by_name() has
# already merged All_NPC_Constant_Data.json into opponent_data by the time any message shows; an
# unset or unknown key falls back to the default grey inside apply_theme().
## The in-match box takes the UI ACCENT, not the opponent's colour.
##
## The user's split: overworld boxes stay per-speaker (each NPC carries its own
## `message_colour`), while in-match boxes join the theme. A match message is the
## GAME talking — "Staryu used Slap", "Flip a coin" — not the opponent, so
## wearing their colour was always slightly wrong.
##
## The match log follows the same key so the box and its history match.
func _match_msgbox_theme_key() -> String:
	return MATCH_MSGBOX_THEME

# Displays the message box with given text and pauses execution until the player clicks
func show_message(message_text: String) -> void:
	_log_match_message(message_text)
	var box := _ensure_match_msgbox()
	# ISSUE #121: re-asserted on every show, exactly like the overworld box does in
	# MapManager._apply_actor_chips() -- the box may have been built before the opponent data
	# finished loading, and a best-of-3 series can swap opponents under a live box.
	box.apply_theme(_match_msgbox_theme_key())
	# Match messages have always been centred in their box; the dynamic box is left-aligned by
	# default, so centre it the same way _show_large_message_with_ok does in the overworld.
	box.set_body_text("[center]" + message_text + "[/center]", MATCH_MSGBOX_FONT_SIZE)
	msgbox_container.visible = true
	await message_acknowledged
	msgbox_container.visible = false
	# ISSUE #37 REVERTED (2026-07-22): the post-message pause added here was a bad change
	# (user feedback) — it inserted a delay after EVERY message box. Removed entirely so
	# messages dismiss instantly again.


# ============================================================
# MATCH LOG — Caps Lock message history
# ============================================================
# Records one message. Called from show_message() only, which is the single
# funnel every in-match message goes through, so no effect script had to change.
#
# The entry is stamped with the turn it happened on and whose turn that was.
# Neither is available at the ~3,000 call sites and neither needs to be: the
# match already tracks both, so this reads them here for free. turn_number only
# increments at the PLAYER's turn start (player_start_turn_checks), which makes
# it a round number shared by both halves of a round — exactly what a divider
# wants written on it.
func _log_match_message(message_text: String) -> void:
	var trimmed := message_text.strip_edges()
	if trimmed == "":
		return
	_match_log.append({
		"text": trimmed,
		"turn": turn_number,
		"opp":  opponents_turn_active,
	})
	if _match_log.size() > MATCH_LOG_MAX_ENTRIES:
		_match_log = _match_log.slice(_match_log.size() - MATCH_LOG_MAX_ENTRIES)


func _toggle_match_log() -> void:
	if match_log_open:
		_close_match_log()
	else:
		_open_match_log()


func _open_match_log() -> void:
	if match_log_open:
		return
	match_log_open = true
	# The other half of the "this overlay owns the board" guard: card nodes sit
	# deeper in the tree so their _input runs BEFORE this script's, and
	# set_input_as_handled() cannot reach them. Same pattern the card preview uses.
	CardDisplay.input_blocked = true

	_match_log_layer = CanvasLayer.new()
	_match_log_layer.layer = MATCH_LOG_LAYER
	add_child(_match_log_layer)

	_match_log_panel = MatchLogPanel.new()
	_match_log_layer.add_child(_match_log_panel)
	_match_log_panel.configure(_match_msgbox_theme_key(), GameState.current_opponent_name)
	_match_log_panel.set_entries(_match_log)
	_match_log_panel.scroll_to_bottom()


func _close_match_log() -> void:
	if not match_log_open:
		return
	match_log_open = false
	CardDisplay.input_blocked = false
	_match_log_panel = null
	if _match_log_layer != null and is_instance_valid(_match_log_layer):
		_match_log_layer.queue_free()
	_match_log_layer = null


# Changes the deck icon to show how many cards remain.
# Draws ceil(count/5) stacked sleeve images, each offset -2px on x, to suggest depth.
func update_deck_icon(is_opponent: bool) -> void:
	var deck = opponent_deck if is_opponent else player_deck
	var widget = opponent_deck_icon if is_opponent else player_deck_icon
	var count = deck.size()

	var count_label = widget.get_node("opponent_deck_count_label") if is_opponent else widget.get_node("player_deck_count_label")
	count_label.text = str(count)

	# Remove previously stacked sleeve children
	for child in widget.get_children():
		if child.get_meta("sleeve_stack", false):
			child.queue_free()
	widget.texture = null

	if count == 0:
		return

	var sleeve_tex: Texture2D = opponent_card_back_texture if is_opponent else card_back_texture
	if sleeve_tex == null:
		return

	var stack_count = ceili(count / 5.0)

	# Add from back to front so the front card (i=0) is drawn last (on top).
	# Positive x offset so cards peek to the right, giving a deck-of-cards depth.
	# Each card is wrapped in a dark ColorRect border (1px on all sides).
	for i in range(stack_count - 1, -1, -1):
		var border = ColorRect.new()
		border.set_meta("sleeve_stack", true)
		border.color = opponent_sleeve_border_color if is_opponent else player_sleeve_border_color
		border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		border.offset_left = i * 2
		border.offset_right = i * 2
		border.mouse_filter = MOUSE_FILTER_IGNORE

		var card = TextureRect.new()
		card.texture = sleeve_tex
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_SCALE
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.offset_left = 1
		card.offset_right = -1
		card.offset_top = 1
		card.offset_bottom = -1
		card.mouse_filter = MOUSE_FILTER_IGNORE

		border.add_child(card)
		widget.add_child(border)

	# Keep count label rendered on top of all stacked cards
	widget.move_child(count_label, -1)

# ISSUE #42: a little riffle-shuffle animation on a deck icon. The deck is drawn as a stack of
# card-back "sleeve_stack" borders (see update_deck_icon), each 2px to the right of the one below.
# Per cycle: every 2nd card lifts up 100px + shifts 2px left (z+1) while the rest shift 2px right
# (z-1), then the lifted cards drop back down — repeated 4× so it reads as a riffle. The whole thing
# runs in ~1s, scaled by the card-match animation speed. Rebuilds the icon at the end to reset state.
func animate_deck_shuffle(is_opponent: bool) -> void:
	var widget = opponent_deck_icon if is_opponent else player_deck_icon
	var stack: Array = []
	for child in widget.get_children():
		if child.get_meta("sleeve_stack", false):
			stack.append(child)
	if stack.is_empty():
		# Nothing to riffle (empty/near-empty deck) — still pause so callers can await a beat.
		await get_tree().create_timer(GameState.match_time(0.3)).timeout
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_card_draw_sound)
	var cycles := 4
	var step := GameState.match_time(1.0) / float(cycles * 2)
	for _c in range(cycles):
		var up_tween := create_tween().set_parallel(true)
		for i in stack.size():
			var node = stack[i]
			if not is_instance_valid(node):
				continue
			if i % 2 == 1:
				node.z_index += 1
				up_tween.tween_property(node, "offset_top",    node.offset_top - 100.0, step)
				up_tween.tween_property(node, "offset_bottom", node.offset_bottom - 100.0, step)
				up_tween.tween_property(node, "offset_left",   node.offset_left - 2.0, step)
				up_tween.tween_property(node, "offset_right",  node.offset_right - 2.0, step)
			else:
				node.z_index -= 1
				up_tween.tween_property(node, "offset_left",  node.offset_left + 2.0, step)
				up_tween.tween_property(node, "offset_right", node.offset_right + 2.0, step)
		await up_tween.finished
		var down_tween := create_tween().set_parallel(true)
		for i in stack.size():
			var node = stack[i]
			if not is_instance_valid(node):
				continue
			if i % 2 == 1:
				down_tween.tween_property(node, "offset_top",    node.offset_top + 100.0, step)
				down_tween.tween_property(node, "offset_bottom", node.offset_bottom + 100.0, step)
		await down_tween.finished
	# Rebuild the icon so positions and z-order snap back to a clean stack.
	update_deck_icon(is_opponent)

# Enables or disables all main screen buttons based on current game state
func update_main_screen_buttons() -> void:
	var should_disable = (
		match_just_started_basic_pokemon_required or
		bench_setup_phase_active or
		card_selection_mode_enabled or
		opponents_turn_active or
		card_attach_mode_active or
		evolution_mode_active or
		retreat_mode_active or
		retreat_bench_selection_active or
		trainer_pokemon_selection_active or
		trainer_discard_selection_active or
		trainer_deck_search_active or
		power_menu_active
	)

	# Only End Turn is left on the footer; attacks, powers and retreat are rows on
	# the Pokemon and disable themselves per row.
	if _end_turn_btn != null and is_instance_valid(_end_turn_btn):
		_end_turn_btn.disabled = should_disable
		# ISSUE #229: hidden, not merely greyed, before there is an Active to end a
		# turn with and behind any full-screen selection.
		_end_turn_btn.visible = not (card_selection_mode_enabled
			or match_just_started_basic_pokemon_required or bench_setup_phase_active
			or _card_showcase_active or game_is_over)

	# ISSUE #217 (retest): THE ROWS WERE NEVER REBUILT WHEN THE TURN CHANGED.
	#
	# _player_can_act_now() / _player_can_attack_now() were correct, but the only
	# thing that calls them is _build_action_panel, and the only thing that calls
	# THAT is display_pokemon() - which runs when the board contents change, not
	# when whose-turn-it-is changes. So the rows kept whatever enabled state they
	# were built with at the end of the player's turn and stayed pressable right
	# through the opponent's. update_main_screen_buttons() is already called from
	# every turn transition and every mode change, which makes it the right place
	# to refresh them: the End Turn button and the rows can no longer disagree.
	_refresh_action_panels()


## ISSUE #217: rebuild both action panels against the CURRENT turn state.
func _refresh_action_panels() -> void:
	if _player_action_panel == null or not is_instance_valid(_player_action_panel):
		return
	_build_action_panel(false)
	_build_action_panel(true)

# Updates the discard pile icon to show the top card and count for the specified player
func update_discard_pile_display(is_opponent: bool) -> void:
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	var icon = opponent_discard_icon if is_opponent else player_discard_icon
	var label_name = "opponent_discard_pile_label" if is_opponent else "player_discard_pile_label"
	
	icon.get_node(label_name).text = str(discard.size())
	
	for child in icon.get_children():
		if child is TextureRect:
			child.queue_free()
	
	if discard.size() == 0:
		return
	
	
	var top_card = discard.back()
	var top_display = TextureRect.new()
	top_display.set_script(card_display_script)
	top_display.mouse_filter = MOUSE_FILTER_IGNORE
	icon.add_child(top_display)
	# ISSUE #220: PILE_SIZE, not a hardcoded 110x141 — the discard's top card was
	# drawing bigger than the deck beside it, so the two piles did not read as a
	# pair.
	top_display.load_card_image(top_card.uid, PILE_SIZE, top_card)
	icon.move_child(icon.get_node(label_name), -1)

## ISSUE #218: TWEAKABLE — the rendered height of one status icon. The width is
## derived from the art so nothing is ever stretched.
## ISSUE #267: 30 -> 28.5 (-5%). The art is ~3.18:1, so an icon is 3.18 x this
## wide: three of them plus two STATUS_ICON_GAPs come to 3*90.7 + 2*6 = 284, which
## is ACTION_PANEL_W exactly. Three conditions at once therefore fill the same
## width as the attack buttons under them instead of overrunning them, which is
## what 30 (297px for three) was doing.
const STATUS_ICON_H := 28.5
## ISSUE #218: space between two icons when more than one condition is on.
const STATUS_ICON_GAP := 6

## ISSUE #224: the active's "30 / 50" readout, a little larger than the bench's.
const ACTIVE_HP_FONT := 24

# Clears and rebuilds status condition icons for a pokemon's status container
func update_status_icons(pokemon: card_object, is_opponent: bool) -> void:
	var container = opponent_status_container if is_opponent else player_status_container
	for child in container.get_children():
		child.queue_free()

	var icons_to_show: Array = []

	if pokemon.special_condition == "Paralyzed":
		icons_to_show.append("status_paralyzed.png")
	if pokemon.special_condition == "Asleep":
		icons_to_show.append("status_asleep.png")
	if pokemon.special_condition == "Confused":
		icons_to_show.append("status_confused.png")
	if pokemon.is_poisoned and pokemon.poison_damage == 10:
		icons_to_show.append("status_poisoned.png")
	if pokemon.is_poisoned and pokemon.poison_damage == 20:
		icons_to_show.append("status_toxic.png")
	if pokemon.is_burned:
		icons_to_show.append("status_burned.png")
	if pokemon.is_blind:
		icons_to_show.append("status_blind.png")
	if pokemon.has_no_damage:
		icons_to_show.append("status_no_damage.png")
	if pokemon.is_invincible:
		icons_to_show.append("status_invincible.png")
	if pokemon.has_destiny_bond:
		icons_to_show.append("status_destiny_bond.png")
	if pokemon.shielded_damage_threshold > 0:
		icons_to_show.append("status_shielded_damage.png")

	# ISSUE #218: the icons were forced into a 100x30 box — three times wider than
	# they are tall — so every one of them was stretched into a smear across the
	# info column. The HEIGHT is fixed now and the width follows the art's own
	# aspect, which is the same rule the card-search chips and the match log's
	# sprite use.
	# ISSUE #218 (retest): THE ASPECT MATHS WAS ALWAYS RIGHT - THE CONTAINER WAS
	# OVERRULING IT. player_active_pokemon_status_container is a VBoxContainer, and
	# a BoxContainer stretches every child to its cross-axis width unless the child
	# says otherwise. A TextureRect defaults to SIZE_FILL, so each icon was being
	# blown back out to the full column width (322px, now ACTION_PANEL_W) on the
	# very next layout pass, no matter what size or minimum the code had just set.
	# That is why "nothing has changed".
	#
	# Two changes: the icons go in a centred HBox ROW (several conditions at once
	# read as a row of badges, not a stack taller than the panel it lives in), and
	# every icon is SHRINK_CENTER so the layout engine has nothing left to stretch.
	var row := HBoxContainer.new()
	# ISSUE #262: same inner-edge rule as the HP readout and the damage counters -
	# the first icon touches the active card and any extra ones grow outward.
	row.alignment = (BoxContainer.ALIGNMENT_BEGIN if is_opponent
		else BoxContainer.ALIGNMENT_END)
	row.add_theme_constant_override("separation", STATUS_ICON_GAP)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(row)

	for icon_file in icons_to_show:
		var tex: Texture2D = load("res://Image_Assets/Icons/Status_Icons/" + icon_file)
		if tex == null:
			continue
		var t := tex.get_size()
		var w: float = STATUS_ICON_H * (t.x / maxf(t.y, 1.0))
		var icon = TextureRect.new()
		icon.texture = tex
		icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.custom_minimum_size = Vector2(w, STATUS_ICON_H)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

############################################################### END DISPLAY FUNCTIONS ################################################################
######################################################################################################################################################

#	   ##      ####    ##  ########      ##      ##          ##    ########  ########
#     ####     ## ##   ##     ##        ####    ####        ####      ##     ##
#    ##  ##    ##  ##  ##     ##       ##  ##  ##  ##      ##  ##     ##     ########
#   ########   ##   ## ##     ##      ##    ####    ##    ########    ##     ##
#  ##      ##  ##    ####  ########  ##      ##      ##  ##      ##   ##     ########

######################################################################################################################################################
################################################################ ANIMATION FUNCTIONS #################################################################

## ISSUE #279: the TYPE SIZE is an argument now.
##
## Every floating label on the board was 36pt with a 10px outline, which is right
## for "Start turn" across an empty corner and far too heavy for a damage figure
## that has to sit beside a Pokemon without covering it. The damage and modifier
## labels pass FLOAT_DAMAGE_FONT; everything else keeps the old numbers by
## default, so no other caller changes. TWEAKABLE.
## ISSUE #288: how long the match board takes to fade up from black. Doubled from
## 0.5 alongside FADE_TIME on the intro, outro and best-of-three screens, so every
## boundary in the sequence moves at the same pace. TWEAKABLE.
const MATCH_FADE_IN_TIME := 1.0

const FLOAT_LABEL_FONT    := 36
const FLOAT_LABEL_OUTLINE := 10
## Half size, and the outline halves with it - an outline that does not scale
## with the glyph swallows a small one whole.
const FLOAT_DAMAGE_FONT    := 18
const FLOAT_DAMAGE_OUTLINE := 5

# Creates a floating label at a given position that drifts upward and fades out over 2 seconds
func show_floating_label(message: String, spawn_position: Vector2, label_color: Color = Color.WHITE, upwards: bool = true, font_size: int = FLOAT_LABEL_FONT, outline: int = FLOAT_LABEL_OUTLINE) -> void:
	var label = Label.new()
	label.text = message
	
	# uncomment these to make it centrally aligned instead of left aligned
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(300, 0)
	
	label.position = spawn_position
	label.modulate = Color(1, 1, 1, 1)
	
	# Apply kenney theme for the pixel font, then override colour and size
	label.theme = theme_disabled
	label.add_theme_color_override("font_color", label_color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_font_size_override("font_size", font_size)
	
	add_child(label)
	
	var tween = create_tween()
	tween.set_parallel(true)
	# ISSUE #34: the drift and the fade run in parallel, so both scale together with the speed preset.
	var drift_time := GameState.match_time(2.5)
	var fade_time  := GameState.match_time(1.5)
	if upwards:
		tween.tween_property(label, "position:y", spawn_position.y - 250, drift_time)
	else:
		tween.tween_property(label, "position:y", spawn_position.y + 250, drift_time)
	tween.tween_property(label, "modulate:a", 0.0, fade_time)
	
	await tween.finished
	label.queue_free()

# Animates a card back image sliding from one node's position to another
# ISSUE #20 FIX ACTIVE: the moving card now glides to the ACTUAL destination slot and
# morphs to that slot's size along the way, instead of shooting to the parent container's
# centre and then popping to a new size when the board refreshes.
#   • target_size (optional)  — the size the card should end at; when given, the ghost tweens
#                               its size from custom_size → target_size in parallel with its
#                               position, so there is no size "jump" on the board refresh.
#   • target_pos_override (optional) — the exact top-left the card should arrive at (e.g. a
#                               specific bench slot). When supplied we use it verbatim rather
#                               than centring on the container. Callers that know the real
#                               destination (bench/active/evolve placements) pass this via
#                               get_pokemon_screen_location().
# Tween duration is also lengthened by 50% for a smoother glide (0.3s → 0.45s etc).
const _ANIM_POS_SENTINEL := Vector2(-99999, -99999)

## ISSUE #250: CARDS MOVE AT A SPEED, NOT FOR A TIME.
##
## Every call used to name a DURATION, so a card nudging 40px into a tool slot
## and a card crossing the whole board both took the same 0.45s - which means the
## long one was moving twenty times faster than the short one and was impossible
## to follow. A single px/sec rate makes every move read at the same pace and
## turns distance into time, which is the way round a viewer expects. The two
## clamps keep a 30px nudge from being instant and a corner-to-corner flight from
## becoming a journey. ALL THREE TWEAKABLE.
const ANIM_PX_PER_SEC := 2100.0
const ANIM_MIN_TIME   := 0.20
const ANIM_MAX_TIME   := 0.95
## ISSUE #236: how far through the flight the card drops behind the board, and
## what z it drops to. 0.82 is "as it reaches the card", not on arrival.
const ANIM_SINK_AT  := 0.82
const ANIM_BEHIND_Z := -3

## ISSUE #243: ONE CARD IN THE AIR AT A TIME.
##
## "At the end of a turn when tools are being discarded, finish this animation
## before drawing a card." The end-of-turn hooks do await each other, but nothing
## stopped a caller that FORGOT to await (animate_energies_to_discard is one)
## from launching a second flight over the first - and two overlapping flights
## also fight over animation_blocker, so the first one to land unblocks the board
## while the second is still moving. Serialising here fixes both at the source and
## costs nothing when calls are already sequential.
var _anim_in_flight: bool = false

## ISSUE #241: where a card ACTUALLY ends up when the caller did not say.
##
## Callers that pass no target_size used to leave the ghost at its starting size,
## so a 405px active card "arriving" at the 77px discard pile simply vanished and
## reappeared as a pile - the snapping the fix describes. Every destination on
## this board has a known card size; this is the table.
func _anim_dest_size(to_node: Control, fallback: Vector2) -> Vector2:
	if to_node == null or not is_instance_valid(to_node):
		return fallback
	if to_node == player_deck_icon or to_node == opponent_deck_icon \
			or to_node == player_discard_icon or to_node == opponent_discard_icon:
		return PILE_SIZE
	if to_node == player_active_container or to_node == opponent_active_container:
		return ACTIVE_CARD
	if to_node == player_bench_container or to_node == opponent_bench_container:
		return BENCH_CARD
	if to_node == player_energy_container or to_node == opponent_energy_container \
			or to_node == player_attached_cards_container \
			or to_node == opponent_attached_cards_container:
		return ATTACH_CARD_SIZE
	if to_node == player_hand_container:
		return card_scales[11]
	if to_node == opponent_hand_container:
		return OPP_HAND_CARD
	if to_node == player_prize_container or to_node == opponent_prize_container:
		return PRIZE_SIZE
	return fallback

## `arrive_behind` (ISSUE #236): the card flies OVER everything, then drops
## behind the board for the last stretch, so it slides in UNDER the Pokemon it is
## being attached to instead of landing on top of it and vanishing. That is how
## an attached tool or energy is actually drawn - peeking out from behind the
## card - so the animation now ends in the same reading the board gives.
## `from_pos_override` (ISSUE #280 / #283): the exact top-left the card STARTS
## from. Every caller used to hand over a CONTAINER - the hand box, the Active's
## card - so a card played out of the middle of your hand took off from the left
## edge of the hand, and an energy being discarded took off from the Pokemon it
## was attached to rather than from the energy card itself. The card's own node is
## usually gone by the time the flight starts (the caller erases and refreshes
## first, and it must), so the position has to be MEASURED BEFORE that and passed
## in - which is what _card_rect_now() is for.
func animate_card_a_to_b(from_node: Control, to_node: Control, animation_speed: float = 0.8, custom_texture: Texture2D = null, custom_size: Vector2 = Vector2(83, 113), target_size: Vector2 = Vector2.ZERO, target_pos_override: Vector2 = _ANIM_POS_SENTINEL, arrive_behind: bool = false, from_pos_override: Vector2 = _ANIM_POS_SENTINEL) -> void:
	# ISSUE #243: queue behind any flight already in the air.
	while _anim_in_flight:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_anim_in_flight = true

	# ISSUE #249: LET THE BOARD CATCH UP BEFORE THE CARD LEAVES.
	#
	# "As soon as the card starts to move it should already have been removed from
	# its old array and the screen refreshed." The callers do erase and refresh
	# first - but a refresh is only a rebuild of Control children, which does not
	# reach the screen until the frame ends. Starting the tween in the same frame
	# meant the card was visibly in two places for one frame, and a message box
	# opened on the same frame described a board that had not been drawn yet.
	# One frame of settle makes "remove, redraw, THEN move" true rather than
	# merely intended.
	await get_tree().process_frame

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_card_draw_sound)
	animation_blocker.visible = true
	# ISSUE #241: fall back to the DESTINATION's own card size, not the source's.
	var final_size: Vector2 = target_size if target_size != Vector2.ZERO \
		else _anim_dest_size(to_node, custom_size)
	var card_image = TextureRect.new()
	card_image.texture = custom_texture if custom_texture else card_back_texture
	card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_image.custom_minimum_size = custom_size
	card_image.size = custom_size
	card_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ISSUE #240: THE CHROME BARS DREW OVER THE MOVING CARD.
	#
	# The bars sit at Z_CHROME (200) and the ghost was at 100, so any card flying
	# to or from the hand, the deck or the discard - all of which live ON a bar -
	# disappeared behind one for the last third of its journey. Above the bars,
	# like the hand and the message box already are (#213).
	card_image.z_index = UIKit.Z_CHROME + 20
	add_child(card_image)

	# ISSUE #280 / #283: start where the card actually IS, when the caller knows.
	card_image.global_position = from_pos_override if from_pos_override != _ANIM_POS_SENTINEL 		else from_node.global_position
	var target_pos: Vector2
	if target_pos_override != _ANIM_POS_SENTINEL:
		target_pos = target_pos_override
	else:
		# Centre the card horizontally on the destination node. (The old code left-aligned the
		# card at the node's mid-x, so it landed half a card-width to the right of centre.)
		target_pos = to_node.global_position + Vector2(to_node.size.x / 2 - final_size.x / 2, 0)

	# ISSUE #250: distance decides the time. `animation_speed` is kept in the
	# signature - 75 call sites pass it - but it is a RELATIVE nudge now rather
	# than the duration itself, normalised on the 0.3 that most callers use.
	# ISSUE #34: still scaled by the global card-match animation-speed multiplier.
	var distance: float = card_image.global_position.distance_to(target_pos)
	var base_time: float = clampf(distance / ANIM_PX_PER_SEC, ANIM_MIN_TIME, ANIM_MAX_TIME)
	var duration = GameState.scaled_duration(base_time * (animation_speed / 0.3),
		GameState.card_match_animation_speed)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card_image, "global_position", target_pos, duration).set_ease(Tween.EASE_IN_OUT)
	if final_size != custom_size:
		tween.tween_property(card_image, "size", final_size, duration).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(card_image, "custom_minimum_size", final_size, duration).set_ease(Tween.EASE_IN_OUT)
	# ISSUE #236: the hand-off point, on a tween of its own so it fires DURING the
	# flight rather than after it. Scales with the duration, so it stays "as the
	# card reaches the Pokemon" at every animation speed.
	if arrive_behind:
		var sink := create_tween()
		sink.tween_interval(duration * ANIM_SINK_AT)
		sink.tween_callback(_sink_behind_board.bind(card_image))
	tween.set_parallel(false)
	tween.tween_callback(card_image.queue_free)
	await tween.finished
	animation_blocker.visible = false
	_anim_in_flight = false


## ISSUE #236: drops a moving card behind the board mid-flight.
func _sink_behind_board(node: CanvasItem) -> void:
	if node != null and is_instance_valid(node):
		node.z_index = ANIM_BEHIND_Z


## ISSUE #236: ONE PLACE THAT KNOWS WHERE AN ATTACHMENT LANDS.
##
## Every tool attach in Trainer_Effects flew the card to the ACTIVE Pokemon's tool
## container - `attached_node` - whatever it had actually been attached to. So
## attaching a Focus Band to a benched Pokemon sent the card to the far side of
## the board, to a stack it was never going to join, and then it popped into
## existence on the bench when the board refreshed. That is the bug as reported.
##
## The Active still measures its real slot in the tool stack (#54); a benched
## Pokemon gets its own slot rect (#236) at bench card size, and arrives BEHIND
## the card it is attaching to.
##
## `card_display_node` is the tool/energy card that has ALREADY been appended to
## the target - call this after the append, like the Active path always has.
func animate_attach_to_pokemon(card: card_object, target: card_object,
		is_opponent: bool, from_node: Control) -> void:
	var texture := get_card_texture(card)
	var active := opponent_active_pokemon if is_opponent else player_active_pokemon
	if target == active:
		var attached_node = opponent_attached_cards_container if is_opponent else player_attached_cards_container
		var rect := measure_and_hide_new_active_tool_slot(is_opponent)
		await animate_card_a_to_b(from_node, attached_node, 0.3, texture, card_scales[10],
			rect.get("size", ATTACH_CARD_SIZE), rect.get("position", _ANIM_POS_SENTINEL))
		return

	var bench_container = opponent_bench_container if is_opponent else player_bench_container
	var loc := get_pokemon_screen_location(target)
	await animate_card_a_to_b(from_node, bench_container, 0.3, texture, card_scales[10],
		loc.get("size", BENCH_CARD), loc.get("position", _ANIM_POS_SENTINEL), true)

# Animate discarding for reatreat and knockout
#
# ISSUE #280: EACH ENERGY LEAVES FROM ITS OWN CARD, NOT FROM THE POKEMON.
#
# `from_node` was the POKEMON's card for every energy in the stack, so a discard
# always took off from the Active slot however far the energy actually sat from
# it - and the peek-stack fans a whole ATTACH_STACK_SPAN (300px) out to the side,
# so the card visibly jumped to the Pokemon before starting to move. Each energy's
# own rect is measured first, then the board is refreshed, then it flies: "hide
# the energy, then animate it from where it was" (which is also #285's first beat).
#
# ISSUE #285: each flight is AWAITED. The old loop fired an un-awaited animation
# and then slept 0.2s, which #243's serialisation turned into a queue running
# behind a timer that had nothing to do with it. Awaiting means the Pokemon's own
# flight (the caller's next step on a knockout) cannot start until the last energy
# has actually landed.
func animate_energies_to_discard(energy_cards: Array, pokemon: card_object, is_opponent: bool) -> void:
	var discard_node = opponent_discard_icon if is_opponent else player_discard_icon
	var discard_pile = opponent_discard_pile if is_opponent else player_discard_pile
	# The Pokemon's own rect, captured once, as the fallback for any energy that
	# has no card of its own on screen (a benched Pokemon's are not drawn). Taken
	# as a RECT rather than kept as a node because the refreshes inside the loop
	# can free it, and a freed from_node would take the flight down with it.
	var poke_rect := _card_rect_now(pokemon)
	if poke_rect.is_empty():
		return

	for energy in energy_cards:
		var energy_texture = get_card_texture(energy)
		# ISSUE #280: measured BEFORE the erase + refresh frees the energy's node.
		# A benched Pokemon's energies are not drawn as separate cards, so there is
		# nothing to measure there and the Pokemon's own rect stays the fallback.
		var energy_from := _card_rect_now(energy)

		# Remove this energy from the pokemon's attached list NOW,
		# so the redraw reflects one fewer energy each frame
		pokemon.attached_energies.erase(energy)

		# Actually add the energy to the discard pile array
		energy.current_location = "discard"
		discard_pile.append(energy)

		display_active_pokemon_energies(is_opponent)
		# ISSUE #79: refresh the discard pile visual after EVERY energy (not just at the end) so the
		# player sees each discarded energy land on the pile as it is discarded during retreat/KO.
		update_discard_pile_display(is_opponent)

		var start := energy_from if not energy_from.is_empty() else poke_rect
		print("ISSUE #280 FIX ACTIVE: discarding ", energy.metadata.get("name", "?"),
			" from ", start["position"], " (own card: ", not energy_from.is_empty(), ")")
		await animate_card_a_to_b(discard_node, discard_node, 0.2, energy_texture,
			start.get("size", card_scales[10]), Vector2.ZERO, _ANIM_POS_SENTINEL,
			false, start["position"])

	# Update the discard pile visual to show the new top card
	update_discard_pile_display(is_opponent)
				
# Animates a retreat or switch. Every path narrates in the same order: say what is about to
# happen, play the animation, then let the caller snap the board to its new state.
#
# Voluntary retreats read as two beats — "X RETREATED TO THE BENCH!" up front, then
# "...SET Y AS THEIR ACTIVE POKEMON!" once Y has physically arrived.
#
# Forced switches (Whirlwind, Warp Point, Switch, Gust of Wind, etc.) pass is_forced_switch and
# get a single up-front line instead, because the swap is one involuntary event rather than a
# retreat followed by a choice. Callers keep their own flavour messages ("HEADS! X SWITCHED IN!").
func animate_retreat(old_active: card_object, new_active: card_object, discarded_energies: Array, is_opponent: bool, is_forced_switch: bool = false) -> void:
	var active_container = opponent_active_container if is_opponent else player_active_container
	var bench_container = opponent_bench_container if is_opponent else player_bench_container
	var side_bench = opponent_bench if is_opponent else player_bench
	var switcher_label = "OPPONENT" if is_opponent else "PLAYER"

	# ── ISSUE #7 FIX ACTIVE: forced switches (Whirlwind, Gust, Warp Point, Switch, Poké-Powers,
	# etc.) read as ONE event: a single message, then the outgoing Pokémon glides down to the
	# Bench, the board updates, then the incoming Pokémon glides up into the Active slot. The two
	# cards no longer fly simultaneously and there is no second "forced to switch in" message.
	if is_forced_switch:
		print("ISSUE #7 FIX ACTIVE (animate_retreat forced): ", old_active.metadata.get("name",""), " <-> ", new_active.metadata.get("name",""), " is_opponent=", is_opponent)
		# ISSUE #7 diagnostic: if the player-forced switch STILL shows no animation, these positions
		# reveal whether the container globals are sane at this moment (a bad/zero pos = the culprit).
		print("ISSUE #7 diag: active_container.global_position=", active_container.global_position, " bench_container.global_position=", bench_container.global_position, " active_visible=", active_container.visible)
		var possessive = "OPPONENT'S" if is_opponent else "YOUR"
		await show_message(possessive + " " + old_active.metadata["name"].to_upper() + " SWITCHED WITH " + new_active.metadata["name"].to_upper() + "!")

		var old_tex = get_card_texture(old_active)
		var new_tex = get_card_texture(new_active)

		# 1) Hide the Active card and glide the outgoing Pokémon down to the Bench (shrinking to Bench size)
		# ISSUE #87: hides the HP squares along with the card.
		set_active_slot_visible(is_opponent, false)
		# ISSUE #242: A FORCED SWITCH IS A RETREAT AND MUST LOOK LIKE ONE.
		#
		# The sequencing was already shared with a voluntary retreat - what was not
		# shared was the geometry. Both flights were sized from card_scales[3.5] /
		# [11] (405x557 and 100x138), neither of which the board has drawn since the
		# overhaul, and both aimed at the bench CONTAINER's centre rather than at the
		# slot the Pokemon lands in. So the card was the wrong size the whole way and
		# then snapped somewhere else on arrival: "it doesn't follow the same
		# animation for retreating". Exact slot rect, exact sizes, both directions.
		var out_slot := _bench_slot_rect(maxi(side_bench.size() - 1, 0), bench_container)
		await animate_card_a_to_b(active_container, bench_container, 0.3, old_tex,
			ACTIVE_CARD, out_slot["size"], out_slot["position"])

		# 2) Apply the swap in data — but only if the caller hasn't already done it (most callers
		#    swap before calling; the few that swap afterwards have had that block removed).
		if new_active.current_location != "active":
			side_bench.erase(new_active)
			side_bench.append(old_active)
			old_active.current_location = "bench"
			new_active.current_location = "active"
			if is_opponent:
				opponent_active_pokemon = new_active
			else:
				player_active_pokemon = new_active
			clear_all_statuses(old_active, is_opponent)

		# 3) Refresh the board so it reflects the swap (Active kept hidden so the incoming card can fly in)
		display_pokemon(is_opponent)
		display_active_pokemon_energies(is_opponent)
		# ISSUE #87: display_pokemon re-shows the squares for the new Active, so re-hide the whole slot
		# until the incoming card has finished flying in.
		set_active_slot_visible(is_opponent, false)

		# 4) Glide the incoming Pokémon up into the Active slot, growing to Active size.
		# ISSUE #7 (player-forced retest): the container's global_position can resolve to the wrong
		# place for the PLAYER side at this moment (during the OPPONENT'S turn the layout differs),
		# so the incoming card flew off-slot and read as "no animation". Mirror the proven
		# knockout-replacement animation (handle_action_knockout_bench) by passing the EXPLICIT active
		# slot position + size from get_pokemon_screen_location, which works on BOTH sides.
		var active_loc = get_pokemon_screen_location(new_active)
		await animate_card_a_to_b(bench_container, active_container, 0.3, new_tex,
			BENCH_CARD, active_loc.get("size", ACTIVE_CARD),
			active_loc.get("position", _ANIM_POS_SENTINEL))

		# 5) Reveal the new Active
		set_active_slot_visible(is_opponent, true)
		display_active_pokemon_energies(is_opponent)
		return

	# ── Voluntary retreat (ISSUE #7): the ONE exception to "message first". Announce the retreat,
	# discard the retreat-cost Energy, then play the SAME sequential glide as a forced switch
	# (outgoing card down to the Bench, board updates, incoming card up into the Active slot), and
	# ONLY THEN confirm the new Active with a closing message. The two cards no longer fly at once.
	print("ISSUE #7 FIX ACTIVE (animate_retreat voluntary sequential): is_opponent=", is_opponent)
	await show_message(old_active.metadata["name"].to_upper() + " RETREATED TO THE BENCH!")

	if discarded_energies.size() > 0:
		await animate_energies_to_discard(discarded_energies, old_active, is_opponent)
		update_discard_pile_display(is_opponent)
		display_active_pokemon_energies(is_opponent)
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
	else:
		display_active_pokemon_energies(is_opponent)

	var old_texture = get_card_texture(old_active)
	var new_texture = get_card_texture(new_active)

	# 1) Hide the Active card and glide the outgoing Pokémon down to the Bench (shrinking to Bench size)
	# ISSUE #87: hides the HP squares along with the card.
	set_active_slot_visible(is_opponent, false)
	# ISSUE #242: same exact-slot geometry as the forced branch above.
	var retreat_slot := _bench_slot_rect(maxi(side_bench.size() - 1, 0), bench_container)
	await animate_card_a_to_b(active_container, bench_container, 0.3, old_texture,
		ACTIVE_CARD, retreat_slot["size"], retreat_slot["position"])

	# 2) The callers have already swapped the data arrays + current_location; ensure the Active
	#    pointer matches too (the player retreat caller only reassigns it AFTER this returns).
	if is_opponent:
		opponent_active_pokemon = new_active
	else:
		player_active_pokemon = new_active

	# 3) Refresh the board so it reflects the swap (Active kept hidden so the incoming card can fly in)
	display_pokemon(is_opponent)
	display_active_pokemon_energies(is_opponent)
	# ISSUE #87: re-hide the slot (display_pokemon just re-showed the squares) until the card lands.
	set_active_slot_visible(is_opponent, false)

	# 4) Glide the incoming Pokémon up into the Active slot, growing to Active size
	var incoming_loc := get_pokemon_screen_location(new_active)
	await animate_card_a_to_b(bench_container, active_container, 0.3, new_texture,
		BENCH_CARD, incoming_loc.get("size", ACTIVE_CARD),
		incoming_loc.get("position", _ANIM_POS_SENTINEL))

	# 5) Reveal the new Active, then the closing message (animation plays fully first)
	set_active_slot_visible(is_opponent, true)
	display_active_pokemon_energies(is_opponent)
	await show_message(switcher_label + " SET " + new_active.metadata["name"].to_upper() + " AS THEIR ACTIVE POKEMON!")

# Creates continuous sparkle particles around a given node, returns the node for manual cleanup
func start_sparkle_effect(target_node: Control) -> CPUParticles2D:
	var particles = CPUParticles2D.new()
	add_child(particles)
	
	particles.global_position = target_node.global_position + target_node.size / 2
	particles.z_index = 101
	particles.amount = 20
	particles.lifetime = 0.9
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.emitting = true

	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = target_node.size / 2
	
	particles.direction = Vector2(0, 0)
	particles.initial_velocity_min = 0.0
	particles.initial_velocity_max = 0.0
	particles.gravity = Vector2(0, 0)
	
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 6.0
	
	var sparkle_colour = get_coin_sparkle_colour()
	var bright = sparkle_colour.lightened(1)
	
	var gradient = Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, sparkle_colour)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(sparkle_colour.r, sparkle_colour.g, sparkle_colour.b, 0.0))
	particles.color_ramp = gradient
	
	return particles

# Each coin can be one of a few colours so make the sparkles match	
func get_coin_sparkle_colour() -> Color:
	var coin_name = tex_heads.resource_path.to_lower()
	if " red"    in coin_name: return Color(1.0, 0.2,  0.2)
	if " gold"   in coin_name: return Color(1.0, 0.85, 0.2)
	if " silver" in coin_name: return Color(0.85, 0.85, 0.9)
	if " blue"   in coin_name: return Color(0.3,  0.5,  1.0)
	if " green"  in coin_name: return Color(0.2,  0.9,  0.3)
	if " pink"   in coin_name: return Color(1.0,  0.2,  0.7)
	if " purple" in coin_name: return Color(0.55, 0.1,  1.0)
	if " black"  in coin_name: return Color(0.0,  0.0,  0.0)
	if " brown"  in coin_name: return Color(0.5,  0.3,  0.2)
	return Color(1.0, 1.0, 1.0)

# Returns a colour for a given Pokemon type string
func get_type_colour(type_name: String) -> Color:
	match type_name.to_lower():
		"fire": return Color(1.0, 0.2, 0.1)
		"water": return Color(0.2, 0.5, 1.0)
		"grass": return Color(0.2, 0.8, 0.3)
		"lightning": return Color(1.0, 0.9, 0.1)
		"darkness": return Color(0.15, 0.1, 0.2)
		"psychic": return Color(0.55, 0.1, 1)
		"metal": return Color(0.6, 0.6, 0.65)
		"fighting": return Color(0.5, 0.3, 0.2)
		"dragon": return Color(0.9, 0.7, 0.2)
		"fairy": return Color(1.0, 0.4, 0.7)
		_: return Color(1.0, 1.0, 1.0)

# Plays a one-shot upward particle burst over a pokemon card for evolution
# Determines a pokemon's screen position and size by checking against known game variables
# Returns {"position": Vector2, "size": Vector2, "is_active": bool} or empty dict if not found
# Returns a Dictionary view of one side's collections and UI nodes.
# Arrays are pass-by-reference so mutations through the dict affect the live arrays.
# Note: "active" is a snapshot — re-query after any KO or switch.
func get_side(is_opponent: bool) -> Dictionary:
	return {
		"active":              opponent_active_pokemon if is_opponent else player_active_pokemon,
		"bench":               opponent_bench if is_opponent else player_bench,
		"hand":                opponent_hand if is_opponent else player_hand,
		"deck":                opponent_deck if is_opponent else player_deck,
		"discard":             opponent_discard_pile if is_opponent else player_discard_pile,
		"prizes":              opponent_prize_cards if is_opponent else player_prize_cards,
		"tickled_set_aside":   opponent_tickled_set_aside if is_opponent else player_tickled_set_aside,
		"hand_container":      opponent_hand_container if is_opponent else player_hand_container,
		"bench_container":     opponent_bench_container if is_opponent else player_bench_container,
		"active_container":    opponent_active_container if is_opponent else player_active_container,
		"discard_icon":        opponent_discard_icon if is_opponent else player_discard_icon,
		"deck_icon":           opponent_deck_icon if is_opponent else player_deck_icon,
		"attached_container":  opponent_attached_cards_container if is_opponent else player_attached_cards_container,
		"is_opponent":         is_opponent,
	}

# Returns the side dict for whichever side owns the given card.
func get_owner_side(card: card_object) -> Dictionary:
	return get_side(card.is_owner_opp(self))

## ISSUE #173: REFRESH THE RIGHT POKEMON'S HP READOUT.
##
## display_hp_circles_above_align() only ever draws the ACTIVE Pokemon's readout —
## the container it writes into belongs to the active slot. Handing it a BENCHED
## Pokemon (which several effects did) repainted the active's HP with the bench
## Pokemon's numbers, so the active appeared to jump to 40/50 while the Pokemon
## that actually took the damage still showed 50/50.
##
## Use this from any effect that can hit either. A bench Pokemon's HP is drawn as
## part of its slot, so the whole side is rebuilt for it.
func refresh_pokemon_hp_display(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null:
		return
	var active := opponent_active_pokemon if is_opponent else player_active_pokemon
	if pokemon == active:
		display_hp_circles_above_align(pokemon, is_opponent)
	else:
		display_pokemon(is_opponent)


## ISSUE #173: a floating damage/heal label over the Pokemon it belongs to.
##
## The labels used to be spawned at a hardcoded x (1030 / 530) and y=300 — the two
## ACTIVE slots — so a bench Pokemon's damage was announced over the active's
## head. get_pokemon_screen_location() already knows where every Pokemon in play
## is drawn; this centres the label on that rect and falls back to the old fixed
## spot only when the Pokemon is not on the board at all.
## ISSUE #279: HOW FAR OUTWARD THE FIGURE SITS FROM THE CARD'S CENTRE.
##
## Centred on the card, a damage figure lands squarely on the Pokemon's art. The
## HP readout and the damage counters both live on the side of the card AWAY from
## the centre line (yours to the left, theirs to the right - see _place_duel_row),
## so pushing the label the same way lines it up with the number it is changing
## and clears the art at the same time. TWEAKABLE.
const FLOAT_LABEL_SIDE_NUDGE := 25.0

## ISSUE #281: BOTH TURN LABELS RISE OUT OF THE SAME PLACE.
##
## "Start turn" spawned top-LEFT at (50, 180) and drifted DOWN while "End turn"
## spawned bottom-right and drifted up - two opposite gestures for the two halves
## of one event, and neither was anywhere near the player's own corner after the
## overhaul moved the piles and prizes. They now both rise out of the gap just
## above the "You" caption in the bottom-right rail, which is the label that names
## whose turn it is about to be.
##
## Derived, not hardcoded: the caption itself is drawn at (RIGHT_RAIL_X,
## PILE_BOT_Y - 26) by _place_rails, so if the rail or the footer moves the labels
## follow. show_floating_label centres its text in a 300px box, hence the -150.
## TWEAKABLE: only the clearance above the caption.
const TURN_FLOAT_GAP := 46.0
static func _turn_float_anchor() -> Vector2:
	return Vector2(RIGHT_RAIL_X + RAIL_W * 0.5 - 150.0,
		PILE_BOT_Y - 26.0 - TURN_FLOAT_GAP)

func float_label_over(pokemon: card_object, text: String, colour: Color,
		is_opponent: bool = false) -> void:
	var loc := get_pokemon_screen_location(pokemon)
	# ISSUE #279: outward is LEFT for you and RIGHT for the opponent, matching the
	# side each one's HP block already sits on.
	var nudge: float = FLOAT_LABEL_SIDE_NUDGE if is_opponent else -FLOAT_LABEL_SIDE_NUDGE
	if loc.is_empty():
		show_floating_label(text,
			Vector2((1030.0 if is_opponent else 530.0) + nudge, 300.0), colour, true,
			FLOAT_DAMAGE_FONT, FLOAT_DAMAGE_OUTLINE)
		return
	var rect_pos: Vector2 = loc["position"]
	var rect_size: Vector2 = loc["size"]
	# show_floating_label centres its text in a 300px box, hence the -150.
	show_floating_label(text,
		Vector2(rect_pos.x + rect_size.x * 0.5 - 150.0 + nudge,
			rect_pos.y + rect_size.y * 0.35),
		colour, true, FLOAT_DAMAGE_FONT, FLOAT_DAMAGE_OUTLINE)


## ISSUE #236 / #241 / #242: THE SIZES HERE WERE PRE-OVERHAUL AND WRONG.
##
## It reported card_scales[3.5] (405x557) for an Active that is drawn at 230x319,
## and card_scales[11] (100x138) for a bench slot drawn at BENCH_CARD - and it
## stepped along the bench row by that wrong width too, so every bench slot past
## the first was reported further right than it is. Everything that aims an
## animation reads this, which is why cards "jump and appear in the new location
## when the card didn't move there to the right spot" (#241), why a Wail switch
## did not look like a retreat (#242), and why a card attached to a bench Pokemon
## flew to the wrong place (#236). It reports the sizes the board actually draws
## now, and the bench y accounts for the slot centring the card inside BENCH_ROW_H.
func get_pokemon_screen_location(pokemon: card_object) -> Dictionary:
	if pokemon == opponent_active_pokemon:
		return {"position": opponent_active_container.global_position, "size": ACTIVE_CARD, "is_active": true}
	elif pokemon == player_active_pokemon:
		return {"position": player_active_container.global_position, "size": ACTIVE_CARD, "is_active": true}
	elif pokemon in opponent_bench:
		return _bench_slot_rect(opponent_bench.find(pokemon), opponent_bench_container)
	elif pokemon in player_bench:
		return _bench_slot_rect(player_bench.find(pokemon), player_bench_container)
	return {}


## ISSUE #236: the exact on-screen rect of one bench slot's CARD.
##
## The row is always five slots wide and centred, so the step is the real card
## width plus the real gap. The card is not at the top of the slot either - the
## slot is a VBox centred inside BENCH_ROW_H with the counter row beneath it - so
## the y is nudged down by that padding.
func _bench_slot_rect(index: int, container: Control) -> Dictionary:
	var content_h: float = BENCH_CARD.y + float(BENCH_SLOT_SEP) + BENCH_COUNTER_H
	var top_pad: float = maxf((BENCH_ROW_H - content_h) * 0.5, 0.0)
	return {
		"position": container.global_position
			+ Vector2(float(index) * (BENCH_CARD.x + float(BENCH_GAP)), top_pad),
		"size": BENCH_CARD,
		"is_active": false,
	}

# ISSUE #40 FIX: build the real Active energy stack (so the just-appended energy occupies its true
# final slot), then return that slot's exact on-screen rect {position, size} AND hide the slot so an
# attaching-energy animation can fly a card INTO that exact spot without the final card also showing
# underneath it (which read as the energy snapping ~300px sideways / to the middle of the stack).
# Reveal happens via the normal display_active_pokemon_energies refresh once the animation lands.
# Returns {} if there is no Active energy to measure. Assumes the energy was already appended to the
# Active's attached_energies (the last child is therefore the newly-attached one).
func measure_and_hide_new_active_energy_slot(is_opponent: bool) -> Dictionary:
	display_active_pokemon_energies(is_opponent)
	var energy_container = opponent_energy_container if is_opponent else player_energy_container
	var count = energy_container.get_child_count()
	if count == 0:
		return {}
	var slot = energy_container.get_child(count - 1)
	var rect = {"position": slot.global_position, "size": slot.size}
	slot.visible = false
	return rect

# ISSUE #54: mirror of measure_and_hide_new_active_energy_slot for attached TOOL/trainer cards
# (PlusPower, Defender, …). Builds the real attached-trainer stack for the Active, returns the exact
# {position, size} of the just-appended (last) slot, and hides it so the incoming card can fly to its
# precise final spot instead of guessing the container's origin (which sat ~150-200px too low).
## ISSUE #280 / #283: WHERE A CARD IS RIGHT NOW, captured before it is erased.
##
## find_card_ui_for_object already walks the hands, the actives, the benches and
## the Active energy stacks, so any card the player can see has a node. The rect
## has to be taken BEFORE the caller erases the card and refreshes the board -
## a refresh frees the node - which is why this is a separate call rather than
## something animate_card_a_to_b could do for itself.
##
## Returns {} when the card has no node on screen; callers fall back to the
## container they used to pass, so nothing regresses if a card is not drawn.
func _card_rect_now(card_obj: card_object) -> Dictionary:
	if card_obj == null:
		return {}
	var node := find_card_ui_for_object(card_obj)
	if node == null or not is_instance_valid(node):
		return {}
	return {"position": node.global_position, "size": node.size}


## ISSUE #282: WHERE A DRAWN CARD ACTUALLY LANDS IN THE HAND.
##
## A draw flew to `player_hand_container` with no override, so it aimed at the
## CENTRE of the hand box and the card then popped to the end of the row when the
## board refreshed. The hand is a centred HBoxContainer, so the landing slot is
## not something that can be calculated - it depends on how many cards are in the
## hand and how tightly they are overlapping. So build the new hand first, let the
## container sort itself, and read the last slot's real rect off the screen.
##
## The new card is made TRANSPARENT rather than hidden, unlike the Active energy
## and tool stacks: hiding a child of a centred HBox drops it out of the layout
## and re-centres every other card in the hand, which would make the whole row
## shuffle sideways for the length of the flight. Alpha keeps the geometry.
## The caller's normal refresh puts the alpha back.
##
## Assumes the card is ALREADY appended to the hand array (so it is the last one).
func measure_and_hide_new_hand_slot(is_opponent: bool) -> Dictionary:
	var hand_container = opponent_hand_container if is_opponent else player_hand_container
	refresh_hand_display(is_opponent)
	# A BoxContainer sorts its children on a deferred pass, so the positions are
	# not real until the frame ends. The energy/tool stacks do not need this -
	# they set position.x by hand - but the hand does.
	await get_tree().process_frame
	if not is_inside_tree():
		return {}
	var count := hand_container.get_child_count()
	if count == 0:
		return {}
	var slot: Control = hand_container.get_child(count - 1)
	var rect := {"position": slot.global_position, "size": slot.size}
	slot.modulate.a = 0.0
	return rect


func measure_and_hide_new_active_tool_slot(is_opponent: bool) -> Dictionary:
	trainer_effects.display_attached_trainer_cards(is_opponent)
	var container = opponent_attached_cards_container if is_opponent else player_attached_cards_container
	var count = container.get_child_count()
	if count == 0:
		return {}
	var slot = container.get_child(count - 1)
	var rect = {"position": slot.global_position, "size": slot.size}
	slot.visible = false
	return rect

func play_evolution_effect(pokemon: card_object) -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_evolve_sound)
	var loc = get_pokemon_screen_location(pokemon)
	if loc.is_empty():
		print("WARNING: play_evolution_effect - could not locate pokemon: ", pokemon.metadata["name"])
		return
	var target_pos = loc["position"]
	var target_size = loc["size"]
	var is_active = loc["is_active"]

	var particles = CPUParticles2D.new()
	add_child(particles)

	particles.global_position = target_pos + Vector2(target_size.x / 2, target_size.y)
	particles.z_index = 101
	particles.amount = 750
	particles.lifetime = 0.25
	particles.one_shot = true
	particles.explosiveness = 0.3

	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(target_size.x / 2, 0)

	particles.direction = Vector2(0, -1)
	particles.spread = 20
	particles.initial_velocity_min = target_size.y * 3.5
	particles.initial_velocity_max = target_size.y * 5
	particles.gravity = Vector2(0, 0)

	if is_active:
		particles.scale_amount_min = 8.0
		particles.scale_amount_max = 25.0
	else:
		particles.scale_amount_min = 3.0
		particles.scale_amount_max = 6.0

	var type_colour = get_pokemon_type_colour(pokemon)
	var darker = type_colour.darkened(0.4)

	var gradient = Gradient.new()
	gradient.set_color(0, darker)
	gradient.set_color(1, Color(type_colour.r, type_colour.g, type_colour.b, 0.0))
	particles.color_ramp = gradient

	# Set emitting AFTER all particle properties are configured
	particles.emitting = true

	await get_tree().create_timer(GameState.match_time(1)).timeout
	particles.queue_free()
	
# Plays a one-shot upward particle burst when energy is attached to a pokemon
func play_energy_attached_effect(pokemon: card_object, energy_card: card_object) -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_energy_sound)
	var loc = get_pokemon_screen_location(pokemon)
	if loc.is_empty():
		print("WARNING: play_energy_attached_effect - could not locate pokemon: ", pokemon.metadata["name"])
		return
	var target_pos = loc["position"]
	var target_size = loc["size"]
	var is_active = loc["is_active"]

	var particles = CPUParticles2D.new()
	add_child(particles)

	particles.global_position = target_pos + Vector2(target_size.x / 2, target_size.y)
	particles.z_index = 101
	particles.amount = 1000
	particles.lifetime = 0.25
	particles.one_shot = true
	particles.explosiveness = 0

	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(target_size.x / 2, 0)

	particles.direction = Vector2(0, -1)
	particles.spread = 1
	particles.initial_velocity_min = target_size.y * 3
	particles.initial_velocity_max = target_size.y * 4.5
	particles.gravity = Vector2(0, 0)

	if is_active:
		particles.scale_amount_min = 4
		particles.scale_amount_max = 10
	else:
		particles.scale_amount_min = 1
		particles.scale_amount_max = 3
		particles.lifetime = 0.2

	var type_colour = get_type_colour(get_energy_type_from_card(energy_card))
	var darker = type_colour.darkened(0.2)

	var gradient = Gradient.new()
	gradient.set_color(0, darker)
	gradient.set_color(1, Color(type_colour.r, type_colour.g, type_colour.b, 0.0))
	particles.color_ramp = gradient

	particles.emitting = true
	await get_tree().create_timer(GameState.match_time(1)).timeout
	particles.queue_free()

############################################################## END ANIMATION FUNCTIONS ###############################################################
######################################################################################################################################################

#                    ##     #####      ##     #####
#                    ##    ##   ##    ####    ##   ##
#                    ##    ##   ##   ##  ##   ##    ##
#                    ##    ##   ##  ########  ##   ##
#                    #####  #####  ##      ## #####

######################################################################################################################################################
################################################################ GAME LOAD FUNCTIONS #################################################################

# Reusable function to load any deck (both player and opponent) from JSON file path
func load_deck_from_file(deck_file_path: String) -> Array:
	var deck = []
	
	# Open and read the file
	var loaded_deck_from_file = FileAccess.open(deck_file_path, FileAccess.READ)
	
	# Make sure no errors when loading the file
	if loaded_deck_from_file == null:
		print("Error: Could not open deck file at: ", deck_file_path)
		return deck
	
	# Read the entire file as plain text first before parsing as JSON
	var unparsed_json_text = loaded_deck_from_file.get_as_text()
	loaded_deck_from_file.close()
	
	# Parse the JSON
	var new_json_object = JSON.new()
	var deck_json_parse_result = new_json_object.parse(unparsed_json_text)
	
	# Check the deck has loaded correctly
	if deck_json_parse_result != OK:
		print("Error: Failed to parse the raw JSON text into JSON")
		return deck
	
	# Load the deck as parsed data
	var deck_data = new_json_object.data

	# As we have the json data containing the ids and amount, we need to add mutiple of some cards
	if deck_data.size() > 0:
		for this_card in deck_data:
			
			# Get the ID and amount there are in the deck
			var card_to_append_to_deck_id = this_card["id"]
			var card_to_append_to_deck_count = this_card["count"]
			
			# We will now add the amount in COUNT to the deck
			for i in range(card_to_append_to_deck_count):
				
				# Get the metadata for this card to save to the card object
				var card_metadata = get_card_metadata(card_to_append_to_deck_id)
				
				# Create a new card_object with the UID and metadata
				var new_card = card_object.new(card_to_append_to_deck_id, card_metadata)
				
				new_card.current_location = "deck" 
				
				# Add the card object to the deck
				deck.append(new_card)

	# Shuffle the fully completed deck
	deck.shuffle()
	
	# Pass the deck back as a saved variable
	return deck

# Main function to set up the player's deck and hand at match start
func setup_player():
	
	# Load the players CURRENT deck from saved files
	var player_deck_path = "user://Player_Decks/"+player_deck_name+".json"
	
	# Load and shuffle deck
	player_deck = load_deck_from_file(player_deck_path)
	
	# Draw opening hand with mulligan (opening_hand_size match effect may override the count)
	player_hand = draw_opening_hand(player_deck, "Player", match_effects.opening_hand_size(false))
	
	# Display the hand on the main screen at the top centre
	display_hand_cards_array(player_hand, player_hand_container, card_scales[11])

# Main function to set up the opponents's deck and hand at match start. Looks up the NPC name and finds the corresponding deck file
func setup_opponent(opponent_id: String):
	
	# Deck names are typed by hand in All_NPC_Constant_Data.json, so the lookup
	# ignores capitalisation -- a slip used to load nothing at all, and only stayed
	# invisible because NTFS is case-insensitive.
	var opponent_deck_path = AssetLookup.deck_path(opponent_id)
	if opponent_deck_path == "":
		push_error("No deck file matching '%s' in Opponent_Deck_Data/" % opponent_id)
	# TEMP TESTING: T-key TEST match — opponent draws from the player's user:// "TEST" deck.
	if GameState.test_match_mode:
		opponent_deck_path = "user://Player_Decks/TEST.json"
	
	# Load the deck from the opponent data folder file
	opponent_deck = load_deck_from_file(opponent_deck_path)
	
	# Draw opening cards and mulligan (opening_hand_size match effect may override the count)
	opponent_hand = draw_opening_hand(opponent_deck, "Opponent", match_effects.opening_hand_size(true))
	
	# Display the cards in the top right in tiny size just for visual cue
	display_hand_cards_array(opponent_hand, opponent_hand_container, card_scales[11.55], hide_hidden_cards, 1300.0, 12, opponent_sleeve_small)

# Function to draw opening hand with mulligan logic for both player and opponent
# hand_size -1 = use the default (amount_of_cards_to_draw); otherwise the opening_hand_size match effect override
func draw_opening_hand(deck: Array, player_name: String = "", hand_size: int = -1) -> Array:
	# Set the opening variables that will be overwritten by the function
	var hand = []
	var has_basic_pokemon = false
	var cards_to_draw = amount_of_cards_to_draw if hand_size <= 0 else hand_size

	# We need to mulligan if no basic pokemon in hand for each draw. May take multiple attempts
	while not has_basic_pokemon:

		# Clear the hand every time this loops otherwise cards would just be continued to be added
		hand.clear()

		# Now draw X (default is 7) cards and put them in the hand
		for i in range(cards_to_draw):
			
			# Pop front removes the same card from the deck so you don't need to do a .remove and a .add at the same time
			var drawn_card = deck.pop_front() 
			
			# Set the card objects current location to be the hand now that it has been added there
			drawn_card.current_location = "hand" 
			
			# Add to the hand
			hand.append(drawn_card)
		
		# Check if hand contains at least one Basic Pokemon, if not hand needs to go back in deck and reshuffle
		for card_uid in hand:
			
			# Is_Basic_pokemon is a function written to check if an array (the hand) contains a basic pokemon
			if is_basic_pokemon(card_uid):
				
				# If one is found then we don't need to keep looping and retrying so exit out of function
				has_basic_pokemon = true
				break
		
		# If no Basic Pokemon, mulligan
		if not has_basic_pokemon:
			print(player_name, "No Basic Pokemon in hand. Shuffling back...")
			
			# Put hand back into deck
			for card_uid in hand:
				deck.append(card_uid)
			
			# Shuffle again and start redraw for new hand again
			deck.shuffle()
	
	return hand

# Draws prize cards from the specified player's deck based on amount_of_prize_cards
func draw_prize_cards(is_opponent: bool) -> void:
	
	# Get the appropriate deck and prize cards array based on whether it's player or opponent
	var deck: Array
	var prize_cards: Array
	
	if is_opponent:
		deck = opponent_deck
		prize_cards = opponent_prize_cards
	else:
		deck = player_deck
		prize_cards = player_prize_cards
	
	# Check if there are enough cards in the deck
	if deck.size() < amount_of_prize_cards:
		print("Error: Not enough cards in deck to draw ", amount_of_prize_cards, " prize cards. Current deck size: ", deck.size())
		return
	
	# Draw the top 6 cards from the deck and add them to prize cards
	for i in range(amount_of_prize_cards):
		var prize_card = deck.pop_front()
		prize_cards.append(prize_card)
	
	# Display the prize cards
	display_prize_cards(is_opponent)
	
	# Sync deck icon count after prize cards are removed from deck
	update_deck_icon(is_opponent)
	
# Initiates the bench setup phase after the active pokemon is selected at game start
func start_bench_setup_phase() -> void:
		
	# Set the flag so we know we're in bench setup mode
	bench_setup_phase_active = true
	action_button.text = "Select a Card"
	action_button.disabled = true
	action_button.theme = theme_disabled
	
	selected_card_for_action = null
	
	cancel_button.text = "Done"
	cancel_button.theme = theme_green
	
	# Show the hand again for bench pokemon selection
	show_enlarged_array_selection_mode(player_hand)	

############################################################### END GAME LOAD FUNCTIONS ##############################################################
######################################################################################################################################################
#
#                    #######  #######    #######  #######
#                    ##      ##     ##  ##        ##
#                    ##      ##     ##  ##        #######
#                    ##      ##     ##  ##        ##
#                    #######  #######   ##        #######
#
######################################################################################################################################################
############################################################ CORE FUNCTIONALITY FUNCTIONS ############################################################

# Forfeit the match. Reached only after the player confirms in _show_forfeit_dialog().
#
# Fix 6: Escape key = forfeit, not quit application.
#
# A forfeit abandons a best-of-N series OUTRIGHT rather than counting as a single round
# loss. Match_End_Outro_Script only routes into the Best_Of_3 round-counter transition when
# GameState.series_active is still set (Match_End_Outro_Script.gd:122), so clearing the
# series here makes the outro treat this as a plain single-match loss and return the player
# to the map — instead of scoring round 1 and dropping them straight into round 2 of a
# series they just tried to leave.
func end_game() -> void:
	if GameState.series_active:
		GameState.clear_match_series()
	game_end_logic(true)

# ─── Forfeit confirmation ────────────────────────────────────────────────────────────────
# Same shape as the main menu's "Quit the game?" popup (Main_Menu_Script._show_quit_dialog):
# a layer-100 CanvasLayer, a 60% black dim over the whole screen, a centred PanelContainer,
# and a red confirm / green cancel button row. Built in code rather than in the scene so the
# match scene doesn't carry a permanently-hidden dialog node.

func _show_forfeit_dialog() -> void:
	if forfeit_dialog != null and is_instance_valid(forfeit_dialog):
		return

	forfeit_dialog = CanvasLayer.new()
	forfeit_dialog.layer = 100
	add_child(forfeit_dialog)

	# Dim the board behind the popup
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	forfeit_dialog.add_child(overlay)

	# Centred panel — wider than the quit dialog's 460 because the question is a longer line
	var panel := PanelContainer.new()
	panel.theme = theme_disabled
	panel.custom_minimum_size = Vector2(600, 220)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -300
	panel.offset_top    = -110
	panel.offset_right  = 300
	panel.offset_bottom = 110
	forfeit_dialog.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var msg := Label.new()
	msg.text = "Would you like to forfeit this match?"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 24)
	# Wrap rather than widen the panel if the theme's font renders this wider than expected.
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(540, 0)
	vbox.add_child(msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	# ISSUE #287: FIRES ON PRESS, NOT RELEASE.
	#
	# Godot's default is ACTION_MODE_BUTTON_RELEASE - nothing happens until the
	# mouse comes back UP, and nudging the pointer while held cancels the click
	# outright, which reads as a dead button. UIKit.style_button sets press mode on
	# every button it themes, but this dialog predates the overhaul and still
	# carries the old theme_red/theme_green, so it never got it. Both buttons, not
	# just Cancel: they are the same control in the same row and a dialog where one
	# half responds on press and the other on release is worse than either.
	var yes_btn := Button.new()
	yes_btn.text = "Forfeit"
	yes_btn.custom_minimum_size = Vector2(130, 45)
	yes_btn.theme = theme_red
	yes_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	yes_btn.pressed.connect(_on_forfeit_confirmed)
	btn_row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "Cancel"
	no_btn.custom_minimum_size = Vector2(130, 45)
	no_btn.theme = theme_green
	no_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	no_btn.pressed.connect(_close_forfeit_dialog)
	btn_row.add_child(no_btn)
	print("ISSUE #287 FIX ACTIVE: forfeit dialog buttons on ACTION_MODE_BUTTON_PRESS")


func _close_forfeit_dialog() -> void:
	if forfeit_dialog != null and is_instance_valid(forfeit_dialog):
		forfeit_dialog.queue_free()
	# Cleared immediately rather than waiting for queue_free to land at end of frame, so the
	# _input() guard above stops swallowing gameplay input on this very frame.
	forfeit_dialog = null


func _on_forfeit_confirmed() -> void:
	_close_forfeit_dialog()
	end_game()
	
# Main function to get metadata of any card passed to it. Goes off UID to lookup JSON data in game file
func get_card_metadata(card_uid: String):
	
	# Check the UID to make sure it's valid and if not error out 
	var split_uid = card_uid.split("-")
	if split_uid.size() != 2:
		print("Invalid UID provided, UID:", card_uid)
		return
	
	# Card details will be for example "Base1-1" "EX2-2"
	var card_set = split_uid[0]
	
	# Fix 1: Use set metadata cache — only read from disk once per set
	if card_set not in _set_metadata_cache:
		var card_set_json_metadata_path = "res://Card_Set_Data/" + card_set + ".json"
		var metadata_file = FileAccess.open(card_set_json_metadata_path, FileAccess.READ)
		if metadata_file == null:
			print("Error: Could not open metadata file at: ", card_set_json_metadata_path)
			return null
		var raw_json_card_set_text = metadata_file.get_as_text()
		metadata_file.close()
		var parsed_card_set_json = JSON.new()
		if parsed_card_set_json.parse(raw_json_card_set_text) != OK:
			print("Error: Failed to parse metadata JSON")
			return null
		_set_metadata_cache[card_set] = parsed_card_set_json.data
	
	# Now loop through the cached card set data and find the specific card by UID
	var card_set_data = _set_metadata_cache[card_set]
	for this_card in card_set_data:
		if this_card.get("id") == card_uid.to_lower():
			return this_card
	
	# If the card could not be found in this set then return null
	print("Card not found in metadata: ", card_uid)
	return null

# Main function to check if a card is a basic pokemon or not. Will return true or false
# Returns true if the card is a Pokémon-ex (2-prize KO). Subtype casing is inconsistent across
# sets in Card_Set_Data (ex1-16/pop use "ex" lowercase, np uses "EX" uppercase) — check case-insensitively.
func is_ex_pokemon(card: card_object) -> bool:
	if card == null:
		return false
	for st in card.metadata.get("subtypes", []):
		if str(st).to_lower() == "ex":
			return true
	return false

func is_basic_pokemon(card: card_object) -> bool:

	# Get the metadata from the card object directly
	var card_full_metadata = card.metadata
	
	# Make sure metadata exists
	if card_full_metadata == null:
		return false
	
	# Now the card metadata has been found save the super and sub type variables to check
	var main_card_type = card_full_metadata.get("supertype", "").to_lower()
	
	# If the card is a pokemon type then we finally check if it's basic or not
	if main_card_type == "pokémon":
		var card_subtypes_array = card_full_metadata.get("subtypes", [])
		
		# Now We need to make sure it is a BASIC and POKEMON (there exists BASIC ENERGY and allow baby pokemon as basic pokemon)
		for each_subtype in card_subtypes_array:
			
			# avoid case sensitivity
			var each_subtype_lower = each_subtype.to_lower()
			
			# Baby pokemon count as basic
			match each_subtype_lower:
				"basic", "baby":
					return true
				"stage 1", "stage 2", "stage1", "stage2":
					return false
	
	# If the above statements don't deem this a POKEMON card at all or it is a pokemon but NOT a BASIC card then return false
	return false

# Get card action is used when selecting a card from an array. Allows basic pokemon to be set, trainers to be played, energies to be attached
func get_card_action(card: card_object) -> Dictionary:
	
	# This function returns a dictionary with the action name and whether it's available
	if card == null:
		return {"action": "NONE", "button_text": ""}
	
	if prize_card_selection_active:
		return {"action": "TAKE_PRIZE", "button_text": "TAKE PRIZE"}
	
	# We need to get the cards type whether it's trainer pokemon or energy
	var card_metadata = card.metadata
	var supertype = card_metadata.get("supertype", "").to_lower()
	
	# As a very specific piece of logic, only basic pokemon can be SET AS ACTIVE POKEMON pokemon on turn 1 and never again.
	if match_just_started_basic_pokemon_required == true:
		
		# Only a pokemon card can be played and ONLY if that pokemon card is basic
		match supertype:
			"pokémon":
				if is_basic_pokemon(card):
					# If the selected card is a basic pokemon then it can be SET AS ACTIVE POKEMON pokemon on turn one
					return {"action": "SET_POKEMON", "button_text": "SET AS ACTIVE POKEMON"}
				else:
					# Stage 1 or Stage 2 cannot be played on turn 1
					return {"action": "NONE", "button_text": "Select Basic Pokemon"}
					
			# trainers and energy cannot be played until a basic pokemon is set
			"trainer","energy":
					return {"action": "NONE", "button_text": "Select Basic Pokemon"}
	
	elif bench_setup_phase_active:
		# Only a pokemon card can be played and ONLY if that pokemon card is basic
		match supertype:
			"pokémon":
				if is_basic_pokemon(card):
					# If the selected card is a basic pokemon then it can be SET AS ACTIVE POKEMON pokemon on turn one
					return {"action": "SET_POKEMON", "button_text": "PLACE ON BENCH"}
				else:
					# Stage 1 or Stage 2 cannot be played on turn 1
					return {"action": "NONE", "button_text": "Select Basic Pokemon"}
					
			# trainers and energy cannot be played until a basic pokemon is set
			"trainer","energy":
					return {"action": "NONE", "button_text": "Select Basic Pokemon"}
					
	# If turn one is done and a basic pokemon has been played then any card can be played with different actions
	else:
		match supertype:
			"pokémon":
				if is_basic_pokemon(card):
					return {"action": "SET_POKEMON", "button_text": "Place on Bench"}
				else:
					# Stage 1 or Stage 2 cannot be played directly
					return {"action": "EVOLVE", "button_text": "Evolve"}
			
			"trainer":
				return {"action": "PLAY_TRAINER", "button_text": "Play"}
			
			"energy":
				return {"action": "ATTACH_ENERGY", "button_text": "Attach"}	
				
	
	# Default fallback
	return {"action": "NONE", "button_text": ""}

# Function for setting the active pokemon from hand of bench
func set_player_active_pokemon() -> void:
	# First, check if a card was actually selected
	if selected_card_for_action == null:
		print("Error: No card selected for action")
		return
	
	# Check if the selected card is a basic pokemon
	if not is_basic_pokemon(selected_card_for_action):
		print("Error: Selected card is not a basic pokemon")
		return
		
	print("Attempting to set an active pokemon:")
	
	# Store the original location before we change it
	var original_location = selected_card_for_action.current_location
	
	# If we get here, it's valid - set it as the active pokemon
	player_active_pokemon = selected_card_for_action
	
	# Update the card's location to "active"
	player_active_pokemon.current_location = "active"
	player_active_pokemon.placed_on_field_this_turn = true
	
	
	# Now remove from the appropriate location based on where it came from
	match original_location:
		"hand":
			player_hand.erase(selected_card_for_action)
			print("Removed pokemon from hand")
		"bench":
			# Move from bench to active if needed
			# For now: player_bench.erase(selected_card_for_action)
			print("Removed pokemon from bench")
	
	# Print confirmation
	print("Player's active pokemon set to: ", player_active_pokemon.metadata["name"])
	
	# Clear the selection
	selected_card_for_action = null

# Function to add a card from the player's hand to the bench
func add_pokemon_to_bench(pokemon: card_object) -> void:

	# Set max bench size (defaults to 5; reduced to 4 by gym1-124 Narrow Gym)
	if player_bench.size() >= get_max_bench_size():
		print("Error: Bench is full (maximum " + str(get_max_bench_size()) + " pokemon)")
		return
		
	# Validate that the card is a basic pokemon
	if not is_basic_pokemon(pokemon):
		print("Error: Cannot add non-basic pokemon to bench")
		return
	
	# Store the original location
	var original_location = pokemon.current_location
	
	# Update the card's location to "bench"
	pokemon.current_location = "bench"
	pokemon.placed_on_field_this_turn = true
	
	# Remove from the appropriate location based on where it came from
	match original_location:
		"hand":
			player_hand.erase(pokemon)
			print("Removed pokemon from hand and added to bench: ", pokemon.metadata["name"])
		"active":
			# Moved from active to bench
			print("Moved pokemon from active to bench")
	
	# Add the pokemon to the bench array
	player_bench.append(pokemon)
	print("Pokemon added to bench. Bench size: ", player_bench.size())
	powers_and_bodies.refresh_holon_veil()   # EX15 Holon Veil

	# GYM2 Giovanni's Persian Call the Boss — search deck for a Giovanni trainer when Persian comes into play from hand
	if original_location == "hand":
		await powers_and_bodies.trigger_call_the_boss(pokemon, false)
	# NEO2 [Engage]/[Increase] (Unown [E]/[I]): on-play triggers
	if original_location == "hand":
		if "[Engage]" in str(pokemon.metadata.get("abilities",[])):
			await powers_and_bodies.trigger_neo2_unown_engage(pokemon, false)
		elif "[Increase]" in str(pokemon.metadata.get("abilities",[])):
			await powers_and_bodies.trigger_neo2_unown_increase(pokemon, false)
	# NEO4 on-bench-from-hand triggers
	if original_location == "hand":
		# Hot Plate (Dark Magcargo): any active Magcargo deals 10 to a newly-benched Basic/Baby
		var subs_n4 = pokemon.metadata.get("subtypes", [])
		if "Basic" in subs_n4 or "Baby" in subs_n4:
			powers_and_bodies.check_neo4_hot_plate(pokemon, false)
		# [Vanish] (Unown [V]): on play, may return another Unown to hand
		if pokemon.has_ability("[Vanish]"):
			await powers_and_bodies.trigger_neo4_vanish(pokemon, false)
		# EX4-83 Team Magma Hideout: playing a non-Team-Magma Basic from hand adds 1 damage counter
		await trainer_effects.ex4_team_magma_hideout_trigger(pokemon, false)
		# EX6 Legendary Ascent (Articuno/Moltres/Zapdos ex): switch with your Active + rally its Energy
		await powers_and_bodies.trigger_ex6_legendary_ascent(pokemon, false)
		# EX8 Dragon Boost (Rayquaza ex ex8-102): move any number of basic Energy to Rayquaza ex
		await powers_and_bodies.trigger_ex8_dragon_boost(pokemon, false)
		# EX11 Delta Switch (Mewtwo δ): on benching from hand, move any number of basic Energy among
		# your other Pokémon (excluding Mewtwo).
		await powers_and_bodies.trigger_ex11_delta_switch(pokemon, false)
		# EX12 Support Navigation (Lapras ex12-8): on benching from hand, search deck for a Supporter → hand.
		if pokemon.has_ability("Support Navigation"):
			await powers_and_bodies.trigger_ex12_support_navigation(pokemon, false)
		# EX14 Crush Chance (Tauros ex14-12): on benching from hand, may discard a Stadium card in play.
		if pokemon.has_ability("Crush Chance"):
			await powers_and_bodies.trigger_ex14_crush_chance(pokemon, false)
		# EX15 Tropical Heal (Tropius δ ex15-23): on benching from hand, remove all Special Conditions,
		# Imprison markers, and Shock-wave markers from your Pokémon.
		if pokemon.has_ability("Tropical Heal"):
			await powers_and_bodies.trigger_ex15_tropical_heal(pokemon, false)
		# EX16 on-bench-from-hand powers: Cursed Eyes (Absol ex), Crimson/Yellow/Blue Ray (Star Eeveelutions).
		await powers_and_bodies.trigger_ex16_on_bench(pokemon, false)
		# POP on-bench-from-hand powers: Time Reversal (Celebi ex), Purple Ray (Espeon Star), Dark Ray (Umbreon Star).
		await powers_and_bodies.trigger_pop_on_bench(pokemon, false)

# Function that get's the card position/location/object. Called from various functions when trying to find a specific card object
func find_card_ui_for_object(card_obj: card_object) -> TextureRect:
	# Helper: searches one level of direct children for a TextureRect matching card_obj,
	# then also searches one level deeper through VBoxContainer → Control wrappers
	# created by build_pokemon_slot_with_energies_and_hp.
	var containers_to_search: Array = []
	
	if small_selection_container.visible:
		containers_to_search.append(small_selection_container)
	if selection_scroller.visible:
		containers_to_search.append(large_selection_container)
	
	containers_to_search.append_array([
		player_active_container, opponent_active_container,
		player_bench_container, opponent_bench_container,
		player_energy_container, opponent_energy_container,
		player_hand_container, opponent_hand_container
	])
	
	for container in containers_to_search:
		for child in container.get_children():
			# Direct TextureRect (hand cards, active pokemon, etc.)
			if child is TextureRect and "card_ref" in child:
				if child.card_ref == card_obj:
					return child
			# Slot wrapper: VBoxContainer → card_area (Control) → TextureRect nodes
			# This is the structure created by build_pokemon_slot_with_energies_and_hp.
			if child is VBoxContainer:
				for slot_child in child.get_children():
					# ISSUE #46 FIX: the retreat energy-raise wrapper puts the card TextureRect as a DIRECT
					# child of the VBox (alongside the spacer Control). Check that case too, or the retreat
					# energy cards can't be found and their click selection animation never plays.
					if slot_child is TextureRect and "card_ref" in slot_child:
						if slot_child.card_ref == card_obj:
							return slot_child
					if slot_child is Control and not (slot_child is Label):
						for card_ui in slot_child.get_children():
							if card_ui is TextureRect and "card_ref" in card_ui:
								if card_ui.card_ref == card_obj:
									return card_ui
	
	return null

# Deselects the currently selected card and selects a new card, updating the UI visuals
func select_card_in_ui(new_card: card_object) -> void:
	# Deselect the previous card and all energy UIs in its slot.
	if selected_card_for_action != null:
		var prev_display = find_card_ui_for_object(selected_card_for_action)
		if prev_display:
			prev_display.set_selected(false)
			# Also deselect attached energy card UIs in the same slot wrapper.
			for energy_ui in _find_energy_uis_in_same_slot(prev_display):
				energy_ui.set_selected(false)
	
	selected_card_for_action = new_card
	
	var card_display = find_card_ui_for_object(new_card)
	if card_display:
		card_display.set_selected(true)
		# Also select attached energy card UIs so they animate together.
		for energy_ui in _find_energy_uis_in_same_slot(card_display):
			energy_ui.set_selected(true)

# Returns all energy TextureRect nodes that are siblings of card_ui inside the same
# VBoxContainer → Control slot created by build_pokemon_slot_with_energies_and_hp.
# Energy nodes use MOUSE_FILTER_IGNORE (pokemon card uses MOUSE_FILTER_PASS/STOP).
func _find_energy_uis_in_same_slot(card_ui: TextureRect) -> Array:
	var result: Array = []
	# card_ui.get_parent() is the card_area Control inside a VBoxContainer slot.
	var card_area = card_ui.get_parent()
	if not (card_area is Control) or card_area is VBoxContainer:
		return result
	for sibling in card_area.get_children():
		if sibling is TextureRect and sibling != card_ui and sibling.mouse_filter == MOUSE_FILTER_IGNORE:
			result.append(sibling)
	return result

# Function called when selecting an energy card to attach to a pokemon. Calls show enlarged array as a subfunction	
func start_energy_attachment() -> void:
	# Validate that an energy card is selected
	if selected_card_for_action == null:
		print("Error: No energy card selected for attachment")
		return
	
	# Store the energy card for later attachment
	energy_card_awaiting_target = selected_card_for_action
	
	# Create temporary array of valid attachment targets
	var attachment_targets = []
	
	attachment_targets.append_array(player_bench)
	if player_active_pokemon != null:
		attachment_targets.append(player_active_pokemon)
	
	
	# Enter attach mode and show only valid targets
	card_attach_mode_active = true
	show_enlarged_array_selection_mode(attachment_targets)
	
	# Update labels for energy attachment context
	var energy_name = energy_card_awaiting_target.metadata.get("name", "Unknown Energy")
	header_label.text = "ATTACHING " + energy_name.to_upper()
	hint_label.text = "Select a Pokémon to attach " + energy_name + " to"
	
	# Update action button text
	action_button.text = "ATTACH ENERGY"
	
# Add this new function after start_energy_attachment()
func perform_energy_attachment() -> void:
	if energy_card_awaiting_target == null or selected_card_for_action == null:
		print("Error: No energy card or target Pokemon selected")
		return
	
	var energy_card = energy_card_awaiting_target
	var target_pokemon = selected_card_for_action
	
	# Check special energy attachment restrictions
	var subtypes = energy_card.metadata.get("subtypes", [])
	if "Special" in subtypes:
		var attach_check = special_energy_effects.can_attach_to(energy_card, target_pokemon)
		if not attach_check["allowed"]:
			await show_message(attach_check["reason"])
			energy_card_awaiting_target = null
			selected_card_for_action = null
			card_attach_mode_active = false
			hide_selection_mode_display_main()
			return
	# Pure Body (Suicune): block Water Energy if Suicune has no energies to discard
	if powers_and_bodies.check_pure_body_block(energy_card, target_pokemon):
		await show_message("PURE BODY! " + target_pokemon.metadata.get("name","").to_upper() + " HAS NO ENERGY TO DISCARD!")
		energy_card_awaiting_target = null
		selected_card_for_action = null
		card_attach_mode_active = false
		hide_selection_mode_display_main()
		return
	# ECARD2 Anti-Lightning (Zapdos): can't attach Lightning Energy from hand to Zapdos
	if powers_and_bodies.check_anti_lightning_block(energy_card, target_pokemon):
		await show_message("ANTI-LIGHTNING! CAN'T ATTACH LIGHTNING ENERGY TO " + target_pokemon.metadata.get("name","").to_upper() + "!")
		energy_card_awaiting_target = null
		selected_card_for_action = null
		card_attach_mode_active = false
		hide_selection_mode_display_main()
		return
	# ECARD3 Water Immunity (Articuno) / Fire Immunity (Moltres): can't attach that type of Energy
	if powers_and_bodies.check_ecard3_type_immunity_block(energy_card, target_pokemon):
		await show_message("CAN'T ATTACH THAT ENERGY TYPE TO " + target_pokemon.metadata.get("name","").to_upper() + "!")
		energy_card_awaiting_target = null
		selected_card_for_action = null
		card_attach_mode_active = false
		hide_selection_mode_display_main()
		return

	# EX14 Cursed Glare (Dusclops ex14-17): opponent can't attach Special Energy (except Darkness/Metal)
	# from hand to their Active Pokemon.
	if powers_and_bodies.check_ex14_cursed_glare_blocks_energy(energy_card, target_pokemon):
		await show_message("CURSED GLARE! CAN'T ATTACH THAT SPECIAL ENERGY TO YOUR ACTIVE POKEMON!")
		energy_card_awaiting_target = null
		selected_card_for_action = null
		card_attach_mode_active = false
		hide_selection_mode_display_main()
		return

	# EX11 Binding Aura (Hypno): the opponent can't attach Energy from hand to an Asleep Pokemon.
	if powers_and_bodies.check_ex11_binding_aura_blocks_energy(target_pokemon):
		await show_message("BINDING AURA! CAN'T ATTACH ENERGY TO AN ASLEEP POKEMON!")
		energy_card_awaiting_target = null
		selected_card_for_action = null
		card_attach_mode_active = false
		hide_selection_mode_display_main()
		return
	# EX5 Freeze Lock (Regice ex ex5-97): can't attach Energy from hand to a Freeze-Locked Pokemon
	if target_pokemon.has_effect("ex5_energy_lock"):
		await show_message("FREEZE LOCK! CAN'T ATTACH ENERGY TO " + target_pokemon.metadata.get("name","").to_upper() + " THIS TURN!")
		energy_card_awaiting_target = null
		selected_card_for_action = null
		card_attach_mode_active = false
		hide_selection_mode_display_main()
		return

	# ISSUE #283: measure the energy card WHERE IT SITS IN THE HAND, before the
	# erase + refresh below frees its node. Without this the flight starts at the
	# hand container's origin - the left end of the row - whichever card was played.
	var energy_from := _card_rect_now(energy_card)
	target_pokemon.attached_energies.append(energy_card)
	print("Attached ", energy_card.metadata.get("name", "Unknown Energy"), " to ", target_pokemon.metadata.get("name", "Unknown Pokemon"))
	player_hand.erase(energy_card)
	# EX5 Island Cave (ex5-89 Stadium): attaching Energy from hand to a Water/Fighting/Metal Pokemon
	# removes any Special Conditions from it.
	trainer_effects.ex5_island_cave_on_attach(target_pokemon, false)
	# MATCH EFFECT: extra_energy_per_turn — flag only set once the per-turn limit is reached
	player_energy_attach_count += 1
	player_energy_played_this_turn = player_energy_attach_count >= match_effects.energy_attach_limit(false)
	
	# Clear the attachment variables and exit attach mode
	energy_card_awaiting_target = null
	selected_card_for_action = null
	card_attach_mode_active = false
	
	hide_selection_mode_display_main()
	refresh_hand_display(false)
	
	# Animate energy flying from hand to the target pokemon
	var target_node = player_energy_container if target_pokemon == player_active_pokemon else player_bench_container
	var energy_texture = get_card_texture(energy_card)
	if target_pokemon == player_active_pokemon:
		# ISSUE #40 FIX: fly the Energy to its EXACT final slot in the Active energy stack (position AND
		# size), read straight off the freshly-built stack — no guessing. Previously it flew to the
		# Active card's position/size and then snapped into the stack (looked ~300px off / mid-array).
		var slot_rect = measure_and_hide_new_active_energy_slot(false)
		var slot_pos = slot_rect.get("position", _ANIM_POS_SENTINEL)
		var slot_size = slot_rect.get("size", card_scales[11])
		# ISSUE #283: leaves from the card's own place in the hand, at the size it
		# was drawn there, and sinks BEHIND the Pokemon as it lands (#236).
		print("ISSUE #283 FIX ACTIVE: energy leaves hand from ",
			energy_from.get("position", "container fallback"))
		await animate_card_a_to_b(player_hand_container, target_node, 0.2, energy_texture,
			energy_from.get("size", card_scales[12]), slot_size, slot_pos, true,
			energy_from.get("position", _ANIM_POS_SENTINEL))
	else:
		# ISSUE #20 FIX: fly the Energy to the ACTUAL benched Pokémon's slot position.
		var bench_energy_loc = get_pokemon_screen_location(target_pokemon)
		var energy_pos_override = bench_energy_loc.get("position", _ANIM_POS_SENTINEL)
		await animate_card_a_to_b(player_hand_container, target_node, 0.2, energy_texture,
			energy_from.get("size", card_scales[12]),
			bench_energy_loc.get("size", BENCH_CARD), energy_pos_override, true,
			energy_from.get("position", _ANIM_POS_SENTINEL))

	display_pokemon(false)
	display_active_pokemon_energies(false)

	await get_tree().process_frame
	await play_energy_attached_effect(target_pokemon, energy_card)
	
	# Apply special energy on-attach effects (Rainbow self-damage, Full Heal cure, Potion heal, etc.)
	if "Special" in subtypes:
		await special_energy_effects.apply_on_attach_effects(energy_card, target_pokemon, false)
		# EX11 Delta Moon (Umbreon δ): opponent attaching a Special Energy takes 1 counter on that Pokemon.
		await powers_and_bodies.check_ex11_delta_moon(target_pokemon, false)

	# GYM2 Blaine's Ninetales Healing Fire — heal 10 when Fire energy is attached from hand
	await powers_and_bodies.check_healing_fire(target_pokemon, energy_card, false)
	# GYM2 Sabrina's Gastly Gaseous Form — +10 HP per Psychic energy attached
	powers_and_bodies.refresh_gaseous_form_hp()
	# NEO2 Energy Evolution (Eevee neo2-38): on energy attach, flip for matching evo
	await powers_and_bodies.check_energy_evolution(target_pokemon, energy_card, false)
	# NEO3 Triggered Poison (Crobat neo3-4): if energy is attached to a pokemon with triggered_poison_active, poison it
	await powers_and_bodies.check_triggered_poison(target_pokemon, false)
	# NEO3 Lightning Burst (Flaaffy neo3-28): when Lightning Energy is attached, deal 10 to each opp benched pokemon
	powers_and_bodies.check_lightning_burst(target_pokemon, energy_card, false)
	# NEO4 Conductivity (Dark Ampharos neo4-1): opponent's Ampharos deals 10 to this Pokemon
	powers_and_bodies.check_neo4_conductivity(target_pokemon, false)
	if _should_bail(): return
	# NP Pure Body (Suicune): discard an energy after Water Energy is attached
	await powers_and_bodies.check_pure_body_discard(energy_card, target_pokemon, false)
	if _should_bail(): return
	# ECARD2 Pokemon Park: energy attached from hand to a Benched Pokemon heals 1 damage counter
	if target_pokemon != player_active_pokemon:
		trainer_effects.pokemon_park_on_bench_energy_attach(target_pokemon, false)
	# ECARD2/ECARD3 Crystal Type: matching-type Energy attach temporarily changes the holder's type
	powers_and_bodies.check_crystal_type_attach(target_pokemon, energy_card, false)
	# ECARD3 Self-healing (Flareon): Fire Energy attach from hand cures all Special Conditions
	powers_and_bodies.check_ecard3_self_healing(target_pokemon, energy_card, false)
	# EX1 Natural Cure (Combusken/Grovyle/Marshtomp): matching-type Energy attach cures all Special Conditions
	powers_and_bodies.check_ex1_natural_cure(target_pokemon, energy_card, false)
	# EX1 Natural Remedy (Swampert ex1-23): Water Energy attach from hand heals 1 damage counter
	powers_and_bodies.check_ex1_natural_remedy(target_pokemon, energy_card, false)
	# EX12 Reactive Healing (Tangela ex12-44): attaching a React Energy from hand removes all counters.
	powers_and_bodies.check_ex12_reactive_healing(target_pokemon, energy_card, false)
	# EX12 Fire Remedy (Arcanine ex ex12-83): attaching a Fire Energy from hand removes 1 counter + status.
	powers_and_bodies.check_ex12_fire_remedy(target_pokemon, energy_card, false)
	# EX7 Saturation (Quagsire ex7-26 / Wooper ex7-81): Water Energy attach clears conditions + heals
	powers_and_bodies.check_ex7_saturation(target_pokemon, energy_card, false)
	# EX8 Natural Cure (Lombre ex8-34) auto-works via check_ex1_natural_cure above (generic ability).
	# EX8 Lightning Burst (Rocket's Raikou ex ex8-108): Darkness Energy attach may switch a Defender
	await powers_and_bodies.check_ex8_lightning_burst(target_pokemon, energy_card, false)

	# MATCH EFFECTS: energy_attach_halve_hp / energy_attach_full_heal
	await apply_energy_attach_match_effects(target_pokemon, false)

# MATCH EFFECTS: energy_attach_halve_hp / energy_attach_full_heal — runs after an energy
# card is attached from hand (both sides). Halve first, then heal; the heal goes through
# heal_pokemon so no_healing wins and healing_multiplier is irrelevant (full heal caps).
func apply_energy_attach_match_effects(target_pokemon: card_object, is_opponent: bool) -> void:
	if target_pokemon == null or game_is_over:
		return
	if match_effects.energy_attach_halve_hp(is_opponent):
		var new_hp = match_effects.halve_hp_round_up_10(target_pokemon.current_hp)
		if new_hp < target_pokemon.current_hp:
			var lost_hp = target_pokemon.current_hp - new_hp
			target_pokemon.current_hp = new_hp
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_poison_sound)
			show_floating_label("-" + str(lost_hp) + "HP", Vector2(1030 if is_opponent else 530, 300), Color.RED, true)
			display_hp_circles_above_align(target_pokemon, is_opponent)
			await show_message("SPECIAL MATCH RULE: " + target_pokemon.metadata.get("name", "").to_upper() + "'S HP WAS HALVED!")
			if _should_bail(): return
	if match_effects.energy_attach_full_heal(is_opponent):
		var missing_hp = target_pokemon.get_max_hp() - target_pokemon.current_hp
		if missing_hp > 0:
			await show_message("SPECIAL MATCH RULE: ATTACHING ENERGY FULLY HEALS " + target_pokemon.metadata.get("name", "").to_upper() + "!")
			if _should_bail(): return
			await card_ops.heal_pokemon(target_pokemon, missing_hp, is_opponent)

# Called when any win/loss condition is met to end the match
func game_end_logic(loser_is_player: bool, is_draw: bool = false) -> void:
	# Set the flag immediately so no other async functions continue processing
	game_is_over = true

	# ISSUE #61: "My game, my rules" — any draw (both players out simultaneously) is a LOSS for the
	# player, matching the Pokémon TCG GB game logic. Never awards a win on a tie.
	if is_draw:
		print("ISSUE #61 FIX ACTIVE: GAME OVER — DRAW, treated as a loss for the player")
		await show_message("IT'S A DRAW — WHICH COUNTS AS A LOSS!")
		GameState.battle_result = "loss"
	elif loser_is_player:
		print("GAME OVER: Player has lost the game!")
		await show_message("GAME OVER: YOU LOST!!!!!")
		GameState.battle_result = "loss"
	else:
		print("GAME OVER: Opponent has lost the game!")
		await show_message("CONGRATULATIONS: YOU WON!!!!!")
		GameState.battle_result = "win"

	# Trainer-card statistics: every finished match counts, win or loss, including each round of
	# a best-of-3 and a forfeit. Test matches are ignored inside record_match_result().
	GameState.record_match_result(GameState.battle_result == "win")
	
	GameState.returning_from_battle = true
	
	# Stop the match BGM before transitioning
	SoundManagerScript.stop_bgm()
	
	# Instead of awaiting a tween on this node (which gets freed by
	# change_scene_to_file), we create a ColorRect overlay on the ROOT
	# CanvasLayer and tween that. The transition is handled via a
	# one-shot timer on the autoload so this script never needs to
	# resume after the scene change.
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.size = Vector2(1920, 1080)
	overlay.z_index = 1000
	# Add to the tree root so it persists through scene change
	get_tree().root.add_child(overlay)
	
	var tween = get_tree().create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 0.5)
	tween.tween_callback(func():
		overlay.queue_free()
		SceneCache.change_scene("res://Scenes/Main_Match_Gameplay_Scenes/Match_End_Outro_Scene.tscn")
	)

# Draws one card from the top of the deck and adds it to the hand
func draw_card_from_deck(is_opponent: bool, speed_multiplier: float = 1.0) -> card_object:
	var deck = opponent_deck if is_opponent else player_deck
	var hand = opponent_hand if is_opponent else player_hand
	if deck.size() == 0:
		game_end_logic(not is_opponent)
		return null

	var drawn_card = deck.pop_front()
	drawn_card.current_location = "hand"
	hand.append(drawn_card)

	# ISSUE #282: fly to the slot the card will REALLY occupy - the end of the row -
	# instead of to the middle of the hand box. measure_and_hide_new_hand_slot
	# builds the new hand, reads the last slot's rect and makes it transparent so
	# the card is not visible in two places during the flight.
	var hand_container = opponent_hand_container if is_opponent else player_hand_container
	var deck_icon = opponent_deck_icon if is_opponent else player_deck_icon
	var back_tex = opponent_card_back_texture if is_opponent else card_back_texture
	var speed: float = (0.2 if is_opponent else 0.3) * speed_multiplier
	var slot := await measure_and_hide_new_hand_slot(is_opponent)
	if not slot.is_empty():
		print("ISSUE #282 FIX ACTIVE: draw lands at ", slot["position"], " size ", slot["size"])
	await animate_card_a_to_b(deck_icon, hand_container, speed, back_tex,
		Vector2(83, 113), slot.get("size", Vector2.ZERO),
		slot.get("position", _ANIM_POS_SENTINEL))
	# Puts the transparent slot back to full opacity.
	refresh_hand_display(is_opponent)

	return drawn_card

# ISSUE #10 FIX ACTIVE: when several cards are drawn back-to-back (e.g. shuffling a hand back
# into the deck and redrawing), each individual draw animation should get quicker so the whole
# batch doesn't take forever — while a single draw still plays at full, normal speed.
func draw_animation_speed_multiplier(total_cards: int) -> float:
	match total_cards:
		0, 1: return 1.0
		2: return 0.8
		3: return 0.6
		4: return 0.5
		5: return 0.44
		6: return 0.4
		_: return 0.3

# Flips a coin with animation, blocks input, shows result message, returns true for heads.
# flipper_is_opponent: when true, uses the opponent's coin texture for the heads face
# (falls back to the player's coin if the opponent has no coin_reward / texture failed to load).
func flip_coin(silent: bool = false, flipper_is_opponent: bool = false) -> bool:
	# MATCH EFFECT: coin_flip_override — every flip forced to heads/tails (animation still plays)
	var rule_override: String = match_effects.coin_override(flipper_is_opponent)
	var result: bool = (rule_override == "heads") if rule_override != "" else (randi() % 2 == 0)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_coin_flip_sound)

	# Resolve which heads face to use for this flip
	var heads_tex = tex_opp_heads if (flipper_is_opponent and tex_opp_heads != null) else tex_heads

	# Show the input-blocking overlay and set initial coin image to heads
	coin_container.visible = true
	var coin = coin_texture
	coin.texture = heads_tex
	coin.visible = true

	# Force coin to a fixed display size regardless of source image dimensions
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.custom_minimum_size = Vector2(129, 129)
	coin.size = Vector2(129, 129)

	# Set pivot to center so the squish effect scales from the middle, not the top edge
	coin.pivot_offset = coin.size / 2
	var start_y = coin.position.y
	var flip_count = 12
	# ISSUE #34: the whole flip (arc + squish cycle) derives from half_flip_time, so scaling this one
	# value scales the coin animation with the Options speed preset.
	var half_flip_time = GameState.match_time(0.04)
	var total_time = flip_count * half_flip_time * 1.5

	# Position tween: arc up then back down
	var pos_tween = create_tween()
	pos_tween.tween_property(coin, "position:y", start_y - 400, total_time / 1.5).set_ease(Tween.EASE_OUT)
	pos_tween.tween_property(coin, "position:y", start_y, total_time / 1.5).set_ease(Tween.EASE_IN)

	# Flip tween: squish scale.y to 0, swap texture, unsquish back to 1
	var flip_tween = create_tween()
	var textures = [tex_tails, heads_tex]
	for i in flip_count:
		flip_tween.tween_property(coin, "scale:y", 0.0, half_flip_time)
		flip_tween.tween_callback(coin.set.bind("texture", textures[i % 2]))
		flip_tween.tween_property(coin, "scale:y", 1.0, half_flip_time)

	await flip_tween.finished

	# Set the final coin face to match the actual result
	coin.texture = heads_tex if result else tex_tails
	var sparkles = null
	if result:
		sparkles = start_sparkle_effect(coin)
	coin.scale.y = 1.0

	# GYM1 Sabrina's ESP: if the flipper's active pokemon has the credit and result is tails, auto re-flip once.
	# (Faithful simplification of "you may re-flip those coins once" — we always take the re-flip on tails since
	#  it can only be better than the original tails. Credit is consumed.)
	if not result and rule_override == "":
		var esp_owner = opponent_active_pokemon if flipper_is_opponent else player_active_pokemon
		if esp_owner != null and esp_owner.gym1_sabrina_esp_credit_active:
			esp_owner.gym1_sabrina_esp_credit_active = false
			if not silent:
				await show_message("SABRINA'S ESP — RE-FLIPPING!")
			result = (randi() % 2 == 0)
			coin.texture = heads_tex if result else tex_tails
			if result:
				if sparkles:
					sparkles.queue_free()
				sparkles = start_sparkle_effect(coin)

	if silent:
		# In silent mode, just wait briefly and clean up without showing a message
		await get_tree().create_timer(GameState.match_time(0.2)).timeout
	else:
		# Show result message using existing message system
		var result_text = "HEADS" if result else "TAILS"
		await show_message("Coin landed on " + result_text + "!")
	
	# Clean up sparkles before hiding coin
	if sparkles:
		sparkles.queue_free()
	
	# Clean up: hide the coin overlay
	coin_container.visible = false
	coin.visible = false
	
	return result
	
# Sends a card and all its attachments (energies, pre-evolutions, attached cards) to the discard pile
func send_card_to_discard(card: card_object, is_opponent: bool) -> void:
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	
	# Revert Ditto Transform before discarding so original card data is preserved
	powers_and_bodies.revert_ditto_if_needed(card)
	
	for energy in card.attached_energies:
		card_ops.discard_energy_from_pokemon(energy, is_opponent, true)  # is_ko_discard=true: skip Ecogym
	card.attached_energies.clear()
	
	for pre_evo in card.attached_pre_evolutions:
		pre_evo.current_location = "discard"
		discard.append(pre_evo)
	card.attached_pre_evolutions.clear()
	
	for attached in card.attached_cards:
		attached.current_location = "discard"
		discard.append(attached)
	card.attached_cards.clear()
	
	card.current_location = "discard"
	discard.append(card)
	
	# Clear temporary type overrides and disabled attacks when leaving play
	card.temporary_weakness = ""
	card.temporary_resistance = ""
	card.shielded_damage_threshold = 0
	card.has_destiny_bond = false
	card.pluspower_count = 0
	card.defender_turns_remaining = -1
	card.defender_count = 0
	card.clear_all_expiring_effects()
	card.no_prize_on_ko = false
	card.is_bench_token = false
	card.power_used_this_turn = false
	card.is_electrode_energy = false
	card.electrode_energy_type = ""
	card.attached_as_energy = false
	card.pokemon_energy_types = []
	# EX15: markers and Holon Veil grant are cleared when a Pokémon leaves play.
	card.imprison_markers = 0
	card.shockwave_markers = 0
	card.granted_delta = false
	# Clear while_in_play and end_of_turn disabled attacks (keep entire_game)
	var keys_to_remove = []
	for atk_name in card.disabled_attacks:
		if card.disabled_attacks[atk_name] != "entire_game":
			keys_to_remove.append(atk_name)
	for key in keys_to_remove:
		card.disabled_attacks.erase(key)
	
	update_discard_pile_display(is_opponent)

# Removes a prize card from the specified player's prizes and adds it to their hand with animation
func take_prize_card(card: card_object, is_opponent: bool) -> void:
	var prizes = opponent_prize_cards if is_opponent else player_prize_cards
	var hand = opponent_hand if is_opponent else player_hand
	var prize_container = opponent_prize_container if is_opponent else player_prize_container
	var hand_container = opponent_hand_container if is_opponent else player_hand_container
	
	var card_ui = find_card_ui_for_object(card)
	# For opponent, always show card back during animation to hide the card
	var card_texture = opponent_card_back_texture if is_opponent else get_card_texture(card)
	
	prizes.erase(card)
	card.current_location = "hand"
	hand.append(card)
	
	display_prize_cards(is_opponent)
	
	await animate_card_a_to_b(prize_container, hand_container, 0.3, card_texture, card_scales[11])
	
	refresh_hand_display(is_opponent)

# Opens selection mode to choose a prize card and return that as the object to put into hand
func player_pick_prize_card() -> void:
	prize_card_selection_active = true
	show_enlarged_array_selection_mode(player_prize_cards)
	header_label.text = "TAKE A PRIZE CARD"
	hint_label.text = "Select a prize card to add to your hand"
	# Hide cancel and re-centre the action button.
	# show_enlarged_array_selection_mode already ran its button layout, so we must
	# explicitly restore the action button to the default centred position here.
	cancel_button.visible = false
	action_button.offset_left = action_button_default_offset_left
	action_button.offset_right = action_button_default_offset_right
	action_button.text = "TAKE PRIZE"
	action_button.disabled = true
	action_button.theme = theme_disabled


############################################### Start and end of turn checks and sets ################################################

# Resets per-turn placement flags for all field pokemon on one side.
func reset_field_pokemon_turn_flags(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench

	if active != null:
		active.reset_placed_this_turn()

	for bench_pokemon in bench:
		bench_pokemon.reset_placed_this_turn()

# ISSUE #75 FIX: opponent_blocker is a FULL-SCREEN input blocker that is up for the whole of the
# opponent's turn (and from the moment the player commits to an attack). Any UI that still needs the
# player to click, scroll or dismiss something while it is up — a card selection, a revealed hand, an
# attack-copy button list — must suspend it first and restore it afterwards, otherwise every click is
# eaten by the blocker. Same root cause as issues #3 and #21; these helpers are the shared version.
func suspend_opponent_blocker(context: String = "") -> bool:
	var was_visible = opponent_blocker.visible
	opponent_blocker.visible = false
	print("ISSUE #75 FIX ACTIVE (", context, "): opponent_blocker suspended, will restore to ", was_visible)
	return was_visible

func restore_opponent_blocker(was_visible: bool, context: String = "") -> void:
	opponent_blocker.visible = was_visible
	print("ISSUE #75 FIX ACTIVE (", context, "): opponent_blocker restored to ", was_visible)

# Called at the start of the player's turn to perform mandatory actions
func player_start_turn_checks() -> void:
	if _should_bail():
		return
	# Reset trainer lock from Headache
	trainer_effects.reset_trainer_lock(false)
	opponent_blocker.visible = false
	# ISSUE #281: up out of the player's corner, exactly like "End turn".
	print("ISSUE #281 FIX ACTIVE: turn labels rise from ", _turn_float_anchor())
	show_floating_label("Start turn", _turn_float_anchor(), Color.WHITE, true)
	turn_number += 1
	_refresh_turn_chip()
	print("PLAYER'S TURN START. TURN NUMBER IS ", turn_number)
	var drawn_card = await draw_card_from_deck(false)

	opponents_turn_active = false
	_refresh_turn_divider()
	update_main_screen_buttons()

	if drawn_card == null:
		return

	# MATCH EFFECT: draw_count — draw extra cards at turn start (deck-out handled inside)
	for extra_draw in range(match_effects.turn_start_draw_count(false) - 1):
		var extra_card = await draw_card_from_deck(false)
		if extra_card == null:
			return

	refresh_hand_display(false)
	update_deck_icon(false)
	powers_and_bodies.refresh_holon_veil()   # EX15 Holon Veil: recompute board-wide δ grant

	# Update Ditto Transform state (may need to re-transform after opponent turn changes)
	powers_and_bodies.update_ditto_transform(false)
	powers_and_bodies.update_ditto_transform(true)

	# NEO1: process turn-start tools (Gold Berry, Berry, Miracle Berry) and Char counters for player's side
	await powers_and_bodies.process_turn_start_tools_and_counters(false)
	if _should_bail(): return

	# EX11 Holon Ruins (ex11-96 Stadium): once per turn, a player with a δ Pokemon in play may draw a
	# card, then discard a card. Offered at the start of the turn.
	await trainer_effects.holon_ruins_offer_draw(false)
	if _should_bail(): return

	# EX12 Power Tree / Strange Cave (Stadiums): once-per-turn optional actions, offered at turn start.
	await trainer_effects.ex12_power_tree_offer(false)
	if _should_bail(): return
	await trainer_effects.ex12_strange_cave_offer(false)
	if _should_bail(): return

## ISSUE #217: End Turn, with the board committed before anything else runs.
func _on_end_turn_pressed() -> void:
	if _end_turn_btn != null and is_instance_valid(_end_turn_btn):
		_end_turn_btn.disabled = true
	set_action_rows_disabled(true)
	player_end_turn_checks()


# Called when the player presses the end turn button to reset per-turn variables and begin next turn
func player_end_turn_checks() -> void:
	# ISSUE #47 FIX: if the game already ended (e.g. the attack that ends this turn took the last
	# prize card), don't run end-turn processing or flash the "End turn" label over the "You won!"
	# message — the match is already over.
	if game_is_over:
		return
	opponent_blocker.visible = true
	opponents_turn_active = true
	_refresh_turn_divider()
	update_main_screen_buttons()
	# ISSUE #281: the same anchor "Start turn" now uses.
	show_floating_label("End turn", _turn_float_anchor(), Color.WHITE, true)
	
	await check_all_knockouts()
	
	if _should_bail():
		return
	
	await inbetween_turn_checks(true)

# Resets shared state between turns, processes status effects, and starts the next turn
func inbetween_turn_checks(player_turn_just_ended: bool = true) -> void:
	if _should_bail():
		return
	
	player_energy_played_this_turn = false
	player_retreated_this_turn = false
	opponent_energy_played_this_turn = false
	opponent_retreated_this_turn = false
	player_energy_attach_count = 0
	opponent_energy_attach_count = 0
	# EX1+: reset the "1 Supporter per turn" flags for both sides on every turn transition
	trainer_effects.player_played_supporter_this_turn = false
	trainer_effects.opponent_played_supporter_this_turn = false
	# EX5: reset the once-per-turn "1 per turn across all copies" power flags for both sides
	player_ex5_heal_dance_used = false
	opponent_ex5_heal_dance_used = false
	player_ex5_weather_used = false
	opponent_ex5_weather_used = false
	player_ex8_form_change_used = false
	opponent_ex8_form_change_used = false
	player_ex8_happy_dance_used = false
	opponent_ex8_happy_dance_used = false
	# EX8 Bay Dance: promote the pending buff to active for the side whose turn is now beginning,
	# and clear the buff for the side whose turn just ended (its boosted turn is over).
	var beginning_is_opponent = player_turn_just_ended
	if beginning_is_opponent:
		player_ex8_bay_dance_active = false
		opponent_ex8_bay_dance_active = opponent_ex8_bay_dance_pending
		opponent_ex8_bay_dance_pending = false
	else:
		opponent_ex8_bay_dance_active = false
		player_ex8_bay_dance_active = player_ex8_bay_dance_pending
		player_ex8_bay_dance_pending = false
	# EX3/EX9 Dragon Dance: same pending→active promotion as Bay Dance above.
	if beginning_is_opponent:
		player_dragon_dance_active = 0
		opponent_dragon_dance_active = opponent_dragon_dance_pending
		opponent_dragon_dance_pending = 0
	else:
		opponent_dragon_dance_active = 0
		player_dragon_dance_active = player_dragon_dance_pending
		player_dragon_dance_pending = 0
	xxxxx_used_this_turn = false
	# EX8 Sunbeam (Solrock): recompute Lunatone max-HP boost each turn transition.
	powers_and_bodies.refresh_ex8_sunbeam_hp()
	# EX9 Mystic Scale (Milotic ex): discard all Technical Machine cards in play while it's out.
	powers_and_bodies.ex9_enforce_mystic_scale()
	reset_field_pokemon_turn_flags(false)
	reset_field_pokemon_turn_flags(true)

	# Stadium per-turn flag resets — clear the flag belonging to the side whose turn JUST ended,
	# so that side can use it again next turn (and the other side already has theirs cleared from earlier).
	if player_turn_just_ended:
		player_celadon_used_this_turn = false
		player_fuchsia_used_this_turn = false
		player_apricorn_forest_used_this_turn = false
		player_undersea_ruins_used_this_turn = false
		player_power_plant_used_this_turn = false
		player_ancient_ruins_used_this_turn = false
		player_mystery_zone_used_this_turn = false
		player_underground_lake_used_this_turn = false
		player_lucky_stadium_used_this_turn = false
		player_saffron_used_this_turn = false
		player_healing_field_used_this_turn = false
	else:
		opponent_celadon_used_this_turn = false
		opponent_fuchsia_used_this_turn = false
		opponent_apricorn_forest_used_this_turn = false
		opponent_undersea_ruins_used_this_turn = false
		opponent_power_plant_used_this_turn = false
		opponent_ancient_ruins_used_this_turn = false
		opponent_mystery_zone_used_this_turn = false
		opponent_underground_lake_used_this_turn = false
		opponent_lucky_stadium_used_this_turn = false
		opponent_saffron_used_this_turn = false
		opponent_healing_field_used_this_turn = false
	
	# Mirror move tracking: clear if the side that just ended their turn didn't attack
	if player_turn_just_ended:
		if not player_attacked_this_turn:
			last_attack_on_opponent = {}
		player_attacked_this_turn = false
	else:
		if not opponent_attacked_this_turn:
			last_attack_on_player = {}
		opponent_attacked_this_turn = false

	# Remove end-of-turn statuses from the pokemon whose owner's turn just ended
	if player_turn_just_ended:
		# NEO1: clear jaw_clamp/screech flags that were set this turn (affect the opponent's side)
		powers_and_bodies.clear_neo1_flags_end_of_turn(true)
		# NEO2: clear lock_on/counter/pursuit/secrete_poison/slime/gaze flags (affect the opponent's side)
		powers_and_bodies.clear_neo2_flags_end_of_turn(true)
		# NEO3: clear triggered_poison/high_speed_locked/submerge/legendary_body flags
		powers_and_bodies.clear_neo3_flags_end_of_turn(true)
		# NEO4: clear perform_damage_stored on the player's own pokemon (just finished their attack turn)
		powers_and_bodies.clear_neo4_flags_end_of_turn(false)
		clear_end_of_turn_statuses(player_active_pokemon, false)
		clear_defensive_statuses(opponent_active_pokemon, true)
		clear_jungle_defensive_statuses(opponent_active_pokemon, true)
		player_retreat_disabled = false
		# Discard PlusPower from player's active at end of player's turn
		if player_active_pokemon != null:
			await trainer_effects.discard_pluspower_from_pokemon(player_active_pokemon, false)
		# Tick down Defender on opponent's pokemon (Defender discards at end of opponent's NEXT turn)
		await trainer_effects.tick_defender_counters(true)
		# GYM1: handle Charity / Sabrina's ESP / Recall / Misty boost expiry for the player's side
		await trainer_effects.gym1_end_of_turn_cleanup(false)
		# GYM1 Tickling Machine: if the player's own hand was tickled, restore it at the end of their own turn
		if player_hand_tickled:
			trainer_effects.gym1_restore_tickled_hand(false)
	else:
		# NEO1: clear jaw_clamp/screech flags that were set this turn (affect the player's side)
		powers_and_bodies.clear_neo1_flags_end_of_turn(false)
		# NEO2: clear lock_on/counter/pursuit/secrete_poison/slime/gaze flags (affect the player's side)
		powers_and_bodies.clear_neo2_flags_end_of_turn(false)
		# NEO3: clear triggered_poison/high_speed_locked/submerge/legendary_body flags
		powers_and_bodies.clear_neo3_flags_end_of_turn(false)
		# NEO4: clear perform_damage_stored on the opponent's own pokemon (just finished their attack turn)
		powers_and_bodies.clear_neo4_flags_end_of_turn(true)
		clear_end_of_turn_statuses(opponent_active_pokemon, true)
		clear_defensive_statuses(player_active_pokemon, false)
		clear_jungle_defensive_statuses(player_active_pokemon, false)
		opponent_retreat_disabled = false
		# Discard PlusPower from opponent's active at end of opponent's turn
		if opponent_active_pokemon != null:
			await trainer_effects.discard_pluspower_from_pokemon(opponent_active_pokemon, true)
		# Tick down Defender on player's pokemon
		await trainer_effects.tick_defender_counters(false)
		# GYM1: handle Charity / Sabrina's ESP / Recall / Misty boost expiry for the opponent's side
		await trainer_effects.gym1_end_of_turn_cleanup(true)
		# GYM1 Tickling Machine: if opponent's own hand was tickled, restore it at the end of their own turn
		if opponent_hand_tickled:
			trainer_effects.gym1_restore_tickled_hand(true)
	
	if _should_bail():
		return
	
	# Reset power_used_this_turn for all pokemon
	if player_turn_just_ended:
		powers_and_bodies.reset_power_used_flags(false)
	else:
		powers_and_bodies.reset_power_used_flags(true)
	
	# Goop Gas Attack: expires at end of opponent's next turn
	# Player played it (owner=false): expires when opponent's turn ends (player_turn_just_ended=false)
	# CPU played it (owner=true): expires when player's turn ends (player_turn_just_ended=true)
	if goop_gas_active:
		if (goop_gas_owner_is_opponent and player_turn_just_ended) or (not goop_gas_owner_is_opponent and not player_turn_just_ended):
			goop_gas_active = false
			print("GOOP GAS: Effect expired")

	# GYM2 Transparent Walls: expire at end of opponent's next turn (same timing pattern as Goop Gas)
	if player_transparent_walls_active and not player_turn_just_ended:
		player_transparent_walls_active = false
		print("GYM2 TRANSPARENT WALLS (player) expired")
	if opponent_transparent_walls_active and player_turn_just_ended:
		opponent_transparent_walls_active = false
		print("GYM2 TRANSPARENT WALLS (opponent) expired")
	
	# Clear power_disabled_until_end_of_next_turn (Dark Arbok Stare)
	# Stare disables "until the end of your opponent's next turn", so clear the flag
	# at the end of the AFFECTED pokemon's owner's turn (not the attacker's turn).
	if player_turn_just_ended:
		# Player's turn just ended — clear player's own disabled flags
		for bp in player_bench:
			bp.power_disabled_until_end_of_next_turn = false
		if player_active_pokemon != null:
			player_active_pokemon.power_disabled_until_end_of_next_turn = false
	else:
		# Opponent's turn just ended — clear opponent's disabled flags
		for bp in opponent_bench:
			bp.power_disabled_until_end_of_next_turn = false
		if opponent_active_pokemon != null:
			opponent_active_pokemon.power_disabled_until_end_of_next_turn = false
	
	# Update Ditto Transform after any switches/KOs that may have happened
	powers_and_bodies.update_ditto_transform(false)
	powers_and_bodies.update_ditto_transform(true)

	# Process between-turn effects (poison, burn, sleep) for both active pokemon
	if player_active_pokemon != null:
		await process_status_between_turns(player_active_pokemon, false)
	if _should_bail():
		return
	if opponent_active_pokemon != null:
		await process_status_between_turns(opponent_active_pokemon, true)
	if _should_bail():
		return

	await check_all_knockouts()

	if _should_bail():
		return

	# NP between-turn passive bodies: Rain Dish (heal Ludicolo), Burning Aura (damage both Actives)
	await powers_and_bodies.apply_np_between_turn_bodies()
	if _should_bail():
		return

	# Rocket's Hideout (neo3) / Low Pressure System (ex3): safety-net HP-bonus refresh for pokemon
	# placed while the stadium is active.
	if is_stadium_in_play(StadiumIds.ROCKETS_HIDEOUT) or is_stadium_in_play(StadiumIds.LOW_PRESSURE_SYSTEM):
		powers_and_bodies.refresh_rockets_hideout_hp()

	# EX3 Buffer Piece (ex3-83): discard at the end of the opponent's turn following the turn it was played.
	await trainer_effects.ex3_buffer_piece_check()
	if _should_bail(): return

	# ECARD2 Healing Berry: at the end of ANY turn (both sides, not just the owner's own), if the
	# holder has 20 HP or less, remove 3 damage counters and discard the berry
	await trainer_effects.ecard2_healing_berry_check()
	if _should_bail(): return

	# ECARD3 Star Piece: between turns, if the holder is Benched with 2+ damage counters,
	# may search deck for an Evolution card that Pokemon evolves into and auto-evolve it
	await trainer_effects.ecard3_star_piece_check()
	if _should_bail(): return

	# EX1 Lum Berry / Oran Berry: between turns, both sides, cure Special Conditions / heal 2 counters
	await trainer_effects.ex1_lum_berry_check()
	if _should_bail(): return
	await trainer_effects.ex1_oran_berry_check()
	if _should_bail(): return

	# EX4 Team Aqua Belt / Team Magma Belt: between turns, if the Active holder can evolve, search
	# the deck for its evolution, evolve it, then discard the Belt
	await trainer_effects.ex4_belt_check()
	if _should_bail(): return

	await check_all_knockouts()
	if _should_bail():
		return

	# NP Championship Arena: at end of each player's turn, if 8+ cards in hand discard to 7
	await trainer_effects.np_championship_arena_check(player_turn_just_ended)
	if _should_bail():
		return

	# MATCH EFFECT: end_of_turn_heal — every pokemon in play (active + bench) heals X
	# between turns. Routed through heal_pokemon so no_healing/healing_multiplier apply.
	for heal_side in [false, true]:
		var rule_heal = match_effects.end_of_turn_heal_amount(heal_side)
		if rule_heal <= 0:
			continue
		var side_active = opponent_active_pokemon if heal_side else player_active_pokemon
		var side_bench = opponent_bench if heal_side else player_bench
		var side_pokemon = []
		if side_active != null:
			side_pokemon.append(side_active)
		side_pokemon.append_array(side_bench)
		for heal_target in side_pokemon:
			if heal_target.current_hp < heal_target.get_max_hp() and not heal_target.is_bench_token:
				await card_ops.heal_pokemon(heal_target, rule_heal, heal_side)
				if _should_bail():
					return

	if player_turn_just_ended:
		await cpu_ai.opponent_start_turn_checks()
	else:
		await player_start_turn_checks()
		
# Removes statuses that expire at the end of the affected player's own turn
func clear_end_of_turn_statuses(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null:
		return

	var pokemon_name = pokemon.metadata.get("name", "Unknown")
	var changed = false

	if pokemon.special_condition == "Paralyzed":
		pokemon.special_condition = ""
		print("END OF TURN: ", pokemon_name, " is no longer Paralyzed")
		changed = true

	if pokemon.is_blind:
		pokemon.is_blind = false
		print("END OF TURN: ", pokemon_name, " is no longer Blind")
		changed = true
	
	# Clear end_of_turn disabled attacks; demote skip_one_turn -> end_of_turn so it survives the owner's NEXT turn
	var keys_to_remove = []
	var keys_to_demote = []
	for atk_name in pokemon.disabled_attacks:
		if pokemon.disabled_attacks[atk_name] == "end_of_turn":
			keys_to_remove.append(atk_name)
			print("END OF TURN: ", pokemon_name, " attack '", atk_name, "' re-enabled")
			changed = true
		elif pokemon.disabled_attacks[atk_name] == "skip_one_turn":
			keys_to_demote.append(atk_name)
	for key in keys_to_remove:
		pokemon.disabled_attacks.erase(key)
	for key in keys_to_demote:
		pokemon.disabled_attacks[key] = "end_of_turn"

	# GYM2 Brock's Dugtrio Lie Low: tick down the Earthdrill availability window
	if pokemon.gym2_lie_low_counter > 0:
		pokemon.gym2_lie_low_counter -= 1

	if changed:
		update_status_icons(pokemon, is_opponent)

# Removes no_damage, invincible, shielded, and destiny_bond shields that expire after the opposing player's turn
func clear_defensive_statuses(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null:
		return

	var changed = false
	var pokemon_name = pokemon.metadata.get("name", "Unknown")

	if pokemon.has_no_damage:
		pokemon.has_no_damage = false
		print("EXPIRED: ", pokemon_name, " no_damage shield wore off")
		changed = true

	if pokemon.is_invincible:
		pokemon.is_invincible = false
		print("EXPIRED: ", pokemon_name, " invincible shield wore off")
		changed = true
	
	if pokemon.shielded_damage_threshold > 0:
		pokemon.shielded_damage_threshold = 0
		print("EXPIRED: ", pokemon_name, " shielded damage threshold wore off")
		changed = true
	
	if pokemon.has_destiny_bond:
		pokemon.has_destiny_bond = false
		print("EXPIRED: ", pokemon_name, " destiny bond wore off")
		changed = true

	if changed:
		update_status_icons(pokemon, is_opponent)

# Also clear Jungle-set defensive properties (called from same timing)
func clear_jungle_defensive_statuses(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null:
		return
	if pokemon.damage_reduction_next_turn > 0:
		pokemon.damage_reduction_next_turn = 0
		print("EXPIRED: ", pokemon.metadata.get("name", ""), " damage reduction wore off")
	if pokemon.attack_blocked_next_turn:
		pokemon.attack_blocked_next_turn = false
		pokemon.attack_blocked_by_id = -1
		print("EXPIRED: ", pokemon.metadata.get("name", ""), " attack block wore off")
	if pokemon.attack_flip_blocked:
		pokemon.attack_flip_blocked = false
		print("EXPIRED: ", pokemon.metadata.get("name", ""), " coin-flip attack block wore off")
	if pokemon.gym2_mega_burn_locked:
		pokemon.gym2_mega_burn_locked = false
		print("EXPIRED: ", pokemon.metadata.get("name", ""), " Mega Burn lock wore off")
	# GYM1: Crosscounter / Fire Wall counter-attacks and Deflector halving wear off after the opponent's turn
	if pokemon.counter_attack_double:
		pokemon.counter_attack_double = false
		print("EXPIRED: ", pokemon.metadata.get("name", ""), " Crosscounter wore off")
	if pokemon.counter_attack_fixed > 0:
		pokemon.counter_attack_fixed = 0
		print("EXPIRED: ", pokemon.metadata.get("name", ""), " Fire Wall wore off")
	if pokemon.damage_halved_next_turn:
		pokemon.damage_halved_next_turn = false
		print("EXPIRED: ", pokemon.metadata.get("name", ""), " Deflector wore off")

########################################################### Evolution functions ##############################################################

# Scans active and bench for Pokemon that the given evolution card can legally evolve from
func get_valid_evolution_targets(evolution_card: card_object, is_opponent: bool) -> Array:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var valid_targets = []

	# GYM2 Giovanni allows evolving on turn 1+ and ignores the placed-this-turn restriction for a tagged pokemon.
	var first_turn_block = turn_number <= 2

	for bench_pokemon in bench:
		var giovanni_override = bench_pokemon.gym2_giovanni_evolve_anywhere
		if first_turn_block and not giovanni_override:
			continue
		if bench_pokemon.placed_on_field_this_turn and not giovanni_override:
			continue
		if can_evolve_from(evolution_card, bench_pokemon):
			valid_targets.append(bench_pokemon)

	if active != null:
		var giovanni_override_a = active.gym2_giovanni_evolve_anywhere
		var block = (first_turn_block and not giovanni_override_a) or (active.placed_on_field_this_turn and not giovanni_override_a)
		if not block and can_evolve_from(evolution_card, active):
			valid_targets.append(active)

	# ECARD3 Primal Aura (Kabutops): while EITHER side's Active is Kabutops, neither player can
	# evolve a Benched Pokemon
	var kabutops_active = (player_active_pokemon != null and player_active_pokemon.has_ability("Primal Aura") and not powers_and_bodies.is_power_blocked_by_status(player_active_pokemon)) or (opponent_active_pokemon != null and opponent_active_pokemon.has_ability("Primal Aura") and not powers_and_bodies.is_power_blocked_by_status(opponent_active_pokemon))
	if kabutops_active:
		valid_targets = valid_targets.filter(func(t): return t == active)

	# ECARD3 Primal Stare (Omastar): while Omastar is your opponent's Active Pokemon, you can't
	# evolve YOUR Active Pokemon (Benched evolutions are unaffected)
	var opposing_active = opponent_active_pokemon if not is_opponent else player_active_pokemon
	if opposing_active != null and opposing_active.has_ability("Primal Stare") and not powers_and_bodies.is_power_blocked_by_status(opposing_active):
		valid_targets = valid_targets.filter(func(t): return t != active)

	# EX4-90 Cradily ex Primal Vibes: while the opposing Active is Cradily ex, you can't play a
	# Pokemon from hand to evolve YOUR Active (Benched evolutions are unaffected)
	if opposing_active != null and opposing_active.has_ability("Primal Vibes") and not powers_and_bodies.is_power_blocked_by_status(opposing_active):
		valid_targets = valid_targets.filter(func(t): return t != active)

	# EX11 Binding Aura (Hypno): while the opposing Active is Hypno, you can't play a Basic/Evolution
	# from hand to evolve YOUR Active Pokemon (Benched evolutions are unaffected).
	if opposing_active != null and opposing_active.has_ability("Binding Aura") and not powers_and_bodies.is_power_blocked_by_status(opposing_active):
		valid_targets = valid_targets.filter(func(t): return t != active)

	return valid_targets

# Stores the evolution card and enters target selection mode for the player to pick which Pokemon to evolve
func start_evolution() -> void:
	if selected_card_for_action == null:
		print("Error: No evolution card selected")
		return
	
	# Check Aerodactyl's Prehistoric Power
	if powers_and_bodies.is_prehistoric_power_active():
		await show_message("PREHISTORIC POWER: EVOLUTION IS BLOCKED!")
		if _should_bail(): return
		return
	
	evolution_card_awaiting_target = selected_card_for_action
	
	var valid_targets = get_valid_evolution_targets(evolution_card_awaiting_target, false)
	
	if valid_targets.size() == 0:
		print("Error: No valid evolution targets found")
		evolution_card_awaiting_target = null
		return
	
	evolution_mode_active = true
	show_enlarged_array_selection_mode(valid_targets)
	
	var evo_name = evolution_card_awaiting_target.metadata.get("name", "Unknown")
	header_label.text = "EVOLVING INTO " + evo_name.to_upper()
	hint_label.text = "Select a Pokémon to evolve into " + evo_name
	
	action_button.text = "EVOLVE"
	action_button.disabled = true
	action_button.theme = theme_disabled

# Replaces a Pokemon on the field with its evolution, transferring all attachments and damage
func perform_evolution(is_opponent: bool) -> void:
	if evolution_card_awaiting_target == null or selected_card_for_action == null:
		print("Error: Missing evolution card or target")
		return
	
	var evo_card = evolution_card_awaiting_target
	var target_card = selected_card_for_action
	
	# Calculate damage taken on the pre-evolution to carry over
	var max_hp_old = int(target_card.metadata.get("hp", "0"))
	var damage_taken = max_hp_old - target_card.current_hp
	
	# Set the new card's HP as its max minus the carried damage
	var max_hp_new = int(evo_card.metadata.get("hp", "0"))
	evo_card.current_hp = max(1, max_hp_new - damage_taken)
	
	# Transfer all attached energies from old card to new card
	evo_card.attached_energies = target_card.attached_energies.duplicate()
	target_card.attached_energies.clear()

	# ISSUE #58 FIX: transfer attached cards (Pokémon Tools like Defender/PlusPower and any other
	# attached trainers) onto the evolution — previously these were silently dropped on evolving.
	# Carry the associated counters/timers so the tools keep working on the new top card.
	evo_card.attached_cards = target_card.attached_cards.duplicate()
	target_card.attached_cards.clear()
	evo_card.defender_turns_remaining = target_card.defender_turns_remaining
	evo_card.defender_count = target_card.defender_count
	evo_card.pluspower_count = target_card.pluspower_count
	target_card.defender_turns_remaining = -1
	target_card.defender_count = 0
	target_card.pluspower_count = 0
	
	# Transfer existing pre-evolutions then add the old card itself to the chain
	evo_card.attached_pre_evolutions = target_card.attached_pre_evolutions.duplicate()
	target_card.attached_pre_evolutions.clear()
	evo_card.attached_pre_evolutions.append(target_card)
	
	# Mark as played this turn so it can't evolve again immediately
	evo_card.placed_on_field_this_turn = true

	# GYM2 Giovanni: pass the evolve-anywhere buff onto the new top card per card rules
	if target_card.gym2_giovanni_evolve_anywhere:
		evo_card.gym2_giovanni_evolve_anywhere = true
	
	# Remove evolution card from the correct hand
	var hand = opponent_hand if is_opponent else player_hand
	hand.erase(evo_card)
	
	# Replace the target card in its current location
	evo_card.current_location = target_card.current_location
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	
	if target_card == active:
		if is_opponent:
			opponent_active_pokemon = evo_card
		else:
			player_active_pokemon = evo_card
	else:
		var bench_index = bench.find(target_card)
		if bench_index != -1:
			bench[bench_index] = evo_card
	
	print(target_card.metadata["name"], " evolved into ", evo_card.metadata["name"], "! (Damage carried: ", damage_taken, ")")
	clear_all_statuses(target_card, is_opponent)

	# GYM2-123 Viridian City Gym — when a Giovanni-named pokemon evolves, heal 20 (or 10 if only 1 counter)
	if is_stadium_in_play(StadiumIds.VIRIDIAN_CITY_GYM) and "Giovanni" in evo_card.metadata.get("name", ""):
		var counters = max_hp_new - evo_card.current_hp
		# MATCH EFFECTS: no_healing / healing_multiplier gate
		var viridian_heal = match_effects.modify_heal_amount(20 if counters >= 20 else 10, is_opponent)
		if counters > 0 and viridian_heal > 0:
			var heal_amount = viridian_heal
			evo_card.current_hp = min(max_hp_new, evo_card.current_hp + heal_amount)
			display_hp_circles_above_align(evo_card, is_opponent)
			await show_message("VIRIDIAN CITY GYM: " + evo_card.metadata.get("name", "").to_upper() + " HEALED " + str(heal_amount) + " HP!")
			if _should_bail(): return

	# MATCH EFFECT: evolve_full_heal — evolving fully heals (unless healing is blocked)
	if match_effects.evolve_full_heal(is_opponent) and not match_effects.healing_blocked(is_opponent):
		if evo_card.current_hp < evo_card.get_max_hp():
			evo_card.current_hp = evo_card.get_max_hp()
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
			display_hp_circles_above_align(evo_card, is_opponent)
			await show_message("SPECIAL MATCH RULE: " + evo_card.metadata.get("name", "").to_upper() + " WAS FULLY HEALED BY EVOLVING!")
			if _should_bail(): return

	# BASE5: When-played powers trigger when evolved from hand. Gate on the ability itself — the ex7
	# reprints share these names (Dark Dragonite/Dark Golbat) but have different abilities.
	var evo_name = evo_card.metadata.get("name", "")
	if evo_name == "Dark Dragonite" and evo_card.has_ability("Summon Minions"):
		await powers_and_bodies.trigger_summon_minions(evo_card, is_opponent)
	elif evo_name == "Dark Golbat" and evo_card.has_ability("Sneak Attack"):
		await powers_and_bodies.trigger_sneak_attack(evo_card, is_opponent)
	elif evo_name == "Dark Slowbro" and evo_card.has_ability("Reel In"):
		await powers_and_bodies.trigger_reel_in(evo_card, is_opponent)
	# NEO1: on-play power triggers
	elif evo_name in ["Feraligatr"] and evo_card.has_ability("Berserk"):
		await powers_and_bodies.trigger_neo1_berserk(evo_card, is_opponent)
	elif evo_name in ["Meganium"] and evo_card.has_ability("Herbal Scent"):
		await powers_and_bodies.trigger_neo1_herbal_scent(evo_card, is_opponent)
	elif evo_name in ["Typhlosion"] and evo_card.has_ability("Fire Boost"):
		await powers_and_bodies.trigger_neo1_fire_boost(evo_card, is_opponent)
	# NEO4: on-play (evolve from hand) power triggers
	elif evo_card.has_ability("Surprise Bite"):
		await powers_and_bodies.trigger_neo4_surprise_bite(evo_card, is_opponent)
	elif evo_card.has_ability("Gift"):
		await powers_and_bodies.trigger_neo4_gift(evo_card, is_opponent)
	elif evo_card.has_ability("Tag Team"):
		await powers_and_bodies.trigger_neo4_tag_team(evo_card, is_opponent)
	# ECARD3: on-play (evolve from hand) power triggers
	elif evo_card.has_ability("Energy Recharge"):
		await powers_and_bodies.trigger_ecard3_energy_recharge(evo_card, is_opponent)
	elif evo_card.has_ability("Venom Spray"):
		await powers_and_bodies.trigger_ecard3_venom_spray(evo_card, is_opponent)
	elif evo_card.has_ability("Manipulate"):
		await powers_and_bodies.trigger_ecard3_manipulate(evo_card, is_opponent)
	elif evo_card.has_ability("Flame Vapor"):
		await powers_and_bodies.trigger_ecard3_flame_vapor(evo_card, is_opponent)
	elif evo_card.has_ability("Streaming Mantle"):
		await powers_and_bodies.trigger_ecard3_streaming_mantle(evo_card, is_opponent)
	elif evo_card.has_ability("Attract Energy"):
		await powers_and_bodies.trigger_ecard3_attract_energy(evo_card, is_opponent)
	# EX3 Loose Shell (Ninjask ex3-18): when Ninjask evolves from hand, may search deck for Shedinja onto Bench
	elif evo_card.has_ability("Loose Shell"):
		await powers_and_bodies.trigger_ex3_loose_shell(evo_card, is_opponent)
	# EX5 Healing Shower (Milotic ex5-12): on evolve, may remove all damage from all Pokemon (excl ex)
	elif evo_card.has_ability("Healing Shower"):
		await powers_and_bodies.trigger_ex5_healing_shower(evo_card, is_opponent)
	# EX7 Froth (Azumarill ex7-1): on evolving an Active, each Defending Pokemon is now Paralyzed
	elif evo_card.has_ability("Froth"):
		await powers_and_bodies.trigger_ex7_froth(evo_card, is_opponent)
	# EX10 on-play (evolve from hand) power triggers
	elif evo_card.has_ability("Blissful Support"):
		await powers_and_bodies.trigger_ex10_blissful_support(evo_card, is_opponent)
	elif evo_card.has_ability("Devo Flash"):
		await powers_and_bodies.trigger_ex10_devo_flash(evo_card, is_opponent)
	elif evo_card.has_ability("Bursting Up"):
		await powers_and_bodies.trigger_ex10_bursting_up(evo_card, is_opponent)
	elif evo_card.has_ability("Darker Ring"):
		await powers_and_bodies.trigger_ex10_darker_ring(evo_card, is_opponent)
	# EX11 on-play (evolve from hand) power triggers (Eeveelution ex)
	elif evo_card.has_ability("Evolutionary Flame"):
		await powers_and_bodies.trigger_ex11_evolutionary_flame(evo_card, is_opponent)
	elif evo_card.has_ability("Evolutionary Thunder"):
		await powers_and_bodies.trigger_ex11_evolutionary_thunder(evo_card, is_opponent)
	elif evo_card.has_ability("Evolutionary Swirl"):
		await powers_and_bodies.trigger_ex11_evolutionary_swirl(evo_card, is_opponent)
	# EX12 on-play (evolve from hand) power triggers
	elif evo_card.has_ability("Evolutionary Fan"):
		await powers_and_bodies.trigger_ex12_evolutionary_fan(evo_card, is_opponent)
	elif evo_card.has_ability("Emerge Charge"):
		await powers_and_bodies.trigger_ex12_emerge_charge(evo_card, is_opponent)
	# EX14 Peal of Thunder (Charizard δ ex14-4): on evolving, look at the top 5 cards and attach Energy.
	elif evo_card.has_ability("Peal of Thunder"):
		await powers_and_bodies.trigger_ex14_peal_of_thunder(evo_card, is_opponent)
	# EX15 on-play (evolve from hand) power triggers
	elif evo_card.has_ability("Evolutionary Call"):
		await powers_and_bodies.trigger_ex15_evolutionary_call(evo_card, is_opponent)
	elif evo_card.has_ability("Prowl"):
		await powers_and_bodies.trigger_ex15_prowl(evo_card, is_opponent)
	elif evo_card.has_ability("Dig Up"):
		await powers_and_bodies.trigger_ex15_dig_up(evo_card, is_opponent)
	# EX16 on-play (evolve from hand) power trigger
	elif evo_card.has_ability("Chilling Breath"):
		await powers_and_bodies.trigger_ex16_chilling_breath(evo_card, is_opponent)

	# EX7 Darkest Impulse (Dark Ampharos ex7-2): whenever the opponent evolves a Pokemon, the opposing
	# Dark Ampharos puts 2 damage counters on it. Fires for every evolution (both sides).
	await powers_and_bodies.check_ex7_darkest_impulse(evo_card, is_opponent)

	# EX15 Holon Veil (Ampharos δ): evolving may bring Ampharos into play or add a Pokémon to the δ set.
	powers_and_bodies.refresh_holon_veil()

	# ISSUE #58: refresh the attached-tool display so any Defender/PlusPower carried onto the evolution
	# is shown on the new Active card.
	trainer_effects.display_attached_trainer_cards(is_opponent)

	# ISSUE #71: Chain Reaction (basep-11 Eevee) triggers "when a Pokémon evolves" — offer it now to any
	# in-play Eevee with the power on either side (CPU auto-uses, player is prompted).
	await powers_and_bodies.trigger_chain_reaction_after_evolution()

########################################################### Retreat functions ##############################################################

# Checks if a Pokemon can retreat, returning a dictionary with "can_retreat" and "reason" if blocked
func can_retreat(is_opponent: bool) -> Dictionary:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var is_disabled = opponent_retreat_disabled if is_opponent else player_retreat_disabled
	var already_retreated = opponent_retreated_this_turn if is_opponent else player_retreated_this_turn
	
	if already_retreated:
		return {"can_retreat": false, "reason": "You have already retreated this turn!"}
	# MATCH EFFECT: no_retreat — retreating is blocked for this side all match
	if match_effects.retreat_blocked(is_opponent):
		return {"can_retreat": false, "reason": "Special match rule: retreating is not allowed!"}
	if active == null:
		return {"can_retreat": false, "reason": "No active Pokemon!"}
	if active.is_bench_token:
		return {"can_retreat": false, "reason": active.metadata.get("name", "") + " cannot retreat!"}
	if bench.size() == 0:
		return {"can_retreat": false, "reason": "Cannot retreat with no Pokemon on your bench!"}
	if is_disabled:
		return {"can_retreat": false, "reason": "You have been prevented from retreating!"}
	# EX5 Fast Feet (Dodrio ex5-33): can retreat even when Asleep or Paralyzed
	var fast_feet = active.has_ability("Fast Feet") and not powers_and_bodies.is_power_blocked(active)
	if not fast_feet and active.special_condition == "Paralyzed":
		return {"can_retreat": false, "reason": active.metadata.get("name", "") + " is Paralyzed and cannot retreat!"}
	if not fast_feet and active.special_condition == "Asleep":
		return {"can_retreat": false, "reason": active.metadata.get("name", "") + " is Asleep and cannot retreat!"}
	if active.attached_energies.size() < get_retreat_cost(active):
		return {"can_retreat": false, "reason": "Not enough energy to retreat!"}

	# Snorlax Guard (basep-49): opposing active Snorlax blocks retreat
	if powers_and_bodies.check_guard_body(is_opponent):
		return {"can_retreat": false, "reason": "Guard! The opposing Pokemon prevents you from retreating!"}

	# EX6 Spiral (Poliwrath ex6-11): while opposing Poliwrath is Active, a Confused Active can't retreat
	if powers_and_bodies.is_ex6_spiral_blocking(active):
		return {"can_retreat": false, "reason": "Spiral! Your Confused Pokemon can't retreat!"}

	# EX8 Boost Energy (ex8-93): the Pokemon it's attached to can't retreat.
	for e in active.attached_energies:
		if e.metadata.get("name", "") == "Boost Energy":
			return {"can_retreat": false, "reason": "Boost Energy! " + active.metadata.get("name", "") + " can't retreat!"}

	return {"can_retreat": true, "reason": ""}

# Initiates the retreat flow: validates, then shows attached energies for the player to select for discarding
func start_retreat() -> void:
	var retreat_check = can_retreat(false)
	
	if not retreat_check["can_retreat"]:
		await show_message(retreat_check["reason"])
		return
	
	var cost = get_retreat_cost(player_active_pokemon)
	
	if cost == 0:
		start_retreat_bench_selection()
		return
	
	retreat_mode_active = true
	retreat_energies_selected.clear()
	retreat_cost_remaining = cost
	
	var display_array = player_active_pokemon.attached_energies.duplicate()
	# ISSUE #80: also show any attached tool cards beside the energies (they're not selectable for the
	# retreat cost — the click handler ignores them — but they read as attached, matching the preview).
	display_array.append_array(player_active_pokemon.attached_cards)
	display_array.append(player_active_pokemon)

	show_enlarged_array_selection_mode(display_array)

	header_label.text = "RETREAT - SELECT ENERGY TO DISCARD"
	hint_label.text = "Select " + str(retreat_cost_remaining) + " energy card(s) to discard"
	action_button.text = str(retreat_cost_remaining) + " ENERGY REMAINING"
	action_button.disabled = true
	action_button.theme = theme_disabled

# Shows the player's bench for selecting which Pokemon to swap into the active spot
func start_retreat_bench_selection() -> void:
	selected_card_for_action = null
	retreat_mode_active = false
	retreat_bench_selection_active = true
	
	show_enlarged_array_selection_mode(player_bench)
	
	header_label.text = "SELECT NEW ACTIVE POKEMON"
	hint_label.text = "Choose a bench Pokemon to switch into the active spot"
	action_button.text = "MAKE ACTIVE"
	action_button.disabled = true
	action_button.theme = theme_disabled#

########################################################## END CORE FUNCTIONALITY FUNCTIONS ##########################################################
######################################################################################################################################################
#
#	           ##    ########  #######     ##     ######  ##   ##
#             ####      ##       ##       ####    ##      ##  ##
#            ##  ##     ##       ##      ##  ##   ##      ####
#           ########    ##       ##     ########  ##      ##  ##
#          ##      ##   ##       ##    ##      ## ######  ##    ##

######################################################################################################################################################
############################################################ ATTACK AND DAMAGE FUNCTIONS #############################################################

############################################################## Attacking helper functions ###########################################################
													
# Returns the attacks array for any given card object.
func get_attacks_for_card(card: card_object) -> Array:

	# Guard against null being passed in (e.g. no active pokemon yet)
	if card == null:
		return []

	# EX4 Power Saver (Kyogre ex4-3 / Groudon ex4-9): can't attack while few Team Pokemon are in play
	if powers_and_bodies.check_power_saver_blocks_attack(card):
		return []

	# EX5 Mark of Antiquity (Groudon ex / Kyogre ex): each player's named Legendary ex can't attack
	# while an opposing Mark of Antiquity holder is Active.
	if powers_and_bodies.check_ex5_mark_of_antiquity_blocks_attack(card):
		return []

	# ex10 Intimidating Ring (Ursaring): while Ursaring is Active, the opponent's Basic Pokemon can't attack.
	if powers_and_bodies.check_ex10_intimidating_ring_blocks_attack(card):
		return []

	# EX14 Intimidating Armor (Aggron ex ex14-89): while Aggron ex is Active, the opponent's Basic Pokemon can't attack.
	if powers_and_bodies.check_ex14_intimidating_armor_blocks_attack(card):
		return []

	# Get the attacks if they exist
	if powers_and_bodies.check_ex11_shining_horn_blocks_attack(card):
		return []

	# EX12 Deadlock (Dunsparce ex12-31): while a Dunsparce with this Body is the opposing Active, this
	# card (if it is a Dunsparce) can't attack.
	if powers_and_bodies.check_ex12_deadlock_blocks_attack(card):
		return []

	var attacks = card.metadata.get("attacks", [])

	# EX12 Versatile (Mew ex ex12-88): Mew ex can use the attacks of all Pokemon in play as its own.
	if card.has_ability("Versatile") and not powers_and_bodies.is_power_blocked(card):
		var seen_v: Dictionary = {}
		for atk in attacks:
			seen_v[atk.get("name","")] = true
		var v_extra: Array = []
		for side in [false, true]:
			for p in card_ops.get_all_pokemon_in_play(side):
				if p == card: continue
				for atk in p.metadata.get("attacks", []):
					var an = atk.get("name","")
					if an != "" and not seen_v.has(an):
						seen_v[an] = true
						v_extra.append(atk)
		if not v_extra.is_empty():
			return attacks + v_extra

	# EX11 Delta Aura (Latias/Latios δ): while its partner is in play, the paired attack costs less.
	attacks = powers_and_bodies.ex11_delta_aura_adjust_attacks(card, attacks)

	# Any Technical Machine card (ecard1-144, ecard2's 8 Cubes, the ex5 Ancient TMs):
	# "That Pokémon may use this card's attack instead of its own."
	#
	# "MAY ... INSTEAD OF" IS AN EXTRA OPTION, NOT A REPLACEMENT. This used to
	# `return ac.metadata.attacks` on the first Technical Machine found, which threw
	# away every attack the Pokemon actually had -- attaching an Ancient Technical
	# Machine to Exploud left it with only Ice Generator and no way back. The player
	# picks one attack per turn anyway, so offering both is what the card says.
	#
	# Appended with `+` rather than append() because `attacks` may still be the very
	# array inside card.metadata; mutating it would weld the TM's attack onto the
	# card permanently, long after the TM is discarded at end of turn.
	var tm_extra: Array = []
	var tm_seen: Dictionary = {}
	for atk in attacks:
		tm_seen[atk.get("name", "")] = true
	for ac in card.attached_cards:
		if "Technical Machine" in ac.metadata.get("subtypes", []):
			for atk in ac.metadata.get("attacks", []):
				var tm_name = atk.get("name", "")
				if tm_name != "" and not tm_seen.has(tm_name):
					tm_seen[tm_name] = true
					tm_extra.append(atk)
	if not tm_extra.is_empty():
		attacks = attacks + tm_extra

	# GYM1 Recall (gym1-116): this turn the Active may also use any attack from its Basic / Evolution chain.
	# We add attached_pre_evolutions' attacks to the list. Energy cost still applies per rules.
	if card.gym1_recall_active:
		var seen_names = {}
		for atk in attacks:
			seen_names[atk.get("name", "")] = true
		var extra: Array = []
		for pre_card in card.attached_pre_evolutions:
			for atk in pre_card.metadata.get("attacks", []):
				var atk_name = atk.get("name", "")
				if atk_name != "" and not seen_names.has(atk_name):
					seen_names[atk_name] = true
					extra.append(atk)
		if extra.size() > 0:
			return attacks + extra

	# EX8 Meteor Falls (ex8-89 Stadium): each player's Active Evolved Pokemon (excluding ex) may use
	# any attack from its Basic Pokemon or Stage 1 Evolution card. Energy cost still applies.
	if is_stadium_in_play(StadiumIds.METEOR_FALLS) and (card == player_active_pokemon or card == opponent_active_pokemon) and not is_ex_pokemon(card):
		var subs_mf = card.metadata.get("subtypes", [])
		if "Stage 1" in subs_mf or "Stage 2" in subs_mf:
			var seen_mf = {}
			for atk in attacks:
				seen_mf[atk.get("name", "")] = true
			var extra_mf: Array = []
			for pre_card in card.attached_pre_evolutions:
				for atk in pre_card.metadata.get("attacks", []):
					var atk_name = atk.get("name", "")
					if atk_name != "" and not seen_mf.has(atk_name):
						seen_mf[atk_name] = true
						extra_mf.append(atk)
			if extra_mf.size() > 0:
				return attacks + extra_mf

	# GYM2 Sabrina's Alakazam Psylink — also gain attacks of every Psychic Pokemon you control
	for ab in card.metadata.get("abilities", []):
		if ab.get("name", "") == "Psylink":
			var is_opp_psylink: bool = (card == opponent_active_pokemon or card in opponent_bench)
			return powers_and_bodies.get_psylink_attacks(card, is_opp_psylink)

	# NEO3 Genetic Memory (Kingdra neo3-19): replace the "Genetic Memory" meta-attack button with
	# the actual pre-evo attacks, each with empty cost (free, per card text).
	var has_genetic_memory_atk = false
	for atk in attacks:
		if atk.get("name", "") == "Genetic Memory":
			has_genetic_memory_atk = true
			break
	if has_genetic_memory_atk and card.attached_pre_evolutions.size() > 0:
		var gm_base: Array = []
		for atk in attacks:
			if atk.get("name", "") != "Genetic Memory":
				gm_base.append(atk)
		var seen_gm: Dictionary = {}
		for atk in gm_base:
			seen_gm[atk.get("name", "")] = true
		for pre_card in card.attached_pre_evolutions:
			for atk in pre_card.metadata.get("attacks", []):
				var atk_name = atk.get("name", "")
				if atk_name != "" and not seen_gm.has(atk_name):
					seen_gm[atk_name] = true
					var free_atk = atk.duplicate()
					free_atk["cost"] = []
					free_atk["convertedEnergyCost"] = 0
					gm_base.append(free_atk)
		return gm_base

	# NEO3 Mimic (Sudowoodo neo3-26): while Active and not statused, also gain the defender's attacks.
	# Slam stays available; defender attacks are appended with their original costs.
	if card == player_active_pokemon or card == opponent_active_pokemon:
		for ab in card.metadata.get("abilities", []):
			if ab.get("name", "") == "Mimic" and not card.gaze_suppressed:
				if not card.is_status_blocked():
					var mimic_defender = opponent_active_pokemon if (card == player_active_pokemon) else player_active_pokemon
					if mimic_defender != null:
						var seen_mimic: Dictionary = {}
						for atk in attacks:
							seen_mimic[atk.get("name", "")] = true
						var mimic_extra: Array = []
						for atk in mimic_defender.metadata.get("attacks", []):
							var n = atk.get("name", "")
							if n != "" and not seen_mimic.has(n):
								mimic_extra.append(atk)
						if mimic_extra.size() > 0:
							return attacks + mimic_extra
				break

	# NEO3 Prehistoric Memory (Aerodactyl neo3-15): evolved pokemon can use attacks from their pre-evo chain.
	# Works for any evolved pokemon on either side while any non-statused Aerodactyl with this power is in play.
	if card.attached_pre_evolutions.size() > 0:
		var prehistoric_active = false
		var all_field: Array = []
		if player_active_pokemon: all_field.append(player_active_pokemon)
		if opponent_active_pokemon: all_field.append(opponent_active_pokemon)
		all_field.append_array(player_bench)
		all_field.append_array(opponent_bench)
		for p in all_field:
			if p.gaze_suppressed or p.is_status_blocked(): continue
			for ab in p.metadata.get("abilities", []):
				if ab.get("name", "") == "Prehistoric Memory":
					prehistoric_active = true
					break
			if prehistoric_active: break
		if prehistoric_active:
			var seen_names: Dictionary = {}
			for atk in attacks:
				seen_names[atk.get("name", "")] = true
			var extra: Array = []
			for pre_card in card.attached_pre_evolutions:
				for atk in pre_card.metadata.get("attacks", []):
					var atk_name = atk.get("name", "")
					if atk_name != "" and not seen_names.has(atk_name):
						seen_names[atk_name] = true
						extra.append(atk)
			if extra.size() > 0:
				return attacks + extra

	# ECARD2 Memory Berry (ecard2-128): holder may also use any attack from its Basic Pokemon card
	# or any Evolution card it evolved from, at that attack's real cost (not free, unlike Genetic
	# Memory). Discarded at end of any turn the holder attacks — see gym1_end_of_turn_cleanup.
	if card.attached_pre_evolutions.size() > 0:
		var has_memory_berry = false
		for ac in card.attached_cards:
			if ac.uid.to_lower() in ["ecard2-128", "ex14-80"]:
				has_memory_berry = true
				break
		if has_memory_berry:
			var seen_mb: Dictionary = {}
			for atk in attacks:
				seen_mb[atk.get("name", "")] = true
			var mb_extra: Array = []
			for pre_card in card.attached_pre_evolutions:
				for atk in pre_card.metadata.get("attacks", []):
					var atk_name = atk.get("name", "")
					if atk_name != "" and not seen_mb.has(atk_name):
						seen_mb[atk_name] = true
						mb_extra.append(atk)
			if mb_extra.size() > 0:
				return attacks + mb_extra

	# EX7 Rocket's Tricky Gym (ex7-90): each Pokemon with "Dark" or "Rocket's" in its name may use the
	# Stadium's Feint Attack in addition to its own.
	if is_stadium_in_play(StadiumIds.ROCKETS_TRICKY_GYM) and current_stadium_card != null:
		var tg_name = card.metadata.get("name","")
		if "Dark" in tg_name or "Rocket's" in tg_name:
			var stadium_atks = current_stadium_card.metadata.get("attacks", [])
			if not stadium_atks.is_empty():
				var seen_tg: Dictionary = {}
				for atk in attacks:
					seen_tg[atk.get("name","")] = true
				var tg_extra: Array = []
				for atk in stadium_atks:
					if not seen_tg.has(atk.get("name","")):
						tg_extra.append(atk)
				if not tg_extra.is_empty():
					return attacks + tg_extra

	# EX13 Fellowship (Bellossom ex13-19): Bellossom may use the attacks of all Oddish, Gloom, Vileplume,
	# Vileplume ex, or other Bellossom you have in play as its own (energy cost still applies).
	if card.has_ability("Fellowship") and not powers_and_bodies.is_body_blocked(card):
		var fw_side = card.is_owner_opp(self)
		var fw_names = ["Oddish", "Gloom", "Vileplume", "Vileplume ex", "Bellossom"]
		var seen_fw: Dictionary = {}
		for atk in attacks:
			seen_fw[atk.get("name","")] = true
		var fw_extra: Array = []
		for p in card_ops.get_all_pokemon_in_play(fw_side):
			if p == card: continue
			if p.metadata.get("name","") not in fw_names: continue
			for atk in p.metadata.get("attacks", []):
				var an = atk.get("name","")
				if an != "" and not seen_fw.has(an):
					seen_fw[an] = true
					fw_extra.append(atk)
		if not fw_extra.is_empty():
			return attacks + fw_extra

	# EX13 Holon Lake (ex13-87 Stadium): each player's Pokémon that has δ on its card may use the
	# Stadium's Delta Call attack in addition to (in place of) its own.
	if is_stadium_in_play("ex13-87") and current_stadium_card != null and card.is_delta():
		var hl_atks = current_stadium_card.metadata.get("attacks", [])
		if not hl_atks.is_empty():
			var seen_hl: Dictionary = {}
			for atk in attacks:
				seen_hl[atk.get("name","")] = true
			var hl_extra: Array = []
			for atk in hl_atks:
				if not seen_hl.has(atk.get("name","")):
					hl_extra.append(atk)
			if not hl_extra.is_empty():
				return attacks + hl_extra

	return attacks

# Read an energy card passed to this function and return what energies this card actually provides.
# Returns the Pokemon that currently has `energy_card` in its attached_energies, or null.
func _find_energy_holder(energy_card: card_object) -> card_object:
	for p in ([player_active_pokemon] if player_active_pokemon != null else []) + player_bench \
			+ ([opponent_active_pokemon] if opponent_active_pokemon != null else []) + opponent_bench:
		if energy_card in p.attached_energies:
			return p
	return null

func get_energy_provided_by_card(energy_card: card_object) -> Array:
	var provided = _get_energy_provided_raw(energy_card)
	# EX14 Crystal Beach (ex14-75 Stadium): each Special Energy card that provides 2 or more Energy (both
	# players) now provides only 1 Colorless Energy. Not affected by any Poké-Powers or Poké-Bodies.
	# (Pokémon-as-Energy and Electrode-as-Energy are not "Special Energy cards", so they are excluded.)
	if provided.size() >= 2 and energy_card != null and not energy_card.attached_as_energy and not energy_card.is_electrode_energy:
		if "Special" in energy_card.metadata.get("subtypes", []) and is_stadium_in_play("ex14-75"):
			provided = ["Colorless"]
	# EX14 Chlorophyll (Venusaur ex14-28): all Energy cards that provide ONLY Colorless attached to your
	# Grass Pokemon provide Grass Energy instead, while a Venusaur with this Body is in play on that side.
	if energy_card != null and not energy_card.attached_as_energy and not energy_card.is_electrode_energy \
			and energy_card.metadata.get("supertype","").to_lower() == "energy" \
			and not provided.is_empty() and provided.all(func(t): return t == "Colorless"):
		var holder = _find_energy_holder(energy_card)
		if holder != null and "Grass" in holder.get_effective_types():
			var chl_side = holder.is_owner_opp(self)
			for p in card_ops.get_all_pokemon_in_play(chl_side):
				if p.has_ability("Chlorophyll") and not powers_and_bodies.is_power_blocked(p):
					return provided.map(func(_t): return "Grass")
	return provided

func _get_energy_provided_raw(energy_card: card_object) -> Array:
	if energy_card == null:
		return []

	# Electrode Buzzap: this card is an Electrode acting as energy
	if energy_card.is_electrode_energy:
		return [energy_card.electrode_energy_type]

	# EX11 Holon's Pokémon attached as a Special Energy card (Magnemite/Voltorb = Colorless;
	# Electrode/Magneton = every type, 2 at a time, stored as ["Any","Any"]).
	if energy_card.attached_as_energy:
		return energy_card.pokemon_energy_types
	
	var supertype = energy_card.metadata.get("supertype", "").to_lower()
	if supertype != "energy":
		return []
	
	var subtypes = energy_card.metadata.get("subtypes", [])
	var card_name = energy_card.metadata.get("name", "")
	
	# Basic energy: strip " Energy" from name to get the type string
	if "Basic" in subtypes:
		var energy_type = card_name.replace(" Energy", "").strip_edges()
		# EX11 Holon Research Tower (ex11-94 Stadium): each player's basic Energy attached to a Pokemon
		# that has δ on its card is both its usual type AND Metal (still only 1 Energy at a time).
		if is_stadium_in_play("ex11-94") and energy_type != "Metal":
			var holder = _find_energy_holder(energy_card)
			if holder != null and holder.is_delta():
				return [energy_type, "Metal"]
		return [energy_type]
	
	# EX8 Scramble Energy (ex8-95): while in play, if its owner has more Prize cards left than the
	# opponent, it provides every type of Energy but only 3 in any combination; otherwise 1 Colorless.
	if card_name == "Scramble Energy":
		var holder_is_opp := -1
		for p in ([player_active_pokemon] if player_active_pokemon != null else []) + player_bench:
			if energy_card in p.attached_energies:
				holder_is_opp = 0
				break
		if holder_is_opp == -1:
			for p in ([opponent_active_pokemon] if opponent_active_pokemon != null else []) + opponent_bench:
				if energy_card in p.attached_energies:
					holder_is_opp = 1
					break
		if holder_is_opp != -1:
			var my_prizes = opponent_prize_cards.size() if holder_is_opp == 1 else player_prize_cards.size()
			var their_prizes = player_prize_cards.size() if holder_is_opp == 1 else opponent_prize_cards.size()
			if my_prizes > their_prizes:
				return ["Any", "Any", "Any"]
		return ["Colorless"]

	# EX12 Reactive Booster (Gorebyss ex12-17 Poké-Body): each React Energy attached to any of your
	# Huntail and Gorebyss provides 2 Energy of every type. Needs holder context; resolved here.
	if card_name == "React Energy":
		var rb_holder = _find_energy_holder(energy_card)
		if rb_holder != null and rb_holder.metadata.get("name","") in ["Huntail", "Gorebyss"]:
			if powers_and_bodies.is_ex12_reactive_booster_active(rb_holder):
				return ["Any", "Any"]

	# EX13 δ Rainbow Energy (ex13-98): provides Colorless normally, but every type of Energy (1 at a
	# time) while attached to a Pokémon that has δ on its card. Needs holder context; resolved here.
	if card_name == "δ Rainbow Energy":
		var dr_holder = _find_energy_holder(energy_card)
		if dr_holder != null and dr_holder.is_delta():
			return ["Any"]
		return ["Colorless"]

	# Special energy: route through Special_Energy_Effects system
	if "Special" in subtypes:
		var provided = special_energy_effects.get_energy_types_provided(card_name)
		if provided.size() > 0:
			return provided
		# Fallback for truly unknown specials
		print("Warning: Unknown special energy card: ", card_name)
		return []
	
	return []

# Check energy requirements of any attack passed to it and return true if requirements are met
func check_attack_requirements(attack_dict: Dictionary, pokemon_card: card_object) -> bool:
	if pokemon_card == null:
		return false
	return cpu_ai.get_unmet_energy_count(attack_dict, pokemon_card) == 0

													######## Actual attacking functions ##########
													
# Checks if the defender has invincibility active (e.g. Agility)
func check_defender_invincible(defender: card_object, is_opponent: bool = false) -> bool:
	if not defender.is_invincible:
		return false
	var label_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
	show_floating_label("NO EFFECT", label_pos, Color.RED, true)
	print("INVINCIBLE: Attack fully blocked on ", defender.metadata["name"])
	return true

# Checks if the defender has a no-damage shield active
# Returns the adjusted damage (0 if shielded, otherwise the original value)
func apply_defender_no_damage_shield(defender: card_object, damage: int, is_opponent: bool = false) -> int:
	# NEO4 Pulse Guard (Light Jolteon): prevent incoming damage at or above threshold
	if defender.neo4_prevent_high_damage > 0 and damage >= defender.neo4_prevent_high_damage:
		var pg_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
		show_floating_label("PULSE GUARD", pg_pos, Color.BLUE, true)
		print("PULSE GUARD: prevented ", damage, " damage")
		return 0
	if not defender.has_no_damage:
		return damage
	var label_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
	show_floating_label("NO DAMAGE", label_pos, Color.BLUE, true)
	print("NO DAMAGE: Defender shield active, damage set to 0")
	return 0

# Checks if a specific attack is disabled on this pokemon
func is_attack_disabled(pokemon: card_object, attack_name: String) -> bool:
	return pokemon.disabled_attacks.has(attack_name)

# Resolves variable damage from attack text BEFORE weakness/resistance is applied.
# Handles: coin flip multipliers (×), does-nothing-on-tails, heads/tails bonus,
# per-energy bonus, per-damage-counter bonus/minus, per-bench bonus,
# half-HP damage, extra-energy-beyond-cost bonus, and condition-gated attacks.
# Returns: {"damage": int, "messages": Array, "flip_result": String, "attack_failed": bool}
func display_and_apply_attack_damage(attacker: card_object, defender: card_object, final_damage: int, modifiers: Array, is_opponent: bool, base_damage: int = -1) -> void:
	# Check Haunter's Transparency power before applying damage
	var transparency_blocked = await powers_and_bodies.check_transparency(defender)
	if transparency_blocked:
		return

	# Check Mew's Neutral Shield (basep-47): blocks all effects from Evolved Pokemon
	if attacker != null and powers_and_bodies.check_neutral_shield(defender, attacker):
		await show_message("NEUTRAL SHIELD! " + defender.metadata.get("name","").to_upper() + " IS PROTECTED FROM EVOLVED POKEMON!")
		if _should_bail(): return
		return

	# GYM1 Shadow Images (Rocket's Scyther): attacker flips a coin, tails = no damage. Lasts until damage gets through.
	if defender.dodge_active and final_damage > 0:
		await show_message(defender.metadata.get("name", "").to_upper() + "'S SHADOW IMAGES! FLIPPING...")
		var dodge_coin = await flip_coin(false, is_opponent)
		if not dodge_coin:
			var dodge_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
			show_floating_label("DODGED!", dodge_pos, Color.BLUE, true)
			print("SHADOW IMAGES: ", defender.metadata.get("name", ""), " dodged the attack")
			return
		defender.dodge_active = false
		update_status_icons(defender, !is_opponent)

	# NEO2 Slime (Wooper neo2-71): if defender has slime_active, attacker must flip; tails = no damage
	if defender.slime_active and final_damage > 0:
		defender.slime_active = false
		var slime_name = defender.metadata.get("name","").to_upper()
		await show_message(slime_name + "'S SLIME! " + ("OPPONENT" if is_opponent else "YOU") + " MUST FLIP!")
		var slime_coin = await flip_coin(false, is_opponent)
		if not slime_coin:
			show_floating_label("SLIMED!", Vector2(530 if is_opponent else 1030, 300), Color.GREEN, true)
			await show_message("TAILS! " + slime_name + " IS PROTECTED BY SLIME!")
			if _should_bail(): return
			return
		print("SLIME: tails would block but got heads — damage proceeds")

	# GYM2 Koga's Ninja Trick (gym2-115): defender's owner may switch this active with a benched pokemon before damage.
	if defender.gym2_koga_ninja_trick_attached:
		var defender_owner_is_opp = (defender == opponent_active_pokemon)
		var bench_for_swap = opponent_bench if defender_owner_is_opp else player_bench
		if bench_for_swap.size() > 0:
			var swapped = await trainer_effects.gym2_koga_ninja_trick_offer_switch(defender, defender_owner_is_opp)
			if swapped:
				# Damage now lands on the NEW active (the swapped-in pokemon). Re-resolve final_damage briefly:
				var new_defender = opponent_active_pokemon if defender_owner_is_opp else player_active_pokemon
				if new_defender != null:
					defender = new_defender
					var attacker_types_re = attacker.metadata.get("types", ["Colorless"]) if attacker != null else ["Colorless"]
					var redo = calculate_final_damage(base_damage if base_damage > 0 else final_damage, attacker_types_re, defender, attacker)
					final_damage = redo["damage"]
					modifiers = redo["modifiers"]

	# GYM1 Deflector (Erika's Exeggcute): halve incoming damage, rounded down to the nearest 10
	if defender.damage_halved_next_turn and final_damage > 0:
		final_damage = int(final_damage / 2.0 / 10.0) * 10
		print("DEFLECTOR: damage halved to ", final_damage)

	# NEO1 Screech (neo1-31/69): +20 damage from next attack received
	if defender.screech_damage_bonus > 0 and final_damage > 0:
		final_damage += defender.screech_damage_bonus
		print("SCREECH BONUS: +", defender.screech_damage_bonus, " damage, total ", final_damage)
		defender.screech_damage_bonus = 0

	# NEO1 Sprout Tower (neo1-97 Stadium): Colorless Pokemon attacks reduced by 30
	if final_damage > 0 and attacker != null:
		final_damage = powers_and_bodies.apply_sprout_tower_reduction(attacker, final_damage)

	# EX16 Psychic Protector (Flygon ex ex16-94): when damaged by an opponent's attack, the defender's
	# owner may discard up to 4 cards from hand to reduce this damage by 10 per card.
	if defender != null and final_damage > 0:
		final_damage = await powers_and_bodies.check_ex16_psychic_protector(defender, final_damage)

	# GYM1 Charity (gym1-99): the attacker's owner may reduce their own outgoing damage to spare the defender.
	# Player gets a YES/NO prompt only if the attack would KO; CPU never reduces.
	if attacker != null and attacker.gym1_charity_attached and final_damage > 0:
		final_damage = await trainer_effects.gym1_charity_choose_reduction(attacker, defender, final_damage, is_opponent)
		print("CHARITY: damage resolved to ", final_damage)

	# ISSUE #279: THE DAMAGE AND MULTIPLIER FIGURES ARE PLACED, NOT HARDCODED.
	#
	# Both were spawned at a fixed (530|1030, 300) - the pre-overhaul Active slots -
	# so they landed on top of whatever the board draws there now. float_label_over
	# reads the defender's real rect (#173), pushes the figure out to the side its
	# HP counters are on and draws it at half size (FLOAT_DAMAGE_FONT), which is
	# the whole of "in line with the HP counters instead of overlapping the card".
	# `is_opponent` here is the ATTACKER's side, so the DEFENDER is the other one.
	var defender_is_opponent: bool = not is_opponent
	print("ISSUE #279 FIX ACTIVE: damage label over ",
		defender.metadata.get("name", "?"), " defender_is_opponent=", defender_is_opponent,
		" nudge ", FLOAT_LABEL_SIDE_NUDGE, " font ", FLOAT_DAMAGE_FONT)
	for modifier in modifiers:
		var color_to_pass = Color.WHITE
		if "WEAKNESS" in modifier:
			color_to_pass = Color.GREEN
		elif "RESISTANCE" in modifier:
			color_to_pass = Color.RED
		else:
			color_to_pass = Color.WHITE
			
		float_label_over(defender, modifier, color_to_pass, defender_is_opponent)
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
	# Only show damage label if there is actual damage, or if the attack originally had damage
	# but it was reduced to 0 by resistance/other modifiers (not shields)
	var has_shield_modifier = "NO DAMAGE" in modifiers
	var show_damage_label = final_damage > 0 or (base_damage > 0 and modifiers.size() > 0 and not has_shield_modifier)
	if show_damage_label:
		float_label_over(defender, "-" + str(final_damage) + "HP", Color.WHITE, defender_is_opponent)
	defender.current_hp = max(0, defender.current_hp - final_damage)
	print(attacker.metadata["name"] + " dealt " + str(final_damage) + " damage to " + defender.metadata["name"] + "! HP remaining: " + str(defender.current_hp))
	display_hp_circles_above_align(defender, !is_opponent)
	
	if final_damage > 0:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
		await powers_and_bodies.dispatch_on_damage(defender, attacker, final_damage, !is_opponent)
		# [PERFORM] (neo4-58 Unown [P]): record damage taken while Active for next turn's Hidden Power bonus
		var def_is_opp = (defender == opponent_active_pokemon)
		if defender.has_ability("[Perform]") and defender == (opponent_active_pokemon if def_is_opp else player_active_pokemon):
			defender.perform_damage_stored = final_damage

	# GYM1-120 Vermilion City Gym: queued self-damage from Lt. Surge tails — apply to attacker after damage resolves
	if vermilion_lt_surge_self_damage_pending > 0 and attacker != null:
		# ISSUE #82 / ISSUE #60: PlusPower +10 each, Defender -20 each on this queued self-damage.
		var v_self_dmg = apply_self_damage_modifiers(attacker, vermilion_lt_surge_self_damage_pending)
		vermilion_lt_surge_self_damage_pending = 0
		if v_self_dmg > 0:
			var attacker_pos = Vector2(1030, 300) if is_opponent else Vector2(530, 300)
			show_floating_label("VERMILION -" + str(v_self_dmg) + "HP", attacker_pos, Color.RED, true)
			attacker.current_hp = max(0, attacker.current_hp - v_self_dmg)
			display_hp_circles_above_align(attacker, is_opponent)
			print("VERMILION GYM TAILS: ", attacker.metadata.get("name", ""), " took ", v_self_dmg, " self-damage")

# Parses the attack text for card effects and applies them
# pre_flip_result: if a coin was already flipped during damage resolution, pass "heads" or "tails" to skip re-flipping

# Applies damage from the chosen attack to the opponent's active pokemon and refreshes the HP display
func perform_attack(attack_index: int) -> void:
	if opponent_active_pokemon == null:
		print("Error: No opponent active pokemon to attack")
		return
	
	# Block player input immediately once attack is selected to prevent stray clicks
	opponent_blocker.visible = true
	
	var attacks = get_attacks_for_card(player_active_pokemon)
	var attack = attacks[attack_index]
	var attack_name = attack.get("name", "")
	
	# Check if attack is disabled (Farfetch'd, Amnesia)
	if is_attack_disabled(player_active_pokemon, attack_name):
		await show_message(attack_name.to_upper() + " IS DISABLED!")
		hide_attack_buttons()
		return
	
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_attack_sound)
	await show_message((player_active_pokemon.metadata["name"] + " USED " + attack_name).to_upper())

	# EX14 Holon Circle (ex14-79 Stadium): prevent all effects, including damage, done by either player's
	# Active Pokémon. The moment an Active uses an attack, that attack ends and Holon Circle is discarded.
	if is_stadium_in_play("ex14-79"):
		await show_message("HOLON CIRCLE! THE ATTACK HAD NO EFFECT!")
		await trainer_effects.remove_current_stadium("Holon Circle")
		player_attacked_this_turn = true
		hide_attack_buttons()
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
		player_end_turn_checks()
		return

	# Baby Pokemon rule: player must flip before attacking a Baby Pokemon (tails = turn ends)
	if await attack_effects.check_baby_rule(opponent_active_pokemon, false):
		hide_attack_buttons()
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
		player_end_turn_checks()
		return

	# SCARE (neo4-5 Dark Feraligatr): opponent's active Dark Feraligatr blocks Baby from attacking
	if "Baby" in player_active_pokemon.metadata.get("subtypes", []) and powers_and_bodies.is_scare_active(false):
		await show_message("SCARE! DARK FERALIGATR PREVENTS BABY POKÉMON FROM ATTACKING!")
		hide_attack_buttons()
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
		player_end_turn_checks()
		return

	# GYM2 Misty's Gyarados Rebellion — flip 2; both tails shuffles Gyarados into deck and cancels the attack
	if await powers_and_bodies.check_rebellion(player_active_pokemon, false):
		player_attacked_this_turn = true
		hide_attack_buttons()
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
		player_end_turn_checks()
		return

	# EX12 Pattern Distraction (Spinda ex12-26): if the opposing Active Spinda has this Body and the
	# attacker is a Basic Pokemon, flip a coin; tails cancels the attack.
	if await powers_and_bodies.check_ex12_pattern_distraction(player_active_pokemon, false):
		player_attacked_this_turn = true
		hide_attack_buttons()
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
		player_end_turn_checks()
		return

	# GYM1-120 Vermilion City Gym pre-attack flip (player). Optional flip for Lt. Surge attacker.
	await maybe_vermilion_lt_surge_flip(player_active_pokemon, false)

	# GYM2 pre-processing: attack-dict modifications before dispatch
	if player_active_pokemon.uid.begins_with("gym2-"):
		# Koga's Ditto Giant Growth boosts Pound's base damage to 30
		if player_active_pokemon.ditto_giant_growth and attack_name.to_lower() == "pound":
			attack = attack.duplicate()
			attack["damage"] = "30"
		# Lt. Surge's Rattata Focus Energy doubles Quick Attack's base damage
		if player_active_pokemon.gym2_focus_energy_active and attack_name.to_lower() == "quick attack":
			attack = attack.duplicate()
			attack["damage"] = str(attack_effects.parse_attack_base_damage(attack) * 2) + "+"
			player_active_pokemon.gym2_focus_energy_active = false
			await show_message("FOCUS ENERGY! QUICK ATTACK IS BOOSTED!")


	# Unified dispatch: handles GYM2 (name), GYM1, Base1-5 (text-pattern), and generic special attacks.
	# Returns true if fully handled (including post-attack cleanup); false falls through to generic path.
	# MATCH EFFECT: raw_damage_only — skip special dispatch so the attack falls through
	# to the generic printed-damage path with no card-text effects.
	if not match_effects.raw_damage_only(false):
		if await attack_effects.dispatch_attack(attack, player_active_pokemon, opponent_active_pokemon, false):
			return

	# Check attack_blocked flag (Tail Wag / Leer) - benching either pokemon ends this
	if player_active_pokemon.attack_blocked_next_turn:
		if opponent_active_pokemon.get_instance_id() == player_active_pokemon.attack_blocked_by_id:
			await show_message(player_active_pokemon.metadata["name"].to_upper() + " CAN'T ATTACK!")
			hide_attack_buttons()
			player_active_pokemon.attack_blocked_next_turn = false
			player_active_pokemon.attack_blocked_by_id = -1
			await get_tree().create_timer(GameState.match_time(0.5)).timeout
			player_end_turn_checks()
			return
		else:
			# Benching broke the effect
			player_active_pokemon.attack_blocked_next_turn = false
			player_active_pokemon.attack_blocked_by_id = -1

	# Coin-flip attack block (Sand-attack / Smokescreen): flip — tails = attack fails this turn
	if player_active_pokemon.attack_flip_blocked:
		player_active_pokemon.attack_flip_blocked = false
		var coin = await flip_coin(false, false)
		if not coin:
			await show_message(player_active_pokemon.metadata["name"].to_upper() + " CAN'T ATTACK! (SAND-ATTACK / SMOKESCREEN)")
			hide_attack_buttons()
			await get_tree().create_timer(GameState.match_time(0.5)).timeout
			player_end_turn_checks()
			return
		await show_message("HEADS! " + player_active_pokemon.metadata["name"].to_upper() + " CAN ATTACK!")
		if _should_bail(): return

	# Swords Dance: If active, boost Slash base damage (base Scyther = 60, ex8 Ninjask = 80)
	if player_active_pokemon.swords_dance_active and attack_name.to_lower() == "slash":
		var sd_dmg = player_active_pokemon.swords_dance_slash_damage if player_active_pokemon.swords_dance_slash_damage > 0 else 60
		attack = attack.duplicate()
		attack["damage"] = str(sd_dmg)
		player_active_pokemon.swords_dance_active = false
		player_active_pokemon.swords_dance_slash_damage = 0
		await show_message("SWORDS DANCE BOOST! SLASH DOES " + str(sd_dmg) + " DAMAGE!")

	# GYM1 Focus Energy (Rattata's Gnaw) / ECARD3 Focus Energy (Machoke's Mega Punch): if active,
	# double the boosted attack's base damage. Both share the gym1-style focus_energy_active flag
	# — only one of these two Pokemon lines can ever be Active at a time, so no collision.
	if player_active_pokemon.focus_energy_active and attack_name.to_lower() in ["gnaw", "mega punch"]:
		attack = attack.duplicate()
		var doubled = attack_effects.parse_attack_base_damage(attack) * 2
		attack["damage"] = str(doubled)
		player_active_pokemon.focus_energy_active = false
		await show_message("FOCUS ENERGY! " + attack_name.to_upper() + " DOES " + str(doubled) + " DAMAGE!")

	if await attack_effects.handle_attack_confusion(player_active_pokemon, false):
		hide_attack_buttons()
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
		player_end_turn_checks()
		return
	
	if await attack_effects.handle_attack_blind(player_active_pokemon, false):
		hide_attack_buttons()
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
		player_end_turn_checks()
		return
	
	# Resolve variable damage (coin flips, per-energy, per-counter, etc.) BEFORE weakness/resistance
	# MATCH EFFECT: raw_damage_only — flatten "20x"/"10+" to the printed number, no flips
	var variable_result
	if match_effects.raw_damage_only(false):
		variable_result = {"damage": attack_effects.parse_attack_base_damage(attack), "flip_result": "", "attack_failed": false, "messages": []}
	else:
		variable_result = await attack_effects.resolve_attack_variable_damage(attack, player_active_pokemon, opponent_active_pokemon, false)
	var resolved_base = variable_result["damage"]
	var flip_result = variable_result["flip_result"]
	
	if variable_result["attack_failed"]:
		for msg in variable_result["messages"]:
			await show_message(msg)
		hide_attack_buttons()
		# Still process non-damage effects (like Farfetch'd disable)
		var _pae_effects_failed = attack_effects.parse_card_text_effects(attack.get("text", ""), player_active_pokemon.metadata.get("name", ""))
		if _pae_effects_failed.size() > 0:
			await attack_effects.apply_card_text_effects(_pae_effects_failed, player_active_pokemon, opponent_active_pokemon, false, flip_result)
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
		player_end_turn_checks()
		return
	
	# Show variable damage messages
	for msg in variable_result["messages"]:
		await show_message(msg)
	
	var attacking_types = player_active_pokemon.metadata.get("types", ["Colorless"])
	var result = calculate_final_damage(resolved_base, attacking_types, opponent_active_pokemon, player_active_pokemon)
	var final_damage = result["damage"]
	
	if check_defender_invincible(opponent_active_pokemon, true):
		hide_attack_buttons()
		await get_tree().create_timer(GameState.match_time(0.5)).timeout
		player_end_turn_checks()
		return

	final_damage = apply_defender_no_damage_shield(opponent_active_pokemon, final_damage, true)

	await display_and_apply_attack_damage(player_active_pokemon, opponent_active_pokemon, final_damage, result["modifiers"], false, resolved_base)
	hide_attack_buttons()
	
	# Store last attack for Mirror Move tracking
	last_attack_on_opponent = {"damage": final_damage, "attack": attack, "attacker_types": attacking_types}
	player_attacked_this_turn = true
	
	# MATCH EFFECT: raw_damage_only — card-text effects are skipped entirely
	var _pae_effects = [] if match_effects.raw_damage_only(false) else attack_effects.parse_card_text_effects(attack.get("text", ""), player_active_pokemon.metadata.get("name", ""))

	# Clear one-shot attack boosts after any attack completes
	player_active_pokemon.clear_attack_boost_flags()
	if _pae_effects.size() > 0:
		await attack_effects.apply_card_text_effects(_pae_effects, player_active_pokemon, opponent_active_pokemon, false, flip_result)
	
	await check_all_knockouts()
	
	await get_tree().create_timer(GameState.match_time(0.5)).timeout
	player_end_turn_checks()
	
# Returns final damage and a list of modifiers applied, for display purposes
# is_self_damage: set by callers that are resolving damage a Pokemon deals to ITSELF (confusion under
# base-set rules runs the self-hit through Weakness/Resistance). Those callers finish with
# apply_self_damage_modifiers(), so the PlusPower and Defender blocks below must be skipped here or the
# same hit would be modified twice — with defending_pokemon == the attacker, Defender was silently
# applied in both places (ISSUE #82 / ISSUE #90).
func calculate_final_damage(base_damage: int, attacking_types: Array, defending_pokemon: card_object, attacker_pokemon: card_object = null, is_self_damage: bool = false) -> Dictionary:
	var damage = base_damage
	var modifiers_applied = []

	if defending_pokemon == null:
		return {"damage": damage, "modifiers": modifiers_applied}

	# ISSUE #73 FIX: an attack with no damage number at all (Snivel, Sing, Tail Wag, Whirlwind…) does
	# no damage, so Weakness and Resistance never apply to it — and their labels ("WEAKNESS ×2",
	# "RESISTANCE -30") must not pop up over the defender. This matches the TCG rule that
	# Weakness/Resistance are only applied when the attack actually does damage to the Defending
	# Pokemon. Every damage modifier further down this function is already gated on damage > 0, so
	# returning here changes nothing except suppressing the misleading labels.
	if base_damage <= 0:
		return {"damage": 0, "modifiers": modifiers_applied}

	# ECARD2/ECARD3 Crystal Type + Crystal Shard: if the attacker's own type is currently
	# overridden (temporary Crystal Type energy-attach, or permanent Crystal Shard Tool), use the
	# effective type for Weakness-triggering instead of whatever the caller happened to compute
	# from metadata — single centralized fix point rather than rewiring every execute_ function's
	# own "var types = attacker.metadata.get('types', ...)" line.
	if attacker_pokemon != null:
		var effective_types = attacker_pokemon.get_effective_types()
		if effective_types != attacker_pokemon.metadata.get("types", ["Colorless"]):
			attacking_types = effective_types

	# Apply weakness (check temporary override from Porygon Conversion 1 first)
	# GYM2-113 Cinnabar City Gym — Ignore Weakness when a Water Pokemon attacks a Blaine-named pokemon
	var skip_weakness = false
	if is_stadium_in_play(StadiumIds.CINNABAR_CITY_GYM) and attacker_pokemon != null:
		var def_name_cinnabar = defending_pokemon.metadata.get("name", "")
		if "Blaine" in def_name_cinnabar and "Water" in attacking_types:
			skip_weakness = true
			modifiers_applied.append("CINNABAR GYM (NO WEAKNESS)")
	# EX5 Ancient Tomb (ex5-87 Stadium): don't apply Weakness for all Pokemon in play (excluding
	# Pokemon-ex and Pokemon that has an owner in its name, e.g. "Brock's", "Rocket's").
	if not skip_weakness and is_stadium_in_play(StadiumIds.ANCIENT_TOMB):
		var def_name_tomb = defending_pokemon.metadata.get("name", "")
		if not is_ex_pokemon(defending_pokemon) and "'s" not in def_name_tomb:
			skip_weakness = true
			modifiers_applied.append("ANCIENT TOMB (NO WEAKNESS)")
	# MATCH EFFECT: ignore_weakness — side-aware for real attacks; for attacker-less calls
	# (CPU planning) only a both-sides rule applies, so planning never sees a one-sided rule
	if not skip_weakness:
		if attacker_pokemon != null:
			skip_weakness = match_effects.ignore_weakness(match_effects.is_card_on_opponent_side(attacker_pokemon))
		else:
			skip_weakness = match_effects.ignore_weakness_global()
	# EX7 Dragon Veil (Kingdra) / Dark Condition (Rocket's Entei ex): defender has no Weakness.
	if not skip_weakness and powers_and_bodies.has_no_weakness_body(defending_pokemon):
		skip_weakness = true
		modifiers_applied.append("NO WEAKNESS (BODY)")
	if not skip_weakness:
		var weaknesses = defending_pokemon.metadata.get("weaknesses", [])
		for weakness in weaknesses:
			var weakness_type = weakness["type"]
			# If Conversion 1 changed this pokemon's weakness, use the override
			if defending_pokemon.temporary_weakness != "":
				weakness_type = defending_pokemon.temporary_weakness
			# EX9 Dark Hole (Dusclops ex ex9-94 on your Bench): don't apply Darkness Weakness for your Pokemon.
			if weakness_type == "Darkness" and powers_and_bodies.ex9_ignores_darkness_weakness(defending_pokemon):
				modifiers_applied.append("DARK HOLE (NO DARKNESS WEAKNESS)")
				continue
			if weakness_type in attacking_types:
				var value = weakness["value"]
				if "×" in value:
					var multiplier = int(value.replace("×", "").strip_edges())
					damage = damage * multiplier
					modifiers_applied.append("WEAKNESS " + value)
				elif "+" in value:
					damage = damage + int(value.replace("+", "").strip_edges())
					modifiers_applied.append("WEAKNESS " + value)
	
	# Apply resistance (check temporary override from Porygon Conversion 2 first)
	# GYM1-115 Pewter City Gym — Pokemon with "Brock" in name ignore Resistance on their attacks
	var skip_resistance = false
	if is_stadium_in_play(StadiumIds.PEWTER_CITY_GYM) and attacker_pokemon != null:
		var atk_name_pewter = attacker_pokemon.metadata.get("name", "")
		if "Brock" in atk_name_pewter:
			skip_resistance = true
			modifiers_applied.append("PEWTER GYM (NO RESISTANCE)")
	# EX1 Withering Dust (Beautifly): while Beautifly is in play on either side, do not apply
	# Resistance for all Active Pokemon.
	if not skip_resistance and powers_and_bodies.is_ex1_withering_dust_in_play():
		skip_resistance = true
		modifiers_applied.append("WITHERING DUST (NO RESISTANCE)")
	# EX11 Holon Energy FF + basic Fighting attached: the holder's attacks aren't affected by Resistance.
	if not skip_resistance and attacker_pokemon != null and special_energy_effects.ex11_holon_ff_ignore_resistance(attacker_pokemon):
		skip_resistance = true
		modifiers_applied.append("HOLON ENERGY FF (NO RESISTANCE)")
	# EX12 Ancient Tentacles (Omanyte ex12-60): damage done by your Omanyte, Omastar, Kabuto, Kabutops,
	# or Kabutops ex isn't affected by Resistance while an Omanyte with this Body is in play on that side.
	if not skip_resistance and attacker_pokemon != null and powers_and_bodies.is_ex12_ancient_tentacles_active(attacker_pokemon):
		skip_resistance = true
		modifiers_applied.append("ANCIENT TENTACLES (NO RESISTANCE)")
	# EX5 Magnetic Storm (ex5-91 Stadium): Psychic/Fighting attacks are not affected by Resistance.
	if not skip_resistance and is_stadium_in_play(StadiumIds.MAGNETIC_STORM):
		if "Psychic" in attacking_types or "Fighting" in attacking_types:
			skip_resistance = true
			modifiers_applied.append("MAGNETIC STORM (NO RESISTANCE)")
	# EX8 Tropical Motion (Tropius): while Tropius is your Active, your opponent's Active has no Resistance.
	if not skip_resistance and attacker_pokemon != null and powers_and_bodies.is_ex8_tropical_motion_active(attacker_pokemon):
		skip_resistance = true
		modifiers_applied.append("TROPICAL MOTION (NO RESISTANCE)")
	# MATCH EFFECT: ignore_resistance — same side-awareness rules as ignore_weakness above
	if not skip_resistance:
		if attacker_pokemon != null:
			skip_resistance = match_effects.ignore_resistance(match_effects.is_card_on_opponent_side(attacker_pokemon))
		else:
			skip_resistance = match_effects.ignore_resistance_global()
	if not skip_resistance:
		var resistances = defending_pokemon.metadata.get("resistances", [])
		# GYM2-109 Resistance Gym — each pokemon's Resistance is reduced by 20 (e.g. -30 -> -10, -20 -> 0)
		# ECARD2 Enervating Pollen (Gloom): while any Gloom is in play, each Active Pokemon's
		# Resistance only reduces damage by 10 (same math as Resistance Gym — defending_pokemon
		# here is always an Active, since bench damage bypasses this weakness/resistance path)
		var resistance_reduction = 20 if (is_stadium_in_play(StadiumIds.RESISTANCE_GYM) or powers_and_bodies.is_enervating_pollen_active()) else 0
		for resistance in resistances:
			var resistance_type = resistance["type"]
			if defending_pokemon.temporary_resistance != "":
				resistance_type = defending_pokemon.temporary_resistance
			if resistance_type in attacking_types:
				var value = int(resistance["value"])
				if resistance_reduction > 0:
					# Resistance values are negative (e.g. -30). Reducing means adding +20 capped at 0.
					value = min(0, value + resistance_reduction)
				if value < 0:
					damage = max(0, damage + value)
					modifiers_applied.append("RESISTANCE " + str(value))
				else:
					modifiers_applied.append("RESISTANCE NULLIFIED")
	
	# NEO2 Unown type reductions: [D] Darkness, [M] Metal, [N] Colorless — -30 from specific type
	if damage > 0 and attacker_pokemon != null:
		damage = powers_and_bodies.apply_unown_type_reductions(attacker_pokemon, defending_pokemon, damage, modifiers_applied)

	# Apply shielded damage threshold (Onix Harden)
	# If the damage after weakness/resistance is AT OR BELOW the threshold, prevent it entirely
	if defending_pokemon.shielded_damage_threshold > 0 and damage > 0:
		if damage <= defending_pokemon.shielded_damage_threshold:
			modifiers_applied.append("NO DAMAGE")
			damage = 0
	
	# Mr. Mime Invisible Wall: if damage >= 30 after W/R, prevent it entirely
	# This is a passive Pokemon Power check (not a stored property)
	if damage >= 30:
		var defender_abilities = defending_pokemon.metadata.get("abilities", [])
		for ability in defender_abilities:
			if ability.get("name", "") == "Invisible Wall":
				if defending_pokemon.special_condition not in ["Paralyzed", "Asleep", "Confused"] and not defending_pokemon.is_poisoned and not powers_and_bodies.is_toxic_gas_active():
					modifiers_applied.append("INVISIBLE WALL")
					damage = 0
					break
	
	# Apply damage reduction from Minimize / Pounce / Snivel
	if damage > 0 and defending_pokemon.damage_reduction_next_turn > 0:
		var reduction = min(damage, defending_pokemon.damage_reduction_next_turn)
		damage -= reduction
		modifiers_applied.append("REDUCED -" + str(reduction))
	
	# Dark Primeape Frenzy: +30 damage when confused
	if attacker_pokemon != null:
		var frenzy_bonus = powers_and_bodies.check_frenzy_bonus(attacker_pokemon)
		if frenzy_bonus > 0:
			damage += frenzy_bonus
			modifiers_applied.append("FRENZY +" + str(frenzy_bonus))
	# NP Frenzy (Kyogre/Groudon/Rayquaza ex): +40 damage if specific legendary on opponent's side
	if attacker_pokemon != null:
		var is_atk_opp = (attacker_pokemon == opponent_active_pokemon or attacker_pokemon in opponent_bench)
		var np_frenzy = powers_and_bodies.get_np_frenzy_bonus(attacker_pokemon, is_atk_opp)
		if np_frenzy > 0:
			damage += np_frenzy
			modifiers_applied.append("FRENZY +" + str(np_frenzy))
	
	# Apply PlusPower bonus (+10 per PlusPower attached to the attacker)
	# PlusPower is applied AFTER weakness/resistance per original TCG rules
	if damage > 0 and not is_self_damage and attacker_pokemon != null and attacker_pokemon.pluspower_count > 0:
		var pp_bonus = attacker_pokemon.pluspower_count * 10
		damage += pp_bonus
		modifiers_applied.append("PLUSPOWER +" + str(pp_bonus))

	# Registered damage-modifier hooks (passive bodies, attached tools — see Powers_And_Bodies_Effects)
	damage = powers_and_bodies.run_damage_modifier_hooks(damage, attacker_pokemon, defending_pokemon, modifiers_applied)

	# GYM1 Misty (gym1-18/102): +20 to next damage attack by an attacker whose name contains "Misty"
	# Boost is owned by whichever side played the card and applies once; consumed here.
	if damage > 0 and attacker_pokemon != null:
		var attacker_owner_is_opp = (attacker_pokemon == opponent_active_pokemon)
		var boost_on = (opponent_misty_boost_active if attacker_owner_is_opp else player_misty_boost_active)
		var attacker_name = attacker_pokemon.metadata.get("name", "")
		if boost_on and "Misty" in attacker_name:
			damage += 20
			modifiers_applied.append("MISTY +20")
			if attacker_owner_is_opp:
				opponent_misty_boost_active = false
			else:
				player_misty_boost_active = false

	# GYM1-120 Vermilion City Gym — one-shot bonus damage from Lt. Surge attacker coin flip (set by pre-attack hook)
	if damage > 0 and vermilion_lt_surge_bonus_damage > 0:
		damage += vermilion_lt_surge_bonus_damage
		modifiers_applied.append("VERMILION +" + str(vermilion_lt_surge_bonus_damage))
		vermilion_lt_surge_bonus_damage = 0
	
	# Apply Defender reduction (-20 damage per Defender attached to the defending pokemon)
	if damage > 0 and not is_self_damage:
		var reduction = get_defender_reduction(defending_pokemon, damage)
		if reduction > 0:
			damage -= reduction
			modifiers_applied.append("DEFENDER -" + str(reduction))
			print("ISSUE #60 FIX ACTIVE: Defender reduced attack damage by ", reduction, " on ", defending_pokemon.metadata.get("name", ""))

	# Apply Kabuto Armor (halve damage, rounded down to nearest 10)
	if damage > 0:
		damage = powers_and_bodies.apply_kabuto_armor(defending_pokemon, damage)

	# GYM1 Misty's Cloyster Shell Armor — -10 damage taken
	if damage > 0:
		var pre_shell = damage
		damage = powers_and_bodies.apply_shell_armor(defending_pokemon, damage)
		if damage < pre_shell:
			modifiers_applied.append("SHELL ARMOR -10")

	# GYM1 Erika's Dratini Strange Barrier — cap damage from a Basic attacker at 10 when ≥20
	if damage >= 20 and attacker_pokemon != null:
		var pre_barrier = damage
		damage = powers_and_bodies.apply_strange_barrier(defending_pokemon, attacker_pokemon, damage)
		if damage < pre_barrier:
			modifiers_applied.append("STRANGE BARRIER -> 10")

	# GYM2 Erika's Ivysaur Relaxing Scent — while Ivysaur is Active anywhere, damage is halved (round up to nearest 10)
	if damage > 0:
		var pre_scent = damage
		damage = powers_and_bodies.apply_relaxing_scent(damage)
		if damage < pre_scent:
			modifiers_applied.append("RELAXING SCENT (halved)")

	# MATCH EFFECTS: flat damage rules. Bonuses only apply to real attacks (attacker known,
	# not hitting itself) so CPU planning calls and self/recoil damage are unaffected.
	if damage > 0 and attacker_pokemon != null and defending_pokemon != attacker_pokemon:
		var rule_bonus = match_effects.attack_damage_bonus(attacker_pokemon, match_effects.is_card_on_opponent_side(attacker_pokemon))
		if rule_bonus > 0:
			damage += rule_bonus
			modifiers_applied.append("RULE +" + str(rule_bonus))

	# MATCH EFFECT: type_damage_reduction — defender-keyed, so it also applies to
	# attacker-less planning calls (the CPU correctly values it when choosing attacks)
	if damage > 0:
		var rule_reduction = match_effects.damage_reduction_for(defending_pokemon, match_effects.is_card_on_opponent_side(defending_pokemon))
		if rule_reduction > 0:
			var applied_reduction = min(damage, rule_reduction)
			damage -= applied_reduction
			modifiers_applied.append("RULE -" + str(applied_reduction))

	# MATCH EFFECT: zero_attack_damage — applied LAST, wins over every bonus above
	if damage > 0 and attacker_pokemon != null and defending_pokemon != attacker_pokemon:
		if match_effects.zero_attack_damage(match_effects.is_card_on_opponent_side(attacker_pokemon)):
			damage = 0
			modifiers_applied.append("ZERO DAMAGE RULE")

	# NEO3 Hard Shell (Shuckle neo3-51): if damage is <= 40, reduce to 10
	if damage > 0 and defending_pokemon != null and attacker_pokemon != defending_pokemon:
		damage = powers_and_bodies.apply_hard_shell(defending_pokemon, damage, modifiers_applied)

	return {"damage": damage, "modifiers": modifiers_applied}

# ISSUE #60: Defender prevents ALL damage to the Pokemon it is attached to — direct attacks,
# attack effects (bench damage, snipes), confusion self-damage and self-damaging attacks alike —
# reducing each hit by 20 per Defender attached. It does NOT prevent poison damage or the damage
# from attaching a Rainbow/special energy (those callers simply don't route through here).
# Returns the total reduction (capped at `damage`) for a Pokemon carrying one or more Defenders.
func get_defender_reduction(pokemon: card_object, damage: int) -> int:
	if pokemon == null or damage <= 0:
		return 0
	if pokemon.defender_count <= 0 or pokemon.defender_turns_remaining < 0:
		return 0
	return min(damage, 20 * pokemon.defender_count)

# ISSUE #82: PlusPower now behaves as the mirror image of Defender — where Defender reduces EVERY hit
# a Pokemon takes (including damage it does to itself), PlusPower raises every amount of damage the
# Pokemon it is attached to deals, self-damage included: +10 per PlusPower attached.
#
# THE ONE PLACE self-damage modifiers are applied. Every self-damage path (confusion coin-flip,
# generic "does N damage to itself" attack text, gym2_self_damage — the shared helper behind dozens of
# recoil attacks — raw recoil loops, and the confused-retreat penalty) routes through here so
# PlusPower and Defender can never drift apart or be applied twice on the same hit.
# Order matches the attack path: bonuses first, then Defender reduction, floored at 0.
func apply_self_damage_modifiers(pokemon: card_object, damage: int) -> int:
	if pokemon == null or damage <= 0:
		return max(0, damage)
	var original = damage
	if pokemon.pluspower_count > 0:
		damage += pokemon.pluspower_count * 10
	var reduction = get_defender_reduction(pokemon, damage)
	damage = max(0, damage - reduction)
	if damage != original:
		print("ISSUE #82 FIX ACTIVE: self-damage on ", pokemon.metadata.get("name", ""), " ", original, " -> ", damage,
			" (PlusPower x", pokemon.pluspower_count, " +", pokemon.pluspower_count * 10, ", Defender -", reduction, ")")
	return damage

############################################################# Knockout functions ##################################################################
													
# Checks a single Pokemon's HP and if zero or below, animates KO and discards it
func check_and_handle_knockout(pokemon: card_object, is_opponent: bool) -> bool:
	if pokemon == null or pokemon.current_hp > 0:
		return false

	# GYM2 Giovanni's Machamp Fortitude — flip to survive with 10 HP
	if await powers_and_bodies.check_fortitude(pokemon):
		return false

	# NEO1 Endure (neo1-43 Phanpy): survive KO with 10 HP if endure_active flag is set
	if pokemon.endure_active and pokemon.current_hp <= 0:
		pokemon.endure_active = false
		pokemon.current_hp = 10
		display_hp_circles_above_align(pokemon, is_opponent)
		await show_message("ENDURE! " + pokemon.metadata.get("name","").to_upper() + " SURVIVED WITH 10 HP!")
		if _should_bail(): return false
		return false

	# NEO3 Time Travel (Celebi neo3-3): if KO'd by attack, flip — heads: survive by shuffling Celebi back into deck
	if await powers_and_bodies.check_time_travel(pokemon, is_opponent):
		return false

	# NEO1 Focus Band (neo1-86 Tool): flip — heads survive with 10 HP
	if await powers_and_bodies.check_focus_band(pokemon, is_opponent):
		return false

	# EX7 Buffer (Hoppip/Skiploom/Jumpluff): flip — heads survive with 10 HP
	if await powers_and_bodies.check_ex7_buffer(pokemon, is_opponent):
		return false

	var ko_name = pokemon.metadata.get("name", "Unknown")
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var discard_node = opponent_discard_icon if is_opponent else player_discard_icon
	var active_container = opponent_active_container if is_opponent else player_active_container

	# Save destiny bond flag BEFORE send_card_to_discard clears it
	var had_destiny_bond = pokemon.has_destiny_bond

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_knockout_sound)
	await show_message(ko_name.to_upper() + " WAS KNOCKED OUT!")

	# Pre-KO event hooks (Final Beam and any future on-KO powers registered in Powers)
	var ko_attacker = player_active_pokemon if is_opponent else opponent_active_pokemon
	await powers_and_bodies.dispatch_pre_ko(pokemon, ko_attacker, is_opponent)

	# EX14 Time Travel (Celebi Star ex14-100): if it would be KO'd by an opponent's attack, flip; on heads
	# it is not KO'd — discard everything attached and put it on the bottom of the deck (no prize taken).
	if await powers_and_bodies.check_ex14_time_travel(pokemon, ko_attacker, is_opponent):
		if pokemon == active:
			if is_opponent:
				opponent_active_pokemon = null
			else:
				player_active_pokemon = null
		elif pokemon in bench:
			bench.erase(pokemon)
		var status_container_tt = opponent_status_container if is_opponent else player_status_container
		for child in status_container_tt.get_children():
			child.queue_free()
		display_pokemon(is_opponent)
		cpu_ai.invalidate_cpu_evaluation()
		return true

	# GYM1 Rocket's Moltres Rebirth — return to hand instead of discarding
	# Must trigger AFTER Final Beam (so Final Beam still resolves) but BEFORE the discard animation.
	if await powers_and_bodies.check_rebirth(pokemon, is_opponent):
		# Clean up board state same as KO but route to hand
		if pokemon == active:
			if is_opponent:
				opponent_active_pokemon = null
			else:
				player_active_pokemon = null
		elif pokemon in bench:
			bench.erase(pokemon)
		var status_container_rb = opponent_status_container if is_opponent else player_status_container
		for child in status_container_rb.get_children():
			child.queue_free()
		display_pokemon(is_opponent)
		cpu_ai.invalidate_cpu_evaluation()
		return true
	
	# ISSUE #285: THE KNOCKOUT IS FOUR BEATS, IN THIS ORDER.
	#
	#   1. every attached Energy disappears from the stack and flies to the discard,
	#      one at a time, each from its OWN card (ISSUE #280);
	#   2. only once the last one has LANDED does the Pokemon itself go;
	#   3. the Active slot is hidden, so the card is gone from the board before the
	#      ghost leaves rather than sitting under it;
	#   4. the ghost flies from the card's EXACT rect and tweens down to the discard
	#      pile's size on the way.
	#
	# Beat 4 is what was actually broken. The flight was sized from card_scales[10]
	# - a size the board has not drawn since the overhaul - so a 265x367 Active
	# "left" as a small card that appeared from nowhere. The rect is measured off
	# the real node now, before anything hides it.
	var pokemon_texture = get_card_texture(pokemon)
	var ko_rect := _card_rect_now(pokemon)
	if ko_rect.is_empty():
		var loc := get_pokemon_screen_location(pokemon)
		ko_rect = {
			"position": loc.get("position", active_container.global_position),
			"size": loc.get("size", ACTIVE_CARD),
		}
	
	# Beat 1 + 2: awaited, so nothing below starts until the stack is empty.
	if pokemon.attached_energies.size() > 0:
		await animate_energies_to_discard(pokemon.attached_energies.duplicate(), pokemon, is_opponent)
		display_active_pokemon_energies(is_opponent)
	
	# Beat 3. ISSUE #87: when it is the ACTIVE being knocked out, hide its slot
	# (card + HP squares + status + action rows) before the card flies to the
	# discard, so nothing is left describing a Pokemon that has gone. They come back
	# with the replacement via display_hp_circles_above_align.
	if pokemon == active:
		set_active_slot_visible(is_opponent, false)
	else:
		# A benched Pokemon has no slot toggle, so take it out of the bench row and
		# redraw before the ghost leaves - same "gone before it moves" reading.
		bench.erase(pokemon)
		display_pokemon(is_opponent)

	# Beat 4. _anim_dest_size resolves the discard pile to PILE_SIZE, so the ghost
	# shrinks from the card's real size to the pile's over the flight.
	print("ISSUE #285 FIX ACTIVE: KO ghost leaves ", ko_rect["position"],
		" at ", ko_rect["size"], " -> discard pile at ", PILE_SIZE)
	await animate_card_a_to_b(discard_node, discard_node, 0.3, pokemon_texture,
		ko_rect["size"], Vector2.ZERO, _ANIM_POS_SENTINEL, false, ko_rect["position"])


	if pokemon == active:
		if is_opponent:
			opponent_active_pokemon = null
		else:
			player_active_pokemon = null
	elif pokemon in bench:
		bench.erase(pokemon)
	
	# Clear status icons for KO'd pokemon
	var status_container = opponent_status_container if is_opponent else player_status_container
	for child in status_container.get_children():
		child.queue_free()
	
	display_pokemon(is_opponent)
	
	# Now do the actual array manipulation
	send_card_to_discard(pokemon, is_opponent)

	# EX15 Holon Veil: a KO (e.g. Ampharos δ leaving play) may collapse the board-wide δ grant.
	powers_and_bodies.refresh_holon_veil()

	# Fix 2: Invalidate CPU evaluation cache after board state change
	cpu_ai.invalidate_cpu_evaluation()
	
	await get_tree().create_timer(GameState.match_time(0.3)).timeout
	display_hp_circles_above_align(active if pokemon != active else null, is_opponent)
	
	# DESTINY BOND: If the KO'd pokemon had destiny bond active, knock out the opposing active
	if had_destiny_bond:
		var opposing_active = player_active_pokemon if is_opponent else opponent_active_pokemon
		if opposing_active != null and opposing_active.current_hp > 0:
			await show_message(ko_name.to_upper() + "'S DESTINY BOND TOOK " + opposing_active.metadata["name"].to_upper() + " DOWN WITH IT!")
			opposing_active.current_hp = 0
			# Update HP circles to show all red
			display_hp_circles_above_align(opposing_active, !is_opponent)
			print("DESTINY BOND: ", opposing_active.metadata["name"], " knocked out by destiny bond")
	
	return true

# Scans all Pokemon on the field for both players, handles each KO, and returns a summary of what was knocked out
func check_all_knockouts() -> Dictionary:
	var results = {"player_kos": 0, "opponent_kos": 0}
	# Track KOs that should award prizes separately from bench token KOs
	var opponent_prize_kos = 0
	var player_prize_kos = 0
	
	var player_to_check = []
	if player_active_pokemon != null:
		player_to_check.append(player_active_pokemon)
	player_to_check.append_array(player_bench.duplicate())
	
	var opponent_to_check = []
	if opponent_active_pokemon != null:
		opponent_to_check.append(opponent_active_pokemon)
	opponent_to_check.append_array(opponent_bench.duplicate())
	
	for pokemon in opponent_to_check:
		# EX8 Empty Shell (Shedinja): when this Pokemon is Knocked Out, the opponent takes no Prizes.
		var should_award_prize = not pokemon.no_prize_on_ko and not pokemon.has_ability("Empty Shell")
		var prizes_for_this_ko = 2 if is_ex_pokemon(pokemon) else 1
		if await check_and_handle_knockout(pokemon, true):
			results["opponent_kos"] += 1
			if should_award_prize:
				opponent_prize_kos += prizes_for_this_ko

	for pokemon in player_to_check:
		# EX8 Empty Shell (Shedinja): when this Pokemon is Knocked Out, the opponent takes no Prizes.
		var should_award_prize = not pokemon.no_prize_on_ko and not pokemon.has_ability("Empty Shell")
		var prizes_for_this_ko = 2 if is_ex_pokemon(pokemon) else 1
		if await check_and_handle_knockout(pokemon, false):
			results["player_kos"] += 1
			if should_award_prize:
				player_prize_kos += prizes_for_this_ko
			
	# MATCH EFFECT: double_prizes — multiply prize-awarding KOs (after the no_prize_on_ko
	# filter, so bench tokens still award nothing). Existing size() guards handle overflow.
	for i in range(opponent_prize_kos * match_effects.prizes_per_ko(false)):
		if player_prize_cards.size() > 0:
			opponent_blocker.visible = false
			await player_pick_prize_card()
			await prize_card_taken
			opponent_blocker.visible = true

	# Opponent takes prizes for player KOs
	for i in range(player_prize_kos * match_effects.prizes_per_ko(true)):
		if opponent_prize_cards.size() > 0:
			await cpu_ai.opponent_take_prize_card()
	
	# ISSUE #61: if BOTH players took their last prize card from this same KO exchange, it's a draw —
	# and by house rules a draw is a loss for the player. Checked before the single-side prize checks.
	if player_prize_cards.size() == 0 and opponent_prize_cards.size() == 0 and (player_prize_kos > 0 or opponent_prize_kos > 0):
		print("ISSUE #61 FIX ACTIVE: both players took their last prize simultaneously — draw")
		game_end_logic(true, true)
		return results

	# ISSUE #47 FIX: check the last-prize win condition BEFORE promoting a new Active. If the KO that
	# just happened took the final prize card the game is already over, so there's no point switching
	# in a new Active Pokémon (and showing "X set Y as their active") only to immediately declare the
	# winner. Win-by-last-prize is resolved here and returns straight away.
	if player_prize_cards.size() == 0 and opponent_prize_kos > 0:
		await show_message("YOU TOOK YOUR LAST PRIZE CARD!")
		game_end_logic(false)  # false = opponent loses
		return results
	if opponent_prize_cards.size() == 0 and player_prize_kos > 0:
		await show_message("OPPONENT TOOK THEIR LAST PRIZE CARD!")
		game_end_logic(true)  # true = player loses
		return results

	# ISSUE #61: if both Active Pokémon were KO'd this exchange and NEITHER side can promote a new
	# Active (both benches empty), it's a draw — a loss for the player under house rules. Checked
	# before promotion so it isn't mis-resolved as a one-sided loss by handle_post_knockout.
	if player_active_pokemon == null and opponent_active_pokemon == null and player_bench.size() == 0 and opponent_bench.size() == 0:
		print("ISSUE #61 FIX ACTIVE: both Actives KO'd, neither can promote — draw")
		game_end_logic(true, true)
		return results

	if results["opponent_kos"] > 0:
		await handle_post_knockout(true)
	if _should_bail():
		return results

	if results["player_kos"] > 0:
		await handle_post_knockout(false)
	if _should_bail():
		return results
	
	# Check win condition: all prize cards taken
	if player_prize_cards.size() == 0 and opponent_prize_kos > 0:
		await show_message("YOU TOOK YOUR LAST PRIZE CARD!")
		game_end_logic(false)  # false = opponent loses
		return results
	if opponent_prize_cards.size() == 0 and player_prize_kos > 0:
		await show_message("OPPONENT TOOK THEIR LAST PRIZE CARD!")
		game_end_logic(true)  # true = player loses
		return results

	return results

# After KOs are processed, animates a bench Pokemon moving to the active spot or ends the game
func handle_post_knockout(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var active_container = opponent_active_container if is_opponent else player_active_container
	var bench_container = opponent_bench_container if is_opponent else player_bench_container
	
	if active != null:
		return
	
	if bench.size() == 0:
		await show_message("NO POKEMON REMAINING!")
		game_end_logic(not is_opponent)
		return
	
	if is_opponent:
		var cpu_eval = cpu_ai.get_cpu_evaluation()
		var new_active = cpu_ai.pick_best_bench_replacement(opponent_bench, player_active_pokemon, cpu_eval)
		if new_active == null:
			new_active = bench[0]

		# ISSUE #276: the slot the card is LEAVING, measured before the bench redraws.
		var repl_from := _card_rect_now(new_active)
		bench.erase(new_active)
		display_pokemon(true)
		var new_texture = get_card_texture(new_active)

		# ISSUE #276: THE CARD GREW TO A SIZE THE BOARD NO LONGER DRAWS.
		#
		# This flight ended at card_scales[3.5] - 405x557, the PRE-OVERHAUL Active
		# size - while the Active slot is ACTIVE_CARD (265x367). So the replacement
		# ballooned to half again the right size in mid-air and then snapped down
		# the moment display_pokemon redrew it, which is the report exactly. It
		# started from card_scales[9] rather than BENCH_CARD for the same reason,
		# and aimed at the CONTAINER's centre instead of the slot.
		# The same trap #236/#241/#242 fixed everywhere else; this call was missed.
		print("ISSUE #276 FIX ACTIVE: bench -> active ",
			repl_from.get("size", BENCH_CARD), " -> ", ACTIVE_CARD,
			" (was card_scales[9] -> card_scales[3.5] = 405x557)")
		await animate_card_a_to_b(bench_container, active_container, 0.3, new_texture,
			repl_from.get("size", BENCH_CARD), ACTIVE_CARD,
			active_container.global_position, false,
			repl_from.get("position", _ANIM_POS_SENTINEL))

		new_active.current_location = "active"
		opponent_active_pokemon = new_active
		display_pokemon(true)
		# ISSUE #87: the slot was hidden for the knockout animation — reveal it now the replacement has
		# landed, so the new card AND its HP squares appear together.
		set_active_slot_visible(true, true)
		display_active_pokemon_energies(true)
		display_active_pokemon_energies(false)
		await show_message("OPPONENT SET " + new_active.metadata["name"].to_upper() + " AS THEIR ACTIVE POKEMON!")
		# Fix 2: Invalidate CPU evaluation cache after replacement
		cpu_ai.invalidate_cpu_evaluation()
		# NEO2 Spikes (Forretress): 10 damage to new opponent active
		await powers_and_bodies.check_spikes(new_active, true)
		if _should_bail(): return
		await check_all_knockouts()
		if _should_bail(): return
	else:
		knockout_bench_selection_active = true
		show_enlarged_array_selection_mode(player_bench)
		cancel_button.visible = false
		header_label.text = "YOUR ACTIVE POKEMON WAS KNOCKED OUT"
		hint_label.text = "Choose a bench Pokemon to set as your new active"
		action_button.text = "SELECT POKEMON"
		action_button.disabled = true
		opponent_blocker.visible = false
		action_button.theme = theme_disabled
		await knockout_replacement_chosen
		display_active_pokemon_energies(false)
		display_active_pokemon_energies(true)
		opponent_blocker.visible = true
	
	# Update Ditto Transform after new active is set
	powers_and_bodies.update_ditto_transform(is_opponent)
	powers_and_bodies.update_ditto_transform(not is_opponent)
	
########################################################## END ATTACK AND DAMAGE FUNCTIONS ###########################################################
######################################################################################################################################################
#
#         ########  ########  #######  ########  #######  ########
#         ##        ##        ##       ##        ##          ##
#         ########  ########  #######  ########  ##          ##
#         ##        ##        ##       ##        ##          ##
#         ########  ##        ##       ########  #######     ##
#

######################################################################################################################################################
############################################################# EFFECT PARSING FUNCTIONS ###############################################################

################################################################## Effect helpers ####################################################################
															
# Looks backwards from an effect's position to find the nearest coin flip condition
func apply_status_effect(effect: Dictionary, attacker: card_object, defender: card_object, is_opponent_attacking: bool) -> void:
	var target_pokemon: card_object
	var is_target_opponent: bool
	if effect["target"] == "defender":
		target_pokemon = defender
		is_target_opponent = !is_opponent_attacking
	else:
		target_pokemon = attacker
		is_target_opponent = is_opponent_attacking

	# Bench tokens cannot be affected by status conditions
	if target_pokemon.is_bench_token:
		print("STATUS BLOCKED: ", target_pokemon.metadata.get("name", ""), " is a bench token - immune to status")
		return

	# MATCH EFFECT: no_status_effects — special conditions cannot be applied
	if match_effects.status_blocked(is_target_opponent):
		await show_message("SPECIAL MATCH RULE: STATUS EFFECTS CANNOT BE APPLIED!")
		return

	# Snorlax Thick Skinned: can't become Asleep, Confused, Paralyzed, or Poisoned
	# Blocked by Muk's Toxic Gas (it's a Pokemon Power)
	var target_abilities = target_pokemon.metadata.get("abilities", [])
	for _ab in target_abilities:
		if _ab.get("name", "") == "Thick Skinned":
			if target_pokemon.special_condition not in ["Asleep", "Confused", "Paralyzed"] and not powers_and_bodies.is_toxic_gas_active():
				await show_message(target_pokemon.metadata.get("name", "").to_upper() + "'S THICK SKINNED PREVENTS STATUS!")
				print("STATUS BLOCKED: Thick Skinned prevents status on ", target_pokemon.metadata.get("name", ""))
				return

	var status = effect["status"]
	var mutually_exclusive = ["Paralyzed", "Asleep", "Confused"]

	if status in mutually_exclusive:
		target_pokemon.special_condition = status
	if status == "Poisoned":
		target_pokemon.is_poisoned = true
		target_pokemon.poison_damage = 10
	if status == "Burned":
		target_pokemon.is_burned = true

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_status_sound)
	await show_message(target_pokemon.metadata["name"].to_upper() + " IS NOW " + status.to_upper() + "!")
	print("STATUS APPLIED: ", target_pokemon.metadata["name"], " is now ", status)
	update_status_icons(target_pokemon, is_target_opponent)
	# GYM2 Brock's Ninetales Shapeshift — A/C/P status discards the attached form
	await powers_and_bodies.shapeshift_check_status_discard(target_pokemon)

# Processes poison damage, burn damage/flip, and sleep wake-up between turns for one pokemon
func process_status_between_turns(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null:
		return

	var pokemon_name = pokemon.metadata.get("name", "Unknown")

	if pokemon.is_poisoned:
		# MATCH EFFECT: poison_damage_multiplier — scale the poison tick
		var poison_tick = match_effects.poison_tick_damage(pokemon.poison_damage, is_opponent)
		pokemon.current_hp = max(0, pokemon.current_hp - poison_tick)
		var label = "TOXIC" if pokemon.poison_damage == 20 else "POISON"
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_poison_sound)
		show_floating_label("-" + str(poison_tick) + "HP", Vector2(530 if !is_opponent else 1030, 300), Color.PURPLE, true)
		display_hp_circles_above_align(pokemon, is_opponent)
		await show_message(pokemon_name.to_upper() + " TAKES " + str(poison_tick) + " " + label + " DAMAGE!")
		print("BETWEEN TURNS: ", pokemon_name, " took ", poison_tick, " poison damage. HP: ", pokemon.current_hp)

	if pokemon.is_burned:
		# EX6 Fiery Aura (Rapidash ex6-13): while a Rapidash with Fiery Aura is Active, Burned Pokemon
		# take 4 damage counters instead of 2 between turns. EX12 Full Flame (ex12-74 Stadium) does the same.
		var burn_dmg = 40 if (powers_and_bodies.is_fiery_aura_active() or is_stadium_in_play("ex12-74")) else 20
		if burn_rules == "base_set_burn_rules":
			await show_message(pokemon_name.to_upper() + " IS BURNED! FLIPPING COIN...")
			var coin = await flip_coin(false, is_opponent)
			if not coin:
				pokemon.current_hp = max(0, pokemon.current_hp - burn_dmg)
				await show_message(pokemon_name.to_upper() + " TAKES " + str(burn_dmg) + " BURN DAMAGE!")
				show_floating_label("-" + str(burn_dmg) + "HP", Vector2(530 if !is_opponent else 1030, 300), Color.RED, is_opponent)
				display_hp_circles_above_align(pokemon, is_opponent)
				print("BETWEEN TURNS: ", pokemon_name, " took ", burn_dmg, " burn damage. HP: ", pokemon.current_hp)
			else:
				await show_message(pokemon_name.to_upper() + " AVOIDED BURN DAMAGE!")
				print("BETWEEN TURNS: ", pokemon_name, " avoided burn damage (heads)")
		elif burn_rules == "modern_era_burn_rules":
			pokemon.current_hp = max(0, pokemon.current_hp - burn_dmg)
			await show_message(pokemon_name.to_upper() + " TAKES " + str(burn_dmg) + " BURN DAMAGE!")
			show_floating_label("-" + str(burn_dmg) + "HP", Vector2(530 if !is_opponent else 1030, 300), Color.RED, is_opponent)
			display_hp_circles_above_align(pokemon, is_opponent)
			print("BETWEEN TURNS: ", pokemon_name, " took 20 burn damage. HP: ", pokemon.current_hp)
			await show_message("FLIPPING COIN TO CURE BURN...")
			var coin = await flip_coin(false, is_opponent)
			if coin:
				pokemon.is_burned = false
				await show_message(pokemon_name.to_upper() + " IS NO LONGER BURNED!")
				update_status_icons(pokemon, is_opponent)
				print("BETWEEN TURNS: ", pokemon_name, " cured of burn (heads)")

	if pokemon.special_condition == "Asleep":
		# DEEP SLEEP (neo4-6 Dark Gengar): flip 2 coins — BOTH must be heads to wake up
		if powers_and_bodies.is_deep_sleep_active():
			await show_message("DEEP SLEEP! " + pokemon_name.to_upper() + " IS IN DEEP SLEEP! FLIPPING 2 COINS...")
			var c1 = await flip_coin(false, is_opponent)
			if _should_bail(): return
			var c2 = await flip_coin(false, is_opponent)
			if _should_bail(): return
			if c1 and c2:
				pokemon.special_condition = ""
				await show_message(pokemon_name.to_upper() + " WOKE UP! (BOTH HEADS)")
				update_status_icons(pokemon, is_opponent)
				print("BETWEEN TURNS: ", pokemon_name, " woke up from Deep Sleep (both heads)")
			else:
				await show_message(pokemon_name.to_upper() + " IS STILL ASLEEP! (DEEP SLEEP)")
				print("BETWEEN TURNS: ", pokemon_name, " still asleep via Deep Sleep")
		else:
			await show_message(pokemon_name.to_upper() + " IS ASLEEP! FLIPPING COIN...")
			var coin = await flip_coin(false, is_opponent)
			if coin:
				pokemon.special_condition = ""
				await show_message(pokemon_name.to_upper() + " WOKE UP!")
				update_status_icons(pokemon, is_opponent)
				print("BETWEEN TURNS: ", pokemon_name, " woke up (heads)")
			else:
				await show_message(pokemon_name.to_upper() + " IS STILL ASLEEP!")
				print("BETWEEN TURNS: ", pokemon_name, " still asleep (tails)")

# Checks confusion retreat rules at the given phase, returns true if retreat should proceed
func check_confused_retreat(pokemon: card_object, is_opponent: bool, phase: String) -> bool:
	if pokemon.special_condition != "Confused":
		return true
	if confusion_rules == "modern_era_confusion_rules":
		return true

	var pokemon_name = pokemon.metadata.get("name", "Unknown")

	if confusion_rules == "fairer_confusion_rules" and phase == "pre_energy":
		await show_message(pokemon_name.to_upper() + " IS CONFUSED! FLIPPING COIN TO RETREAT...")
		var coin = await flip_coin(false, is_opponent)
		if not coin:
			# ISSUE #82 / ISSUE #60: PlusPower +10 each, Defender -20 each on the failed-retreat penalty.
			var retreat_self_dmg = apply_self_damage_modifiers(pokemon, 20)
			pokemon.current_hp = max(0, pokemon.current_hp - retreat_self_dmg)
			await show_message("RETREAT FAILED! " + pokemon_name.to_upper() + " HURT ITSELF FOR " + str(retreat_self_dmg) + " DAMAGE!")
			var label_x = 1030 if is_opponent else 530
			show_floating_label("-" + str(retreat_self_dmg) + "HP", Vector2(label_x, 300), Color.YELLOW, is_opponent)
			display_hp_circles_above_align(pokemon, is_opponent)
			if is_opponent:
				opponent_retreated_this_turn = true
			else:
				player_retreated_this_turn = true
			print("CONFUSED RETREAT FAILED: ", pokemon_name, " took 20 damage (fairer rules)")
			return false
		print("CONFUSED RETREAT PASSED: ", pokemon_name, " can retreat (fairer rules)")
		return true

	if confusion_rules == "base_set_confusion_rules" and phase == "post_energy":
		await show_message(pokemon_name.to_upper() + " IS CONFUSED! FLIPPING COIN TO RETREAT...")
		var coin = await flip_coin(false, is_opponent)
		if not coin:
			await show_message("RETREAT FAILED! ENERGY WAS STILL DISCARDED!")
			if is_opponent:
				opponent_retreated_this_turn = true
			else:
				player_retreated_this_turn = true
			print("CONFUSED RETREAT FAILED: ", pokemon_name, " lost energy but stayed (base set rules)")
			return false
		print("CONFUSED RETREAT PASSED: ", pokemon_name, " can retreat (base set rules)")
		return true

	return true

# Removes all status conditions from a pokemon (used when retreating or evolving)
func clear_all_statuses(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null:
		return

	var had_status = false
	if pokemon.special_condition != "":
		had_status = true
	if pokemon.is_poisoned or pokemon.is_burned or pokemon.is_blind:
		had_status = true
	if pokemon.has_no_damage or pokemon.is_invincible or pokemon.has_destiny_bond:
		had_status = true
	if pokemon.shielded_damage_threshold > 0:
		had_status = true

	pokemon.special_condition = ""
	pokemon.is_poisoned = false
	pokemon.poison_damage = 10
	pokemon.is_burned = false
	pokemon.is_blind = false
	pokemon.has_no_damage = false
	pokemon.is_invincible = false
	pokemon.has_destiny_bond = false
	pokemon.shielded_damage_threshold = 0
	
	# Clear temporary type overrides when leaving play
	pokemon.temporary_weakness = ""
	pokemon.temporary_resistance = ""

	# NEO3: clear flags that should expire when the pokemon leaves the active slot
	pokemon.night_eyes_used = false
	pokemon.submerge_active = false
	pokemon.triggered_poison_active = false
	pokemon.neo3_high_speed_locked = false

	# GYM2 Koga's Ditto Giant Growth: benching ends the HP / Pound boost
	if pokemon.ditto_giant_growth:
		pokemon.ditto_giant_growth = false
		pokemon.max_hp_override = 0
		var real_max = int(pokemon.metadata.get("hp", "0"))
		if pokemon.current_hp > real_max:
			pokemon.current_hp = real_max
	
	# Clear disabled attacks that are "while_in_play" (not "entire_game")
	var keys_to_remove = []
	for atk_name in pokemon.disabled_attacks:
		if pokemon.disabled_attacks[atk_name] != "entire_game":
			keys_to_remove.append(atk_name)
	for key in keys_to_remove:
		pokemon.disabled_attacks.erase(key)

	if had_status:
		print("STATUSES CLEARED: ", pokemon.metadata.get("name", "Unknown"))
		update_status_icons(pokemon, is_opponent)

# Walks backwards from a keyword position in text to extract the preceding number
func get_all_basic_pokemon(card_array: Array) -> Array:
	var basic_pokemon = []
	for card in card_array:
		if is_basic_pokemon(card):
			basic_pokemon.append(card)
	return basic_pokemon

# Function mainly just for readability in the code to check if a pokemon can evolve from another pokemon by checking the evolving pokemon's "evolvesFrom" metadata
#
# A handful of cards print TWO legal pre-evolutions - Blissey ex reads "Evolves from Chansey or
# Chansey ex", Scizor ex reads "Evolves from Scyther or Scyther ex". The card data holds the
# ordinary form in "evolvesFrom" and the extra ones in "evolvesFromAlso", so every other place that
# compares "evolvesFrom" by name keeps finding the common line, and only this check - the one every
# hand evolution, CPU evolution and deck-search trainer goes through - knows about the alternates.
# NOTE this is deliberately NOT given to Rocket's Scizor ex, which only ever evolves from Rocket's
# Scyther ex.
func can_evolve_from(evolving_pokemon: card_object, base_pokemon: card_object) -> bool:
	var base_name = base_pokemon.metadata.get("name", "")
	if evolving_pokemon.metadata.get("evolvesFrom", "") == base_name:
		return true
	for alt in evolving_pokemon.metadata.get("evolvesFromAlso", []):
		if str(alt) == base_name:
			return true
	return false

# Function to check if a card is a basic energy card (not special energy like Double Colorless)
func is_basic_energy_card(card: card_object) -> bool:
	if card.metadata.get("supertype") != "Energy":
		return false
	
	if card.metadata.has("subtypes") and card.metadata["subtypes"].has("Basic"):
		return true
	
	return false

# Function to get the energy type from an energy card name
func get_energy_type_from_card(energy_card: card_object) -> String:
	var energy_name = energy_card.metadata.get("name", "")
	return energy_name.trim_suffix(" Energy")

# Function mainly just for readability to get the pokemon type from a pokemon card
func get_pokemon_type(pokemon_card: card_object) -> String:
	if pokemon_card.metadata.has("types") and pokemon_card.metadata["types"].size() > 0:
		return pokemon_card.metadata["types"][0]
	return "Colorless"
	
# Function to get the HP of a pokemon
func get_pokemon_hp(pokemon_card: card_object) -> int:
	if pokemon_card.metadata.has("hp"):
		return int(pokemon_card.metadata["hp"])
	return 0
	
# Function to check if a basic pokemon has any Stage 1 evolution in the given card array
func has_evolution(base_pokemon: card_object, card_array: Array, stage_type: String) -> bool:
	for card in card_array:
		if card.metadata.has("subtypes") and card.metadata["subtypes"].has(stage_type):
			if can_evolve_from(card, base_pokemon):
				return true
	return false

# Returns the retreat cost count for a Pokemon, or 0 if no retreat cost exists
func get_retreat_cost(pokemon: card_object) -> int:
	if pokemon == null:
		return 0

	# ECARD1 Tailwind (Dragonite): this Pokemon's Retreat Cost is 0 for the rest of the turn
	if pokemon.has_effect("ecard1_tailwind"):
		return 0

	# EX5 Freefloating (Tentacool ex5-77): Retreat Cost is 0 while no Energy is attached
	if powers_and_bodies.is_ex5_freefloating_free(pokemon):
		return 0

	# EX11 Holon Energy WP + basic Psychic attached: this Pokemon's Retreat Cost is 0.
	if special_energy_effects.ex11_holon_wp_free_retreat(pokemon):
		return 0

	# ex10 Free Flight (Gligar): Retreat Cost is 0 while no Energy is attached
	if pokemon.has_ability("Free Flight") and not powers_and_bodies.is_power_blocked(pokemon) and pokemon.attached_energies.is_empty():
		return 0

	# EX14 Flotation (Kyogre ex ex14-95): Retreat Cost is 0 while it has 1 Energy or less attached.
	if pokemon.has_ability("Flotation") and not powers_and_bodies.is_power_blocked(pokemon) and pokemon.attached_energies.size() <= 1:
		return 0

	# EX15 Psychic Wing (Vibrava δ ex15-24): Retreat Cost is 0 while any Psychic Energy is attached.
	if pokemon.has_ability("Psychic Wing") and not powers_and_bodies.is_power_blocked(pokemon):
		for e in pokemon.attached_energies:
			if "Psychic" in get_energy_provided_by_card(e):
				return 0

	# EX15 Link Wing (Latios ex δ ex15-96): the Retreat Cost for each of your Latias/Latias ex/Latios/
	# Latios ex is 0 while a Latios with this Body is in play on that side.
	var lw_name = pokemon.metadata.get("name","")
	if "Latias" in lw_name or "Latios" in lw_name:
		var lw_is_opp = (pokemon == opponent_active_pokemon or pokemon in opponent_bench)
		for lp in card_ops.get_all_pokemon_in_play(lw_is_opp):
			if lp.has_ability("Link Wing") and not powers_and_bodies.is_power_blocked(lp):
				return 0

	# EX15 Extra Wing (Swellow δ ex15-40): the Retreat Cost for each of your Stage 2 Pokémon-ex is 0 while
	# a Swellow with this Body is in play on that side.
	if "Stage 2" in pokemon.metadata.get("subtypes", []) and is_ex_pokemon(pokemon):
		var ew_is_opp = (pokemon == opponent_active_pokemon or pokemon in opponent_bench)
		for ep in card_ops.get_all_pokemon_in_play(ew_is_opp):
			if ep.has_ability("Extra Wing") and not powers_and_bodies.is_power_blocked(ep):
				return 0

	# ex10 Fluffy Berry (Pokémon Tool ex10-85): Retreat Cost is 0 while attached
	for ac in pokemon.attached_cards:
		if ac.uid.to_lower() == "ex10-85":
			return 0

	# ECARD3 Psychoflow (Abra): Retreat Cost is 0 as long as a Psychic Energy is attached to it
	if pokemon.has_ability("Psychoflow") and not powers_and_bodies.is_power_blocked(pokemon):
		for e in pokemon.attached_energies:
			if "Psychic" in get_energy_provided_by_card(e):
				return 0

	# EX12 Reactive Lift (Wailord ex12-14): while a Wailord on this side has any React Energy attached,
	# this side's Water Pokemon (excluding Pokemon-ex) have Retreat Cost 0.
	if not is_ex_pokemon(pokemon) and "Water" in pokemon.get_effective_types():
		var rl_is_opp = (pokemon == opponent_active_pokemon or pokemon in opponent_bench)
		for wp in card_ops.get_all_pokemon_in_play(rl_is_opp):
			if wp.has_ability("Reactive Lift") and wp.react_energy_count() > 0 and not powers_and_bodies.is_power_blocked_by_status(wp):
				return 0

	# EX2 Uplifting Glow (Volbeat): Retreat Cost is 0 as long as Illumise is in play on its side.
	if pokemon.has_ability("Uplifting Glow") and not powers_and_bodies.is_power_blocked(pokemon):
		var volbeat_is_opp = (pokemon == opponent_active_pokemon or pokemon in opponent_bench)
		if powers_and_bodies._ex2_named_in_play(volbeat_is_opp, "Illumise"):
			return 0

	# ECARD3 Slippery Skin (Dunsparce): Retreat Cost is 0 as long as the Defending Pokemon is Evolved
	if pokemon.has_ability("Slippery Skin") and not powers_and_bodies.is_power_blocked(pokemon):
		var dunsparce_is_opp = (pokemon == opponent_active_pokemon or pokemon in opponent_bench)
		var defending = player_active_pokemon if dunsparce_is_opp else opponent_active_pokemon
		if defending != null and not is_basic_pokemon(defending):
			return 0

	# MATCH EFFECT: free_retreat — retreating costs nothing for this side
	var pokemon_is_opponent = (pokemon == opponent_active_pokemon or pokemon in opponent_bench)
	if match_effects.retreat_is_free(pokemon_is_opponent):
		return 0

	var cost = pokemon.metadata.get("retreatCost", []).size()

	# Dodrio Retreat Aid: reduce retreat cost by 1 while Dodrio is on the bench
	var bench = []
	if pokemon == player_active_pokemon or pokemon in player_bench:
		bench = player_bench
	elif pokemon == opponent_active_pokemon or pokemon in opponent_bench:
		bench = opponent_bench
	for bp in bench:
		var bp_abilities = bp.metadata.get("abilities", [])
		for _ability in bp_abilities:
			if _ability.get("name", "") == "Retreat Aid":
				if bp.special_condition not in ["Paralyzed", "Asleep", "Confused"] and not bp.is_poisoned:
					cost = max(0, cost - 1)
					break

	# EX15 Stages of Evolution (Jynx δ ex15-17): while an Evolved Jynx with this Body is in play, you pay
	# Colorless less (1 per such Jynx) to retreat your Fire and Psychic Pokémon.
	var soe_types = pokemon.get_effective_types()
	if "Fire" in soe_types or "Psychic" in soe_types:
		var soe_is_opp = (pokemon == opponent_active_pokemon or pokemon in opponent_bench)
		for jp in card_ops.get_all_pokemon_in_play(soe_is_opp):
			if jp.metadata.get("name","") == "Jynx δ" and jp.has_ability("Stages of Evolution") and not jp.attached_pre_evolutions.is_empty() and not powers_and_bodies.is_power_blocked(jp):
				cost = max(0, cost - 1)

	# Dark Muk Sticky Goo: opponent pays 2 more to retreat
	var is_player_pokemon = (pokemon == player_active_pokemon or pokemon in player_bench)
	cost += powers_and_bodies.get_sticky_goo_cost(is_player_pokemon)

	# EX12 Stages of Evolution (Wobbuffet ex12-28): while an Evolved Wobbuffet with this Body is in play,
	# that player's OPPONENT pays 1 Colorless more to retreat their Active Pokemon.
	if pokemon == player_active_pokemon or pokemon == opponent_active_pokemon:
		var wob_side_opp = not (pokemon == opponent_active_pokemon or pokemon in opponent_bench)
		for wob in card_ops.get_all_pokemon_in_play(wob_side_opp):
			if wob.metadata.get("name","") == "Wobbuffet" and wob.has_ability("Stages of Evolution") and not wob.attached_pre_evolutions.is_empty() and not powers_and_bodies.is_power_blocked_by_status(wob):
				cost += 1
				break

	# ECARD2 self-reduction Poké-Bodies: Extreme Speed (Arcanine, -1 per Energy attached),
	# Lightweight (Skiploom/Hoppip, -1 per Grass Energy attached)
	if not powers_and_bodies.is_power_blocked(pokemon):
		for ab in pokemon.metadata.get("abilities", []):
			if ab.get("name", "") == "Extreme Speed":
				cost = max(0, cost - pokemon.attached_energies.size())
			elif ab.get("name", "") == "Levitate":
				# EX3 Vibrava (ex3-46): 0 while any basic Energy attached. ex9 Claydol (ex9-24): 0 while
				# ANY Energy attached — branch on the ability's own wording.
				if "basic energy" in ab.get("text","").to_lower():
					for e in pokemon.attached_energies:
						if "Basic" in e.metadata.get("subtypes", []):
							cost = 0
							break
				elif pokemon.attached_energies.size() > 0:
					cost = 0
			elif ab.get("name", "") == "Lightweight":
				var grass_n = 0
				for e in pokemon.attached_energies:
					if "Grass" in get_energy_provided_by_card(e): grass_n += 1
				cost = max(0, cost - grass_n)
			elif ab.get("name", "") == "Leaf Ride" or ab.get("name", "") == "Floating Electrons":
				# EX6 Scyther (ex6-29) / Voltorb (ex6-85): Retreat Cost is 0 while any Energy is attached
				if not pokemon.attached_energies.is_empty():
					cost = 0
			elif ab.get("name", "") == "Free Flight":
				# EX6 Fearow (ex6-24): Retreat Cost is 0 while NO Energy is attached
				if pokemon.attached_energies.is_empty():
					cost = 0
				# EX8 Metallic Lift (Skarmory ex8-26): Retreat Cost is 0 while any Metal Energy is attached
			elif ab.get("name", "") == "Metallic Lift":
				for e in pokemon.attached_energies:
					if "Metal" in get_energy_provided_by_card(e):
						cost = 0
						break
				# EX8 Aqua Lift (Lombre ex8-33): Retreat Cost is 0 while any Water Energy is attached
			elif ab.get("name", "") == "Aqua Lift":
				for e in pokemon.attached_energies:
					if "Water" in get_energy_provided_by_card(e):
						cost = 0
						break

	# EX6 Family Bonds (Nidoqueen ex6-9): Retreat Cost is 0 for the Nidoran family and Nidoking while a
	# Nidoqueen is in play on that side.
	if pokemon.metadata.get("name", "") in ["Nidoran ♀", "Nidorina", "Nidoran ♂", "Nidorino", "Nidoking"]:
		var side_all: Array = bench.duplicate()
		var side_active = player_active_pokemon if (pokemon == player_active_pokemon or pokemon in player_bench) else opponent_active_pokemon
		if side_active != null:
			side_all.append(side_active)
		for np in side_all:
			if np.metadata.get("name", "") == "Nidoqueen" and not powers_and_bodies.is_power_blocked(np):
				cost = 0
				break

	# EX14 Hover Lift (Igglybuff ex14-21): you pay Colorless less to retreat your Jigglypuff, Wigglytuff,
	# Wigglytuff ex, and Igglybuff while an Igglybuff with this Body is in play on that side.
	if pokemon.metadata.get("name", "") in ["Jigglypuff", "Wigglytuff", "Wigglytuff ex", "Igglybuff"]:
		var hl_side_all: Array = bench.duplicate()
		var hl_side_active = player_active_pokemon if (pokemon == player_active_pokemon or pokemon in player_bench) else opponent_active_pokemon
		if hl_side_active != null:
			hl_side_all.append(hl_side_active)
		for hp in hl_side_all:
			if hp.has_ability("Hover Lift") and not powers_and_bodies.is_power_blocked(hp):
				cost = max(0, cost - 1)
				break

	# EX8 Moonglow (Lunatone ex8-36): the Retreat Cost for each Solrock you have in play is 0.
	# EX8 Dragon Lift (Salamence ex ex8-103): Retreat Cost is 0 for each of your Pokemon (excluding
	# Pokemon-ex and Baby Pokemon) while Salamence ex is in play on that side.
	var lift_side_all: Array = bench.duplicate()
	var lift_side_active = player_active_pokemon if (pokemon == player_active_pokemon or pokemon in player_bench) else opponent_active_pokemon
	if lift_side_active != null:
		lift_side_all.append(lift_side_active)
	if pokemon.metadata.get("name", "") == "Solrock":
		for lp in lift_side_all:
			if lp.has_ability("Moonglow") and not powers_and_bodies.is_power_blocked(lp):
				cost = 0
				break
	if not is_ex_pokemon(pokemon) and "Baby" not in pokemon.metadata.get("subtypes", []):
		for lp in lift_side_all:
			if lp.has_ability("Dragon Lift") and not powers_and_bodies.is_power_blocked(lp):
				cost = 0
				break

	# ECARD2 Heavyweight (Muk): +2 while a Grass Energy is attached to Muk itself
	if not powers_and_bodies.is_power_blocked(pokemon):
		for ab in pokemon.metadata.get("abilities", []):
			if ab.get("name", "") == "Heavyweight":
				for e in pokemon.attached_energies:
					if "Grass" in get_energy_provided_by_card(e):
						cost += 2
						break

	# ECARD2 Conductive Body (Magnemite) / EX11 Conductive Body (Beldum): -1 per Pokemon of the SAME
	# name on this side's bench ("for each <self> on your Bench").
	if not powers_and_bodies.is_power_blocked(pokemon):
		for ab in pokemon.metadata.get("abilities", []):
			if ab.get("name", "") == "Conductive Body":
				var mag_count = 0
				for bp in bench:
					if bp.metadata.get("name", "") == pokemon.metadata.get("name", ""): mag_count += 1
				cost = max(0, cost - mag_count)

	# ECARD2 Gluey Slime (Ariados): while ANY Ariados is in play, both sides pay +1 to retreat their
	# Active (capped at +1 total regardless of how many Ariados are in play)
	var all_field_ariados: Array = []
	if player_active_pokemon != null: all_field_ariados.append(player_active_pokemon)
	all_field_ariados.append_array(player_bench)
	if opponent_active_pokemon != null: all_field_ariados.append(opponent_active_pokemon)
	all_field_ariados.append_array(opponent_bench)
	for p in all_field_ariados:
		if p.metadata.get("name", "") == "Ariados" and not powers_and_bodies.is_power_blocked(p):
			cost += 1
			break

	# GYM1-104 The Rocket's Training Gym — both players pay +1 Colorless to retreat their Active Pokemon
	if is_stadium_in_play(StadiumIds.ROCKETS_TRAINING_GYM):
		cost += 1
	# GYM1-108 Cerulean City Gym — Pokemon with "Misty" in name pay 1 less to retreat
	if is_stadium_in_play(StadiumIds.CERULEAN_CITY_GYM):
		var pname = pokemon.metadata.get("name", "")
		if "Misty" in pname:
			cost = max(0, cost - 1)
	# EX3-85 High Pressure System — each player pays 1 less to retreat Fire/Water Pokemon
	if is_stadium_in_play(StadiumIds.HIGH_PRESSURE_SYSTEM):
		var eff_types = pokemon.get_effective_types()
		if "Fire" in eff_types or "Water" in eff_types:
			cost = max(0, cost - 1)
	# EX16-79 Phoebe's Stadium — each player pays 2 Colorless less to retreat their Psychic Pokemon
	if is_stadium_in_play(StadiumIds.PHOEBES_STADIUM):
		if "Psychic" in pokemon.get_effective_types():
			cost = max(0, cost - 2)
	# EX4-78 Team Aqua Hideout — Pokemon without "Team Aqua" in name pay 1 more to retreat
	if is_stadium_in_play(StadiumIds.TEAM_AQUA_HIDEOUT):
		if "Team Aqua" not in pokemon.metadata.get("name", ""):
			cost += 1
	# EX4-25 Team Aqua's Carvanha Dark Lift (Poké-Body): retreat 0 while it has Darkness Energy attached
	if pokemon.has_ability("Dark Lift") and not powers_and_bodies.is_power_blocked(pokemon):
		for e in pokemon.attached_energies:
			if "Darkness" in get_energy_provided_by_card(e):
				return 0
	# EX7 Scramble (Rattata ex7-71): retreat 0 while the opponent's Active is a Pokémon-ex.
	if powers_and_bodies.ex7_scramble_free_retreat(pokemon):
		return 0

	# MATCH EFFECT: retreat_cost_modifier — flat adjustment to retreat cost (floor 0)
	cost = max(0, cost + match_effects.retreat_cost_modifier(pokemon_is_opponent))

	# NEO4 Broken Ground Gym (neo4-92): each player pays +1 to retreat a Baby/Basic Pokemon
	if is_stadium_in_play(StadiumIds.BROKEN_GROUND_GYM):
		var subs = pokemon.metadata.get("subtypes", [])
		if "Basic" in subs or "Baby" in subs:
			cost += 1

	# NEO4 Unown [Z] (neo4-60) [Zoom]: while it is benched, Unown pay no Energy to retreat
	if "Unown" in pokemon.metadata.get("name", ""):
		for bp in bench:
			if bp.has_ability("[Zoom]") and not bp.is_status_blocked():
				return 0

	# NEO3 Balloon Berry (neo3-60 Tool): makes retreat free
	if trainer_effects.check_balloon_berry_retreat_free(pokemon):
		return 0

	# NP Synchronized Lift (np-31/32/33 Moltres/Articuno/Zapdos ex): free retreat if partners in play
	if powers_and_bodies.check_synchronized_lift(pokemon, pokemon_is_opponent):
		return 0

	return cost

# Returns true if the named stadium (uid) is the currently active stadium card
# POP-series Stadium reprints share the exact rules of an existing Stadium but carry a new UID.
# Normalize the in-play card's UID to its canonical StadiumIds constant so every existing
# is_stadium_in_play(StadiumIds.X) check recognizes the reprint without further changes.
const STADIUM_UID_ALIASES := {
	"pop2-10": StadiumIds.POKEMON_PARK,          # Pokémon Park (= ecard2-131)
	"pop3-10": StadiumIds.HIGH_PRESSURE_SYSTEM,  # High Pressure System (= ex3-85)
	"pop3-11": StadiumIds.LOW_PRESSURE_SYSTEM,   # Low Pressure System (= ex3-86)
}

func is_stadium_in_play(uid: String) -> bool:
	if current_stadium_card == null:
		return false
	var cur = current_stadium_card.uid.to_lower()
	cur = STADIUM_UID_ALIASES.get(cur, cur)
	return cur == uid.to_lower()

# Returns the bench cap. Reduced to 4 while gym1-124 Narrow Gym is in play.
# May be reduced further by the bench_size_limit match effect.
func get_max_bench_size() -> int:
	var cap = 5
	if is_stadium_in_play(StadiumIds.NARROW_GYM):
		cap = 4
	# EX12 Giant Stump (ex12-75 Stadium): each player can't have more than 3 Benched Pokemon.
	if is_stadium_in_play("ex12-75"):
		cap = min(cap, 3)
	var rule_cap = match_effects.max_bench_size_override()
	if rule_cap > 0:
		cap = min(cap, rule_cap)
	return cap

# MATCH EFFECT: max_hp_modifier — apply the per-side max HP shift to every pokemon card
# in deck + hand at game start (floor 10 HP). current_hp follows so cards start full.
func apply_max_hp_modifier_match_effect() -> void:
	for side in [false, true]:
		var shift = match_effects.max_hp_modifier(side)
		if shift == 0:
			continue
		var piles = [player_deck, player_hand] if not side else [opponent_deck, opponent_hand]
		for pile in piles:
			for card in pile:
				if card.metadata.get("supertype", "") != "Pokémon":
					continue
				var base_hp = int(card.metadata.get("hp", "0"))
				if base_hp <= 0:
					continue
				card.max_hp_override = max(10, base_hp + shift)
				card.current_hp = card.max_hp_override

# GYM1-120 Vermilion City Gym pre-attack flip. If stadium is in play and attacker name contains "Lt. Surge",
# the attacker MAY flip a coin. Heads = +10 damage; tails = 10 self-damage after attack.
# Player gets a YES/NO prompt (always; the upside is free unless attacker would be KO'd by 10 self-damage).
# CPU heuristic: skip if the 10 self-damage would KO the attacker or leave it 1-shot to player; otherwise flip.
func maybe_vermilion_lt_surge_flip(attacker: card_object, is_opponent: bool) -> void:
	if attacker == null:
		return
	if not is_stadium_in_play(StadiumIds.VERMILION_CITY_GYM):
		return
	if not ("Lt. Surge" in attacker.metadata.get("name", "")):
		return

	var wants_flip := false
	if is_opponent:
		# CPU heuristic: don't flip if 10 self-damage would KO us; otherwise always take the chance for +10
		if attacker.current_hp <= 10:
			wants_flip = false
		else:
			wants_flip = true
	else:
		# Player chooses
		wants_flip = await trainer_effects.gym1_prompt_yes_no(
			attacker,
			"VERMILION CITY GYM",
			"Flip coin? Heads: +10 damage. Tails: 10 self-damage.",
			"FLIP",
			"SKIP"
		)
		if _should_bail(): return

	if not wants_flip:
		return

	await show_message("VERMILION CITY GYM: Flipping coin...")
	if _should_bail(): return
	var heads = await flip_coin(false, is_opponent)
	if _should_bail(): return
	if heads:
		vermilion_lt_surge_bonus_damage = 10
		vermilion_lt_surge_self_damage_pending = 0
		await show_message("HEADS! +10 damage!")
	else:
		vermilion_lt_surge_bonus_damage = 0
		vermilion_lt_surge_self_damage_pending = 10
		vermilion_lt_surge_attacker_is_opponent = is_opponent
		await show_message("TAILS! " + attacker.metadata.get("name", "") + " takes 10 self-damage after the attack.")
	if _should_bail(): return

# Loads the small card image texture for any card object by its UID
func get_card_texture(card: card_object) -> Texture2D:
	# Ditto Transform: if this card is a transformed Ditto, return a whitened version
	if card.is_ditto_transformed and card.ditto_transform_uid != "":
		var ditto_cache_key = "ditto_" + card.ditto_transform_uid
		if ditto_cache_key in _texture_cache:
			return _texture_cache[ditto_cache_key]
		# Load the target card's texture and apply a 20% white overlay
		var target_uid = card.ditto_transform_uid
		var target_set = target_uid.split("-")[0]
		var base_tex = load("res://Image_Assets/Card_Image_Library/" + target_set + "/Small/" + target_uid + ".png")
		if base_tex != null:
			var img = base_tex.get_image()
			if img != null:
				img = img.duplicate()
				var white_blend = 0.20
				for y in range(img.get_height()):
					for x in range(img.get_width()):
						var c = img.get_pixel(x, y)
						c.r = lerp(c.r, 1.0, white_blend)
						c.g = lerp(c.g, 1.0, white_blend)
						c.b = lerp(c.b, 1.0, white_blend)
						img.set_pixel(x, y, c)
				var whitened = ImageTexture.create_from_image(img)
				_texture_cache[ditto_cache_key] = whitened
				return whitened
		# Fallback if texture load fails
		if base_tex != null:
			_texture_cache[ditto_cache_key] = base_tex
			return base_tex
	
	# Fix 8: Cache textures by UID to avoid redundant load() calls
	if card.uid in _texture_cache:
		return _texture_cache[card.uid]
	var card_set = card.uid.split("-")[0]
	var tex = load("res://Image_Assets/Card_Image_Library/" + card_set + "/Small/" + card.uid + ".png")
	_texture_cache[card.uid] = tex
	return tex

# Returns a colour based on a Pokemon's primary type
func get_pokemon_type_colour(pokemon: card_object) -> Color:
	var types = pokemon.metadata.get("types", ["Colorless"])
	return get_type_colour(types[0])

################################################# END SMALL FUNCTIONS TO HELP WITH CODE READABILITY ##################################################
######################################################################################################################################################

# #######  ######   ##   ##        #######  ##   ##    ######    ########  #######  #######
# ##       ##   ##  ##   ##        ##       ##   ##  ##      ##     ##     ##       ## 
# ##       ######   ##   ##  ##### ##       #######  ##      ##     ##     ##       #######
# ##       ##       ##   ##        ##       ##   ##  ##      ##     ##     ##       ##
# #######  ##       #######        #######  ##   ##    ######     #######  #######  #######

######################################################################################################################################################
#################################################### OPPONENT PRIORITISE FUNCTIONALITY FUNCTIONS #####################################################

# Function to get lowest cost attack for a pokemon by looping through all attacks. Returns a dictionary with "cost" (convertedEnergyCost), "damage" (as int), and "attack_name"
func _resolve_sleeve_path(sleeve_name: String, small: bool) -> String:
	var default_path = "res://Image_Assets/Sleeves/1_Default_English.png"
	if sleeve_name == "" or sleeve_name == "default":
		return default_path
	# Sleeves are stored by name with no extension; the originals are a mix of .jpg and .png,
	# so try both. Matches always use the full-size original, never the small/ grid thumbnails.
	for ext in [".jpg", ".png"]:
		var path = "res://Image_Assets/Sleeves/" + sleeve_name + ext
		# Verify the asset is actually loadable — files may not be imported yet
		if ResourceLoader.exists(path) and load(path) != null:
			return path
	return default_path

# Samples the right-center edge pixel of a sleeve texture and returns it darkened 50%.
# Used to give each deck's stack border a colour that complements the sleeve art.
func _derive_sleeve_border_color(tex: Texture2D) -> Color:
	var fallback := Color(0.15, 0.15, 0.15, 1.0)
	if tex == null:
		return fallback
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return fallback
	img.decompress()
	var sampled := img.get_pixel(img.get_width() - 1, img.get_height() / 2)
	return sampled.darkened(0.5)

func load_opponent_data_by_name(opp_name: String):
	# TEMP TESTING: T-key TEST match synthesizes opponent data instead of reading NPC JSON.
	if GameState.test_match_mode:
		opponent_data = GameState.build_test_opponent_data()
		return

	opponent_data = CharacterSchedule.find_opponent(
		GameState.current_opponent_map, opp_name,
		GameState.get_date(), GameState.get_time(), MapManager.evaluate_condition)
	if opponent_data.is_empty():
		print("Opponent with name ", opp_name, " not found on map ",
			GameState.current_opponent_map)

# Play the correct music via the global SoundManager
# The JSON holds a bare track name (no folder, no extension) picked in the character editor;
# the Sound Manager turns that into a path. Opponents still carrying the "REPLACEMUSIC" /
# "TEST" placeholders name no real file, so they fall through to play_bgm()'s own warning.
func play_opponent_music():
	var music_file = opponent_data.get("music")
	if music_file == null:
		print("No music file specified")
		return

	SoundManagerScript.play_bgm_named(str(music_file), true)

# Function to set up opponent's active and bench pokemon using the priority condition criteria scoring selection
func action_button_pressed_perform_action() -> void:
	
	action_button.text = "Select a Card"
	action_button.disabled = true
	action_button.theme = theme_disabled
	
	if retreat_mode_active:
		retreat_mode_active = false
		start_retreat_bench_selection()
		return
	
	if retreat_bench_selection_active:
		await handle_action_retreat_bench()
		return
	
	if knockout_bench_selection_active:
		await handle_action_knockout_bench()
		return
	
	if card_attach_mode_active:
		perform_energy_attachment()
		return
	
	if evolution_mode_active:
		await handle_action_evolution()
		return
	
	if prize_card_selection_active:
		await handle_action_prize_card()
		return
	
	# Trainer card selection modes
	if trainer_pokemon_selection_active or trainer_deck_search_active:
		if selected_card_for_action != null:
			trainer_target_selected.emit()
		return
	
	if trainer_discard_selection_active:
		# Confirm the selection (cards already toggled via click handler)
		if trainer_discard_selected.size() >= trainer_discard_cards_needed:
			trainer_discard_selection_done.emit()
		return
	
	# Pokedex reorder: confirm the chosen order
	if trainer_reorder_active:
		if pokedex_reorder_result.size() >= pokedex_cards.size():
			trainer_reorder_done.emit()
		return
	
	# Forced switch: player selects bench pokemon to switch in
	if forced_switch_selection_active:
		if selected_card_for_action != null and selected_card_for_action in player_bench:
			var old_active = player_active_pokemon
			player_bench.erase(selected_card_for_action)
			player_bench.append(old_active)
			old_active.current_location = "bench"
			selected_card_for_action.current_location = "active"
			player_active_pokemon = selected_card_for_action
			clear_all_statuses(old_active, false)
			hide_selection_mode_display_main()
			display_pokemon(false)
			display_active_pokemon_energies(false)
			await show_message("SWITCHED TO " + player_active_pokemon.metadata["name"].to_upper() + "!")
			forced_switch_chosen.emit()
		return
	
	# Defender energy discard: player selects energy to discard from their active
	if defender_energy_discard_active:
		if selected_card_for_action != null:
			defender_energy_chosen.emit(selected_card_for_action)
		return
	
	# Energy type selection for Conversion
	if energy_type_selection_active:
		if selected_card_for_action != null:
			var energy_name = selected_card_for_action.metadata.get("name", "")
			var energy_type = energy_name.replace(" Energy", "").strip_edges()
			energy_type_selected.emit(energy_type)
		return
	
	await handle_action_normal_card()

# Performs the player's retreat: confusion checks, bench swap, animation, and status clearing
func handle_action_retreat_bench() -> void:
	var new_active = selected_card_for_action

	# ECARD3 Mirage Stadium: any retreat attempt requires a coin flip — tails blocks it entirely
	var mirage_ok = await trainer_effects.mirage_stadium_check(false)
	if _should_bail(): return
	if not mirage_ok:
		retreat_bench_selection_active = false
		selected_card_for_action = null
		retreat_energies_selected.clear()
		hide_selection_mode_display_main()
		display_pokemon(false)
		display_active_pokemon_energies(false)
		return

	var pre_check = await check_confused_retreat(player_active_pokemon, false, "pre_energy")
	if not pre_check:
		retreat_bench_selection_active = false
		selected_card_for_action = null
		hide_selection_mode_display_main()
		display_hp_circles_above_align(player_active_pokemon, false)
		await check_all_knockouts()
		if _should_bail(): return
		display_pokemon(false)
		return

	var post_check = await check_confused_retreat(player_active_pokemon, false, "post_energy")
	if not post_check:
		retreat_bench_selection_active = false
		selected_card_for_action = null
		hide_selection_mode_display_main()
		display_pokemon(false)
		display_active_pokemon_energies(false)
		return

	# [CHASE] (neo4-57 Unown [C]): opponent's active Unown [C] may deal 1 damage counter when we retreat
	await powers_and_bodies.check_neo4_chase(player_active_pokemon, false)
	if _should_bail(): return
	# ECARD2 Suction Cups (Octillery): if opponent's Active is Octillery, discard our energy when we retreat
	powers_and_bodies.check_suction_cups(player_active_pokemon, false)
	# EX16 Metal Gravity (Skarmory ex ex16-98): opponent's Active reacts to our retreat with 3 counters.
	await powers_and_bodies.check_ex16_metal_gravity(player_active_pokemon, false)
	if _should_bail(): return

	player_bench.erase(new_active)
	player_bench.append(player_active_pokemon)

	player_active_pokemon.current_location = "bench"
	new_active.current_location = "active"

	player_retreated_this_turn = true
	retreat_bench_selection_active = false
	selected_card_for_action = null

	var retreating_pokemon = player_active_pokemon  # Save ref before reassignment

	hide_selection_mode_display_main()
	await animate_retreat(retreating_pokemon, new_active, retreat_energies_selected, false)

	# NEO3 Balloon Berry (neo3-60): if the retreating pokemon used Balloon Berry for free retreat, discard it.
	# ISSUE #7: animate_retreat now reassigns player_active_pokemon to the new Active, so operate on the
	# saved `retreating_pokemon` (the OLD Active) here rather than the pointer.
	trainer_effects.consume_balloon_berry(retreating_pokemon, false)
	clear_all_statuses(retreating_pokemon, false)
	player_active_pokemon = new_active
	retreat_energies_selected.clear()

	display_pokemon(false)
	display_active_pokemon_energies(false)

	# Update Ditto Transform after active switch
	powers_and_bodies.update_ditto_transform(false)
	powers_and_bodies.update_ditto_transform(true)

	# NEO2 Pursuit (Umbreon): if retreating pokemon has pursuit_active, take 10 damage
	if retreating_pokemon.pursuit_active:
		retreating_pokemon.pursuit_active = false
		retreating_pokemon.current_hp = max(0, retreating_pokemon.current_hp - 10)
		display_hp_circles_above_align(retreating_pokemon, false)
		await show_message("PURSUIT! " + retreating_pokemon.metadata.get("name","").to_upper() + " TAKES 10 DAMAGE FOR RETREATING!")
		if _should_bail(): return
		await check_all_knockouts()
		if _should_bail(): return

	# Sinkhole (Dark Dugtrio): damage to retreating Pokemon
	await powers_and_bodies.check_sinkhole(retreating_pokemon, false)
	if _should_bail(): return
	await check_all_knockouts()
	if _should_bail(): return
	# NEO3 Magma Pool (Magcargo neo3-33): when Magcargo retreats, both pokemon take 20 damage
	powers_and_bodies.check_magma_pool(retreating_pokemon, player_active_pokemon, false)
	await check_all_knockouts()
	if _should_bail(): return
	# NEO2 Spikes (Forretress): 10 damage to new active pokemon (player's bench→active)
	await powers_and_bodies.check_spikes(new_active, false)
	if _should_bail(): return
	await check_all_knockouts()
	if _should_bail(): return

# Moves a bench pokemon to the active slot after a knockout and triggers post-knockout signals
func handle_action_knockout_bench() -> void:
	var new_active = selected_card_for_action
	# ISSUE #276: measured while the card is still on the bench (or in the picker),
	# before the erase and the screen teardown below take its node away.
	var pl_repl_from := _card_rect_now(new_active)
	player_bench.erase(new_active)
	new_active.current_location = "active"
	player_active_pokemon = new_active

	knockout_bench_selection_active = false
	selected_card_for_action = null

	hide_selection_mode_display_main()

	var new_texture = get_card_texture(new_active)
	# ISSUE #20: glide to the real active slot and grow to active size (no post-refresh pop)
	# ISSUE #276: the SIBLING of the opponent's replacement above - same two stale
	# card_scales entries. get_pokemon_screen_location already reported the right
	# numbers here, so only the fallbacks and the start size were wrong, but they
	# are the ones that bite the moment the lookup misses.
	var active_loc = get_pokemon_screen_location(new_active)
	print("ISSUE #276 FIX ACTIVE: player bench -> active ",
		pl_repl_from.get("size", BENCH_CARD), " -> ", active_loc.get("size", ACTIVE_CARD))
	await animate_card_a_to_b(player_bench_container, player_active_container, 0.3,
		new_texture, pl_repl_from.get("size", BENCH_CARD),
		active_loc.get("size", ACTIVE_CARD),
		active_loc.get("position", _ANIM_POS_SENTINEL), false,
		pl_repl_from.get("position", _ANIM_POS_SENTINEL))

	display_pokemon(false)
	# ISSUE #87: the slot was hidden for the knockout animation — reveal it now the replacement has
	# landed, so the new card AND its HP squares appear together.
	set_active_slot_visible(false, true)
	display_active_pokemon_energies(false)
	display_hp_circles_above_align(player_active_pokemon, false)

	# NEO2 Spikes (Forretress): 10 damage to player's new active after KO replacement
	await powers_and_bodies.check_spikes(new_active, false)
	if _should_bail(): return
	await check_all_knockouts()
	if _should_bail(): return

	knockout_replacement_chosen.emit()

# Evolves the selected target pokemon, plays animations, and refreshes the display
func handle_action_evolution() -> void:
	var evo_card = evolution_card_awaiting_target
	var target_card = selected_card_for_action
	
	# ISSUE #283: measured BEFORE perform_evolution, which takes the card out of
	# the hand - after that there is no node left to measure.
	var evo_from := _card_rect_now(evo_card)
	
	perform_evolution(false)
	
	evolution_card_awaiting_target = null
	selected_card_for_action = null
	evolution_mode_active = false
	
	hide_selection_mode_display_main()
	refresh_hand_display(false)
	
	var target_node = null
	var card_scale_to_animate = card_scales[12]
	
	if evo_card.current_location == "active": 
		target_node = player_active_container
		card_scale_to_animate = card_scales[8]
	else:
		target_node = player_bench_container
		card_scale_to_animate = card_scales[11]
		
	var evo_texture = get_card_texture(evo_card)
	# ISSUE #20: land on the evolving Pokémon's actual slot at its real size
	var evo_loc = get_pokemon_screen_location(evo_card)
	print("ISSUE #283 FIX ACTIVE: evolution leaves hand from ",
		evo_from.get("position", "container fallback"))
	await animate_card_a_to_b(player_hand_container, target_node, 0.3, evo_texture,
		evo_from.get("size", card_scale_to_animate),
		evo_loc.get("size", card_scale_to_animate),
		evo_loc.get("position", _ANIM_POS_SENTINEL), false,
		evo_from.get("position", _ANIM_POS_SENTINEL))

	display_pokemon(false)
	await get_tree().process_frame
	await play_evolution_effect(evo_card)
	display_active_pokemon_energies(false)

# Takes the selected prize card and adds it to the player's hand with animation
func handle_action_prize_card() -> void:
	var prize_card = selected_card_for_action
	prize_card_selection_active = false
	selected_card_for_action = null
	
	hide_selection_mode_display_main()
	await take_prize_card(prize_card, false)
	prize_card_taken.emit()

# Handles playing a card from the player's hand: placing pokemon, attaching energy, evolving, or playing trainers
func handle_action_normal_card() -> void:
	# Don't do anything if no card is selected
	if selected_card_for_action == null:
		print("Error: No card selected for action")
		return
	
	# Prevent playing opponents cards
	if selected_card_for_action not in player_hand:
		print("Error: Can only play cards from your own hand")
		return
		
	# EX11 Holon's Pokémon (Magnemite/Voltorb/Electrode/Magneton) may be attached from hand as a
	# Special Energy card. Outside the opening setup phases, offer that choice before the normal
	# Pokémon action (place/evolve). If the player attaches it as Energy, we are done for this card.
	if not match_just_started_basic_pokemon_required and not bench_setup_phase_active \
			and attack_effects.card_can_attach_as_energy(selected_card_for_action):
		var chose_energy = await attack_effects.prompt_and_attach_holon_pokemon_energy(selected_card_for_action, false)
		if _should_bail(): return
		if chose_energy:
			hide_selection_mode_display_main()
			return

	# Get the action type
	var action_info = get_card_action(selected_card_for_action)
	var action_type = action_info["action"]

	# Perform the appropriate action based on card type
	match action_type:
		"SET_POKEMON":
			if match_just_started_basic_pokemon_required:
				# First turn - SET AS ACTIVE POKEMON pokemon
				set_player_active_pokemon()
				display_pokemon(false)  # false = player
				refresh_hand_display(false)
				match_just_started_basic_pokemon_required = false
				
				# After active pokemon is set, start the bench setup phase
				start_bench_setup_phase()
			else:
				var bench_card = selected_card_for_action
				# ISSUE #283: measured before add_pokemon_to_bench/refresh frees the
				# hand node, so the card takes off from where the player clicked it
				# rather than from the left end of the hand.
				var bench_from := _card_rect_now(bench_card)
				add_pokemon_to_bench(bench_card)
				refresh_hand_display(false)
				
				if bench_setup_phase_active:
					selected_card_for_action = null
					display_pokemon(false)
					show_enlarged_array_selection_mode(player_hand)
				else:
					hide_selection_mode_display_main()
					await get_tree().process_frame
					await get_tree().process_frame
					var bench_texture = get_card_texture(bench_card)
					# ISSUE #20: land on the actual next bench slot (bench cards are same size, so no morph)
					var bench_loc = get_pokemon_screen_location(bench_card)
					print("ISSUE #283 FIX ACTIVE: bench placement leaves hand from ",
						bench_from.get("position", "container fallback"))
					await animate_card_a_to_b(player_hand_container, player_bench_container, 0.3,
						bench_texture, bench_from.get("size", card_scales[11]),
						bench_loc.get("size", BENCH_CARD),
						bench_loc.get("position", _ANIM_POS_SENTINEL), false,
						bench_from.get("position", _ANIM_POS_SENTINEL))
					display_pokemon(false)
					# GYM2-119 Rocket's Minefield Gym — coin flip per benched Basic from hand; tails = 20 damage
					await trainer_effects.gym2_minefield_gym_trigger(bench_card, false)
		
		"PLAY_TRAINER":
			var trainer_to_play = selected_card_for_action
			# Pre-validate that the trainer card can actually have an effect before playing it
			var validation_error = trainer_effects.validate_trainer_can_be_played(trainer_to_play, false)
			if validation_error != "":
				await show_message(validation_error)
				# ISSUE #174: DROP THE SELECTION TOO. Returning here left the card
				# still highlighted in the hand while the action button fell back to
				# "SELECT A CARD" — so the trainer looked picked and the button said
				# nothing was. clear_current_action_selection() deselects the card and
				# resets the button without leaving the hand screen, which is exactly
				# the state a refused play should land in.
				print("ISSUE #174 FIX ACTIVE: clearing selection after refused trainer play")
				clear_current_action_selection()
				return
			hide_selection_mode_display_main()
			await trainer_effects.play_trainer_card(trainer_to_play, false)
			# GYM1 — Tickling Machine / Minion of Team Rocket can force-end the player's turn
			if player_turn_force_end:
				player_turn_force_end = false
				await player_end_turn_checks()
		
		"ATTACH_ENERGY":
			start_energy_attachment()
		
		"EVOLVE":
			start_evolution()
		
		_:
			print("Unknown action: ", action_type)

# When the cancel button is clicked, hide everthing in card selection mode and show main screen again
func cancel_button_pressed_hide_selection_mode() -> void:

	# ISSUE #80: close the single-card preview (view-only) back to the board.
	if pokemon_preview_active:
		pokemon_preview_active = false
		pokemon_preview_target = null
		hide_selection_mode_display_main()
		return

	# ISSUE #80: close the bench VIEW back to the board.
	if bench_view_active:
		bench_view_active = false
		hide_selection_mode_display_main()
		return

		# If we're in attach mode, cancel the energy attachment
	if card_attach_mode_active:
		print("Energy attachment cancelled")
		
		# Clear the energy card awaiting target (it stays in the hand)
		energy_card_awaiting_target = null
		
		# Exit attach mode
		card_attach_mode_active = false
		
		# Return to main UI screen
		hide_selection_mode_display_main()
		return
	
	elif evolution_mode_active:
		print("Evolution cancelled")
		evolution_card_awaiting_target = null
		evolution_mode_active = false
		hide_selection_mode_display_main()
		return
	
	elif retreat_mode_active:
		print("Retreat energy selection cancelled")
		retreat_mode_active = false
		retreat_energies_selected.clear()
		retreat_cost_remaining = 0
		hide_selection_mode_display_main()
		return
	
	elif retreat_bench_selection_active:
		print("Retreat bench selection cancelled")
		retreat_bench_selection_active = false
		retreat_energies_selected.clear()
		retreat_cost_remaining = 0
		hide_selection_mode_display_main()
		return
	
	# Defender/energy-discard selection cancel (ISSUE #25): emit with null so the awaiting
	# remove_one_energy returns null and the caller can refund the effect.
	elif defender_energy_discard_active:
		print("ISSUE #25 FIX ACTIVE: energy discard selection cancelled")
		selected_card_for_action = null
		defender_energy_discard_active = false
		hide_selection_mode_display_main()
		defender_energy_chosen.emit(null)
		return

	# Trainer/Power selection cancel: emit signal with null so awaiting functions can continue
	elif trainer_pokemon_selection_active:
		print("Trainer pokemon selection cancelled")
		selected_card_for_action = null
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		trainer_target_selected.emit()
		return
	
	elif trainer_deck_search_active:
		print("Trainer deck search cancelled")
		selected_card_for_action = null
		trainer_deck_search_active = false
		hide_selection_mode_display_main()
		trainer_target_selected.emit()
		return
	
	elif trainer_discard_selection_active:
		print("Trainer discard selection cancelled")
		trainer_discard_selected.clear()
		trainer_discard_selection_active = false
		hide_selection_mode_display_main()
		trainer_discard_selection_done.emit()
		return
	
	# If we were in bench setup phase, end it and draw prize cards
	elif bench_setup_phase_active:
		opponent_blocker.visible = true
		bench_setup_phase_active = false
		cancel_button.text = "Cancel"
		cancel_button.theme = theme_red
		draw_prize_cards(true)
		hide_selection_mode_display_main()

		# MATCH EFFECTS: announce this opponent's special rules at the start of each game
		if match_effects.has_any():
			await show_message("SPECIAL MATCH RULES ARE IN EFFECT!")
			for rule_line in match_effects.get_announcement_lines():
				await show_message(rule_line)

		await show_message("FLIPPING COIN TO DECIDE WHICH PLAYER GOES FIRST")
	
		var who_starts = await flip_coin()
	
		if who_starts:
			await show_message("You are going first!")
			player_start_turn_checks()
		else:
			await show_message("Opponent is going first!")
			cpu_ai.opponent_start_turn_checks()
	else:
		hide_selection_mode_display_main()

# Opens any card array in enlarged selection mode when its container is clicked
func array_container_clicked(event: InputEvent, card_array: Array) -> void:
	if event is InputEventMouseButton and event.pressed:
		# ISSUE #89 FIX: mouse-wheel notches arrive as pressed mouse buttons, so scrolling over a
		# container used to open its enlarged selection view. Scrolling is not a click.
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return
		if msgbox_container.visible or coin_container.visible: return
		if card_array.size() > 0:
			# ISSUE #80: viewing either bench is a VIEW (no "place on bench" action); clicking a card
			# in it opens a single-card preview. Only flag it when we aren't already mid-action so it
			# never hijacks a genuine bench selection (retreat/knockout/forced-switch set their own modes).
			if (card_array == player_bench or card_array == opponent_bench) and not is_pokemon_selection_mode_active():
				bench_view_active = true
			show_enlarged_array_selection_mode(card_array)

# ISSUE #80: single-card preview — show one Pokémon plus its attached energies and tools laid out as
# separate cards to its left (raised to line up), the focus card enlarged with its HP label beneath,
# and only a centred Close button. Reached by clicking a card while viewing a bench.
func show_pokemon_preview(pokemon: card_object) -> void:
	if pokemon == null:
		return
	bench_view_active = false
	pokemon_preview_active = true
	pokemon_preview_target = pokemon
	# Energies + tools first (rendered as cards to the left), focus Pokémon last.
	var display_array: Array = pokemon.attached_energies.duplicate()
	display_array.append_array(pokemon.attached_cards)
	display_array.append(pokemon)
	show_enlarged_array_selection_mode(display_array)
	header_label.text = pokemon.metadata.get("name", "").to_upper()
	var extras := pokemon.attached_energies.size() + pokemon.attached_cards.size()
	hint_label.text = (str(extras) + " attached card(s)") if extras > 0 else "No attached cards"
	action_button.visible = false
	cancel_button.visible = true
	cancel_button.text = "CLOSE"
	cancel_button.theme = theme_green
	cancel_button.offset_left = -219.0
	cancel_button.offset_right = 219.0

# Called when a card in selection mode is clicked
func this_card_clicked(clicked_card: card_object) -> void:
	# Don't allow card selection if action button is hidden (view-only mode) or messagebox is being displayed
	if msgbox_container.visible or coin_container.visible: return
	# ISSUE #80: the single-card preview is view-only — ignore clicks on the previewed/attached cards.
	if pokemon_preview_active:
		return
	# ISSUE #80: clicking a card while viewing a bench opens the single-card preview of it, instead of
	# the old behaviour of "selecting" it and showing a bogus PLACE ON BENCH button.
	if bench_view_active:
		show_pokemon_preview(clicked_card)
		return
	if not action_button.visible: return

	if card_selection_mode_enabled == true:
		
		# ATTACHMENT MODE ATTACHMENT MODE ATTACHMENT MODE ATTACHMENT MODE ATTACHMENT MODE ATTACHMENT MODE ATTACHMENT MODE
		if card_attach_mode_active:
			# In attach mode, we're selecting a target Pokemon, not performing a card action
			select_card_in_ui(clicked_card)
			
			print("Selected target Pokemon for energy attachment: ", selected_card_for_action.metadata["name"])
			
			# Update button to show it's ready to attach
			action_button.text = "ATTACH ENERGY"
			action_button.disabled = false
			action_button.theme = theme_green
			return
		
		# EVOLUTION MODE EVOLUTION MODE EVOLUTION MODE EVOLUTION MODE EVOLUTION MODE EVOLUTION MODE EVOLUTION MODE	
		elif evolution_mode_active:
			select_card_in_ui(clicked_card)
			
			print("Selected evolution target: ", selected_card_for_action.metadata["name"])
			
			action_button.text = "EVOLVE"
			action_button.disabled = false
			action_button.theme = theme_green
			return
		
		# RETREAT MODE RETREAT MODE RETREAT MODE RETREAT MODE RETREAT MODE RETREAT MODE RETREAT MODE RETREAT MODE
		elif retreat_mode_active:
			if clicked_card == player_active_pokemon:
				return
			# ISSUE #80: attached tool cards are shown on the retreat screen but are NOT part of the
			# retreat cost — only energies can be selected for discard, so ignore tool clicks.
			if clicked_card in player_active_pokemon.attached_cards:
				return

			if clicked_card in retreat_energies_selected:
				retreat_energies_selected.erase(clicked_card)
				var card_display = find_card_ui_for_object(clicked_card)
				if card_display:
					card_display.set_selected(false)
			else:
				if retreat_energies_selected.size() >= get_retreat_cost(player_active_pokemon):
					return
				retreat_energies_selected.append(clicked_card)
				var card_display = find_card_ui_for_object(clicked_card)
				if card_display:
					card_display.set_selected(true)
			
			retreat_cost_remaining = get_retreat_cost(player_active_pokemon) - retreat_energies_selected.size()
			hint_label.text = "Select " + str(retreat_cost_remaining) + " energy card(s) to discard"
			
			if retreat_cost_remaining <= 0:
				action_button.text = "DISCARD & RETREAT"
				action_button.disabled = false
				action_button.theme = theme_green
			else:
				action_button.text = str(retreat_cost_remaining) + " ENERGY REMAINING"
				action_button.disabled = true
				action_button.theme = theme_disabled
			return
		
		elif retreat_bench_selection_active or knockout_bench_selection_active:
			select_card_in_ui(clicked_card)
			
			action_button.text = "SET AS ACTIVE"
			action_button.disabled = false
			action_button.theme = theme_green
			return
		
		# FORCED SWITCH MODE
		elif forced_switch_selection_active:
			select_card_in_ui(clicked_card)
			action_button.text = "SWITCH IN"
			action_button.disabled = false
			action_button.theme = theme_green
			return
		
		# DEFENDER ENERGY DISCARD MODE
		elif defender_energy_discard_active:
			select_card_in_ui(clicked_card)
			action_button.text = "DISCARD ENERGY"
			action_button.disabled = false
			action_button.theme = theme_red
			return
		
		# ENERGY TYPE SELECTION MODE (Porygon Conversion)
		elif energy_type_selection_active:
			select_card_in_ui(clicked_card)
			action_button.text = "SELECT TYPE"
			action_button.disabled = false
			action_button.theme = theme_blue
			return
		
		# POKEDEX REORDER MODE - click cards to assign position numbers (with deselection support)
		elif trainer_reorder_active:
			if clicked_card in pokedex_reorder_result:
				# DESELECT: remove this card and shift remaining numbers
				var removed_index = pokedex_reorder_result.find(clicked_card)
				pokedex_reorder_result.erase(clicked_card)
				
				# Clear all number labels and rebuild them
				for card in pokedex_cards:
					var c_ui = find_card_ui_for_object(card)
					if c_ui:
						# Remove any child labels
						for child in c_ui.get_children():
							if child is Label:
								child.queue_free()
						if card in pokedex_reorder_result:
							var new_pos = pokedex_reorder_result.find(card) + 1
							c_ui.modulate = Color(0.6, 0.6, 0.6, 1.0)
							var num_label = Label.new()
							num_label.text = str(new_pos)
							num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
							num_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
							num_label.theme = theme_disabled
							num_label.add_theme_font_size_override("font_size", 72)
							num_label.add_theme_color_override("font_color", Color.WHITE)
							num_label.add_theme_color_override("font_outline_color", Color.BLACK)
							num_label.add_theme_constant_override("outline_size", 12)
							num_label.custom_minimum_size = c_ui.size
							num_label.size = c_ui.size
							num_label.mouse_filter = MOUSE_FILTER_IGNORE
							c_ui.add_child(num_label)
						else:
							c_ui.modulate = Color(1.0, 1.0, 1.0, 1.0)
				
				var position_num = pokedex_reorder_result.size()
				hint_label.text = str(position_num) + "/" + str(pokedex_cards.size()) + " cards ordered"
				action_button.text = str(position_num) + "/" + str(pokedex_cards.size()) + " SELECTED"
				action_button.disabled = true
				action_button.theme = theme_disabled
				return
			
			# SELECT: add card to order
			pokedex_reorder_result.append(clicked_card)
			var position_num = pokedex_reorder_result.size()
			
			# Add a number label on top of the card
			var card_ui = find_card_ui_for_object(clicked_card)
			if card_ui:
				var num_label = Label.new()
				num_label.text = str(position_num)
				num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				num_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				num_label.theme = theme_disabled
				num_label.add_theme_font_size_override("font_size", 72)
				num_label.add_theme_color_override("font_color", Color.WHITE)
				num_label.add_theme_color_override("font_outline_color", Color.BLACK)
				num_label.add_theme_constant_override("outline_size", 12)
				num_label.custom_minimum_size = card_ui.size
				num_label.size = card_ui.size
				num_label.mouse_filter = MOUSE_FILTER_IGNORE
				card_ui.add_child(num_label)
				# Dim the card to show it's been selected
				card_ui.modulate = Color(0.6, 0.6, 0.6, 1.0)
			
			hint_label.text = str(position_num) + "/" + str(pokedex_cards.size()) + " cards ordered"
			
			if pokedex_reorder_result.size() >= pokedex_cards.size():
				# All cards numbered - enable confirm button
				action_button.text = "CONFIRM ORDER"
				action_button.disabled = false
				action_button.theme = theme_green
			else:
				action_button.text = str(position_num) + "/" + str(pokedex_cards.size()) + " SELECTED"
				action_button.disabled = true
				action_button.theme = theme_disabled
			return
		
		# TRAINER DISCARD SELECTION MODE - click to toggle cards like retreat energy
		elif trainer_discard_selection_active:
			# Toggle this card in/out of the selection
			if clicked_card in trainer_discard_selected:
				trainer_discard_selected.erase(clicked_card)
				var card_display = find_card_ui_for_object(clicked_card)
				if card_display:
					card_display.set_selected(false)
			else:
				if trainer_discard_selected.size() >= trainer_discard_cards_needed:
					return
				trainer_discard_selected.append(clicked_card)
				var card_display = find_card_ui_for_object(clicked_card)
				if card_display:
					card_display.set_selected(true)
			
			var remaining = trainer_discard_cards_needed - trainer_discard_selected.size()
			hint_label.text = str(trainer_discard_selected.size()) + "/" + str(trainer_discard_cards_needed) + " selected"
			
			if remaining <= 0:
				action_button.text = "CONFIRM"
				action_button.disabled = false
				action_button.theme = theme_green
			else:
				action_button.text = str(remaining) + " MORE"
				action_button.disabled = true
				action_button.theme = theme_disabled
			return
		
		# TRAINER POKEMON SELECTION MODE
		elif trainer_pokemon_selection_active or trainer_deck_search_active:
			select_card_in_ui(clicked_card)
			action_button.disabled = false
			action_button.theme = theme_green
			return

		# Normal card selection mode (not in attach mode)
		select_card_in_ui(clicked_card)
		
		print("Selected card for action: ", selected_card_for_action.metadata["name"])
		
		# Update the button text and state based on the selected card
		update_action_button()
			
	else:
		selected_card_for_action = null

######################################################################################################################################################
########################################################### USER INPUT ON CLICK FUNCTIONS ############################################################
######################################################################################################################################################

#                       ######  ##   ##  ####    ##
#                      ##       ##   ##  ## ##   ##
#                      ##       ##   ##  ##  ##  ##
#                      ##       ##   ##  ##   ## ##
#                      ##       #######  ##    ####

######################################################################################################################################################
####################################################### START OF MAIN GAME RUNNING FUNCTIONS #########################################################
	
# ISSUE #77/#78: clear ALL currently-selected cards for the in-progress action — a single-select
# (a hand/bench card) OR a multi-select mode (retreat energy discard, trainer discard, Pokédex
# reorder). Stops each card's selection animation (set_selected(false) / un-dim / strip number
# labels), empties the cached selection arrays, and resets the action button + hint back to the
# "nothing selected yet" state of the CURRENT mode — WITHOUT cancelling the mode, so the player can
# immediately start re-selecting. Triggered by clicking a blank space OR right-clicking (#78).
func clear_current_action_selection() -> void:
	# ISSUE #80: the bench view and single-card preview are view-only — nothing is "selected", so a
	# blank-space / right-click has nothing to clear (and must not disturb the view).
	if pokemon_preview_active or bench_view_active:
		return

	# ── Multi-select: retreat energy discard (choose N energy to pay the retreat cost) ──
	if retreat_mode_active:
		for c in retreat_energies_selected:
			var ui = find_card_ui_for_object(c)
			if ui: ui.set_selected(false)
		retreat_energies_selected.clear()
		var cost = get_retreat_cost(player_active_pokemon)
		retreat_cost_remaining = cost
		hint_label.text = "Select " + str(cost) + " energy card(s) to discard"
		action_button.text = str(cost) + " ENERGY REMAINING"
		action_button.disabled = true
		action_button.theme = theme_disabled
		return

	# ── Multi-select: trainer discard (choose N cards to discard) ──
	if trainer_discard_selection_active:
		for c in trainer_discard_selected:
			var ui = find_card_ui_for_object(c)
			if ui: ui.set_selected(false)
		trainer_discard_selected.clear()
		hint_label.text = "0/" + str(trainer_discard_cards_needed) + " selected"
		action_button.text = str(trainer_discard_cards_needed) + " MORE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		return

	# ── Multi-select: Pokédex reorder (assign an order number to each card) ──
	if trainer_reorder_active:
		for card in pokedex_cards:
			var c_ui = find_card_ui_for_object(card)
			if c_ui:
				for child in c_ui.get_children():
					if child is Label:
						child.queue_free()
				c_ui.modulate = Color(1.0, 1.0, 1.0, 1.0)
		pokedex_reorder_result.clear()
		hint_label.text = "0/" + str(pokedex_cards.size()) + " cards ordered"
		action_button.text = "0/" + str(pokedex_cards.size()) + " SELECTED"
		action_button.disabled = true
		action_button.theme = theme_disabled
		return

	# ── Single-select modes (hand card, attach/evolve target, bench/forced-switch pick, etc.) ──
	if selected_card_for_action != null:
		var card_ui = find_card_ui_for_object(selected_card_for_action)
		if card_ui:
			card_ui.set_selected(false)
	selected_card_for_action = null
	update_action_button()

# ==============================================================================
# CARD ZOOM - hold Shift to enlarge whatever the mouse is over
# ==============================================================================

# Follows the mouse for as long as the key is held.
func _process(_delta: float) -> void:
	if not zoom_held:
		return
	# Safety net: alt-tabbing with the key down swallows the release event, which would
	# otherwise strand a full-screen black overlay over the match with no way to shift it.
	if not UIInput.is_zoom_held():
		zoom_held = false
		_hide_card_zoom()
		return
	_refresh_card_zoom()


# Swaps the preview to whatever card the mouse has moved onto.
# Deliberately sticky, matching the deck builder: it only ever changes to ANOTHER card,
# never back to nothing. Sliding between two cards crosses a few pixels of empty table,
# and tearing the overlay down and rebuilding it on every crossing flashes the board
# through for a frame. Releasing the key is the only thing that closes the preview.
func _refresh_card_zoom() -> void:
	var card_node := _get_hovered_card_node()
	if card_node == zoomed_card_node:
		return
	if card_node == null:
		return
	_show_card_zoom(card_node)


# Returns the card display under the mouse, or null if there isn't one the player may see.
func _get_hovered_card_node() -> CardDisplay:
	# The precise answer, for when the mouse is genuinely over a card Control. It may be over a
	# wrapper or a label sitting on the card rather than the card itself, so walk up a few levels.
	var node: Node = get_viewport().gui_get_hovered_control()
	for i in range(6):
		if node == null:
			break
		if node is CardDisplay:
			var card := node as CardDisplay
			return card if _card_is_previewable(card) else null
		node = node.get_parent()
	# Nothing found, which on this screen is the normal case rather than the exception: the match
	# lays full-screen transparent ColorRects over the whole board — the message box, the
	# opponent-turn blocker, the animation blocker, the played-trainer overlay — and each of them
	# swallows GUI hover for every pixel behind it. Reading a card WHILE a message is up is the
	# entire point of the feature, so fall back to hit-testing the card rects directly. This is the
	# same test Card_Image_Loader already uses to decide whether a click landed on a card
	# (is_visible_in_tree + get_global_rect), so anything clickable is also enlargeable — including
	# cards that ignore the mouse entirely, like the energies and tools stacked behind a bench
	# Pokemon and the top card of a discard pile.
	return _find_card_under_mouse(self)


# Deepest-last search for the card the cursor is over.
func _find_card_under_mouse(root_node: Node) -> CardDisplay:
	var mouse_pos := get_global_mouse_position()
	var topmost: CardDisplay = null
	for node in _collect_card_displays(root_node, []):
		var card := node as CardDisplay
		if not card.is_visible_in_tree():
			continue                      # hidden, or inside a container that is
		if not card.get_global_rect().has_point(mouse_pos):
			continue
		# Keep the LAST match rather than returning the first: siblings draw in child order and
		# later branches of the tree draw over earlier ones, so the last hit is the one on top.
		topmost = card
	# Face-down cards are counted in that search and only rejected here, at the end. They are
	# still what the mouse is on — so whatever is lying behind one stays hidden rather than
	# being previewed straight through it.
	return topmost if _card_is_previewable(topmost) else null


func _collect_card_displays(node: Node, out: Array) -> Array:
	for child in node.get_children():
		if child is CardDisplay:
			out.append(child)
		_collect_card_displays(child, out)
	return out


# A card can be enlarged only if it is on screen and face up. Face-down covers the
# opponent's hand and both players' prize cards; an effect that reveals one redraws it
# face up, so it becomes previewable at that point with no special casing here.
func _card_is_previewable(node: CardDisplay) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not node.is_visible_in_tree():
		return false
	if node.is_face_down:
		return false
	return node.card_uid != null and str(node.card_uid) != ""


# Builds the preview overlay, or re-points it at another card if one is already up.
func _show_card_zoom(card_node: CardDisplay) -> void:
	# Claimed before anything can fail below. _process re-runs this every frame while the key is
	# held, so a card whose data is missing would otherwise re-fail — and re-log — forever.
	zoomed_card_node = card_node

	var uid := str(card_node.card_uid)
	if uid.split("-").size() != 2:
		return

	# An overlay is already up and the mouse has slid onto another card - hand the new card to
	# the live panel. Freeing and rebuilding the CanvasLayer lets the board flash through for a frame.
	if is_zoomed and detail_panel != null and is_instance_valid(detail_panel):
		detail_panel.show_card(uid)
		return

	is_zoomed = true
	CardDisplay.zoom_active = true   # stops the card nodes themselves reacting to clicks

	# Layer 150 clears everything the match draws, including the forfeit dialog.
	zoom_overlay = CanvasLayer.new()
	zoom_overlay.layer = 150
	add_child(zoom_overlay)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, ZOOM_BACKDROP_ALPHA)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	# Must never absorb hover, or gui_get_hovered_control() would report the backdrop
	# instead of the board underneath and the preview would freeze on its first card.
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.add_child(backdrop)

	detail_panel = CardDetailPanel.new()
	zoom_overlay.add_child(detail_panel)
	detail_panel.show_card(uid)


func _hide_card_zoom() -> void:
	CardDisplay.zoom_active = false
	if not is_zoomed:
		return
	is_zoomed = false
	zoomed_card_node = null
	detail_panel = null
	if zoom_overlay != null:
		zoom_overlay.queue_free()
		zoom_overlay = null


# Both flags are static, so a match left while the preview was held or the log was
# open would carry a permanent "clicks are blocked" state into the next one.
func _exit_tree() -> void:
	CardDisplay.zoom_active = false
	CardDisplay.input_blocked = false


func _input(event: InputEvent) -> void:

	# -- Hold Shift to enlarge the card under the mouse -------------------------
	# First branch in the function on purpose, so a card can be read at ANY moment -
	# including with a message box up, which is exactly when you want to look at the
	# card the opponent just played. Shift is not the accept key, so opening a preview
	# never competes with the Space/Enter that dismisses the message afterwards.
	# `not match_log_open` so Shift can't open a card preview underneath the log —
	# the log's own swallow branch sits below this one, and this branch is
	# deliberately first. The RELEASE is still processed unconditionally, so a
	# Shift held across the log opening can't strand zoom_held at true.
	if UIInput.is_zoom_start(event) and not match_log_open:
		zoom_held = true
		_refresh_card_zoom()
		return
	if UIInput.is_zoom_end(event):
		zoom_held = false
		_hide_card_zoom()
		return

	# While a card is enlarged the preview owns the screen: every other input is
	# swallowed, so a click aimed at closing it cannot acknowledge the message box,
	# select a card or open the forfeit prompt behind the player's back and carry the
	# match on underneath something they are still reading. Releasing Shift is the only
	# way out. Card nodes are deeper in the tree, so their own _input runs before this
	# one and is blocked separately - see CardDisplay.zoom_active.
	if is_zoomed:
		get_viewport().set_input_as_handled()
		return

	# -- Caps Lock opens the match message log ---------------------------------
	# Placed after the preview branches so the log can't open underneath an open
	# card preview, and BEFORE the message-box branch below so opening the log to
	# re-read a message doesn't also dismiss the message you opened it for.
	if UIInput.is_log_toggle(event):
		_toggle_match_log()
		get_viewport().set_input_as_handled()
		return

	# While the log is open it owns the screen, exactly like the card preview
	# above: the board is frozen and every event is swallowed so a click or a
	# stray Space can't advance a message, pick a card or open the forfeit prompt
	# behind something the player is still reading. Escape closes the log rather
	# than falling through to the forfeit branch further down.
	#
	# Scrolling is driven by hand rather than left to the ScrollContainer -- see
	# the note in Match_Log_Panel.gd. That is what makes the wheel work with the
	# cursor anywhere on screen instead of only over the panel.
	if match_log_open:
		if UIInput.is_cancel(event):
			_close_match_log()
			get_viewport().set_input_as_handled()
			return
		if _match_log_panel != null and is_instance_valid(_match_log_panel):
			_match_log_panel.handle_scroll_input(event)
		get_viewport().set_input_as_handled()
		return

	# While the forfeit confirmation is up it owns the screen: swallow all gameplay input so
	# a click can't acknowledge a message box, cancel a mode or move a card underneath it.
	# The dialog's own buttons are Controls, and GUI input is processed AFTER _input(), so
	# returning here still lets Forfeit/Cancel receive their clicks. ESC closes it, matching
	# the "escape backs out" behaviour used everywhere else in the game.
	if forfeit_dialog != null and is_instance_valid(forfeit_dialog):
		# Same yes/no key rule as every other prompt in the game: accept confirms,
		# cancel backs out. Note the dialog is OPENED by Escape, so Escape-then-
		# Space forfeits the match — see the comment on the yes/no branch below.
		if UIInput.is_cancel(event):
			_close_forfeit_dialog()
			get_viewport().set_input_as_handled()
		elif UIInput.is_accept(event):
			get_viewport().set_input_as_handled()
			_on_forfeit_confirmed()
		return

	# ── Message box: Space / Enter / Escape all advance it ──────────────────────
	# Mirrors the mouse handler further down (any click acknowledges), so a message
	# can be read through without touching the mouse. This sits ABOVE the Escape
	# branch below because that one returns unconditionally — Escape would
	# otherwise be swallowed while a message is up.
	# The event is consumed so Space/Enter can't also fire "ui_accept" on whatever
	# button happens to hold focus behind the box.
	if msgbox_container.visible and UIInput.is_advance(event):
		message_acknowledged.emit()
		get_viewport().set_input_as_handled()
		return

	# ── In-match Yes/No questions ───────────────────────────────────────────────
	# These are drawn as the selection-mode action/cancel buttons rather than a
	# message box (see Trainer_Effects.gym1_prompt_yes_no, ~100 call sites), so they
	# need their own branch: accept presses the YES button, cancel presses the NO
	# button. Deliberately gated on yes_no_prompt_active alone — ordinary selection
	# modes keep their existing mouse-only handling, so Space can't confirm a
	# half-made card selection and Escape still opens the forfeit prompt there.
	if yes_no_prompt_active:
		if UIInput.is_accept(event):
			if action_button.visible and not action_button.disabled:
				get_viewport().set_input_as_handled()
				action_button.pressed.emit()
			return
		if UIInput.is_cancel(event):
			if cancel_button.visible and not cancel_button.disabled:
				get_viewport().set_input_as_handled()
				cancel_button.pressed.emit()
			return

	# ESC = forfeit the match, behind a confirmation. This used to call end_game() directly,
	# so one stray press of the key that backs out of every menu in the game instantly threw
	# the match. Three guards beyond the prompt itself:
	#   - game_is_over: the result is already decided, there is nothing left to forfeit.
	#   - msgbox visible: game_end_logic() awaits its own show_message(), and the pending
	#     await belonging to whatever is on screen right now would never be resolved.
	#   - coin flip visible: the flip is an input-blocking overlay driven by a tween, so the
	#     forfeit's message box would have to fight it for the screen and the click.
	# The msgbox/coin pair is the same "input is blocked right now" test the mouse handlers
	# below already use.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not game_is_over and not msgbox_container.visible and not coin_container.visible:
			_show_forfeit_dialog()
		return

	# Dev cheat keys — 9 = instant win, 0 = instant lose, D = both draw, S = both shuffle,
	# E = both attach energy, H = heal actives, B = heal bench.
	# Gated on DebugMode (Debug_Mode.gd) so a release build can't throw or steal a match with
	# a single keypress. In the editor debug mode is always on, so this changes nothing day to day.
	if DebugMode.is_enabled() and event is InputEventKey and event.pressed and not game_is_over:
		if event.keycode == KEY_9:
			game_end_logic(false)   # player wins
		elif event.keycode == KEY_0:
			game_end_logic(true)    # player loses
		elif event.keycode == KEY_D:
			debug_key_both_draw()
		elif event.keycode == KEY_S:
			debug_key_both_shuffle_hand()
		elif event.keycode == KEY_E:
			debug_key_both_attach_energy()
		elif event.keycode == KEY_H:
			debug_key_heal_actives()
		elif event.keycode == KEY_B:
			debug_key_heal_bench()
			
	if event is InputEventMouseButton and event.pressed:

		# ISSUE #89 FIX: the mouse wheel arrives as an InputEventMouseButton with pressed == true, so
		# every notch of scrolling was being treated as a click — it acknowledged message boxes and,
		# whenever the cursor wasn't over a card, cleared the player's in-progress selection. That made
		# a hand of 8+ cards (which goes into a scroll box) impossible to scroll through without losing
		# the selected card. Scrolling is not a click: drop wheel events here and let the ScrollContainer
		# under the cursor do its job.
		# The MIDDLE button is dropped by the same test. It has no job in a match and was landing here
		# as an ordinary left-click — and since it is the same physical control as the wheel, a firm
		# scroll press was throwing away a card selection. UIInput.is_inert_mouse_button() is the one
		# definition of "this mouse button does nothing", shared with the card nodes.
		if UIInput.is_inert_mouse_button(event):
			return

		if msgbox_container.visible:
			message_acknowledged.emit()
			get_viewport().set_input_as_handled()
			return

		# ISSUE #88 FIX: right-click is the "back/cancel" button (it will map to controller B/O later).
		# When a Cancel button is on screen, right-clicking anywhere presses it — the same as clicking
		# the button itself, whatever its current label ("Cancel", "Done", "CLOSE"). With no Cancel
		# button up there is nothing to back out of, so it falls back to ISSUE #78's behaviour: treat it
		# as a blank-space click, clearing every selected card for the in-progress action without
		# cancelling the mode.
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if cancel_button.visible and not cancel_button.disabled:
				cancel_button.pressed.emit()
			else:
				clear_current_action_selection()
			get_viewport().set_input_as_handled()
			return

		var mouse_pos = get_global_mouse_position()

		# Check if click is on the cancel or action button - if so, ignore
		if cancel_button.visible and cancel_button.get_global_rect().has_point(mouse_pos):
			return
		if action_button.visible and action_button.get_global_rect().has_point(mouse_pos):
			return

		# Check if mouse is over any card in the visible containers
		var clicked_on_card = false

		# NEW: Only check small selection container if it's visible
		if small_selection_container.visible:
			for card_ui in small_selection_container.get_children():
				if card_ui.get_global_rect().has_point(mouse_pos) and card_selection_mode_enabled == true:
					clicked_on_card = true
					print("the game thinks a card has been clicked")
					break

		# NEW: Only check large selection container if it's visible
		if selection_scroller.visible:
			for card_ui in large_selection_container.get_children():
				if card_ui.get_global_rect().has_point(mouse_pos) and card_selection_mode_enabled == true:
					clicked_on_card = true
					break

		# ISSUE #77: clicking a blank space clears ALL selected cards for the current action (single
		# OR multi-select), resetting to the "nothing selected" state without cancelling the mode.
		# Previously multi-select modes either did a partial single-card clear (leaving cards visually
		# selected while the button wrongly reset to "Select A Card") or bailed without clearing.
		if not clicked_on_card:
			clear_current_action_selection()


# ── Dev debug cheat keys (in-match) ──────────────────────────────────────────────────────
# Only reachable while DebugMode.is_enabled() — see the key handling in _input() above.
# D: both players draw 1 card.
func debug_key_both_draw() -> void:
	await card_ops.draw_n(false, 1)
	if _should_bail(): return
	await card_ops.draw_n(true, 1)
	if _should_bail(): return

# S: both players shuffle their hand into their deck and draw back the same number of cards.
func debug_key_both_shuffle_hand() -> void:
	for is_opponent in [false, true]:
		var hand = opponent_hand if is_opponent else player_hand
		var deck = opponent_deck if is_opponent else player_deck
		var n = hand.size()
		for c in hand.duplicate():
			c.current_location = "deck"
			deck.append(c)
		hand.clear()
		deck.shuffle()
		await card_ops.draw_n(is_opponent, n)
		if _should_bail(): return

# E: attach an energy card of each active Pokemon's own type to that Pokemon (searched from its owner's deck).
func debug_key_both_attach_energy() -> void:
	for is_opponent in [false, true]:
		var active = opponent_active_pokemon if is_opponent else player_active_pokemon
		if active == null:
			continue
		var types = active.metadata.get("types", [])
		if types.is_empty():
			continue
		var energy_type = types[0]
		var deck = opponent_deck if is_opponent else player_deck
		var pool = deck.filter(func(c): return c.metadata.get("supertype", "") == "Energy" and energy_type in get_energy_provided_by_card(c))
		if pool.is_empty():
			deck.shuffle()
			continue
		var e = pool[0]
		deck.erase(e)
		e.current_location = "attached"
		active.attached_energies.append(e)
		deck.shuffle()
		display_active_pokemon_energies(is_opponent)
		update_deck_icon(is_opponent)
		await play_energy_attached_effect(active, e)
		if _should_bail(): return

# H: fully heal both active Pokemon.
func debug_key_heal_actives() -> void:
	if player_active_pokemon != null:
		await card_ops.heal_pokemon(player_active_pokemon, player_active_pokemon.get_max_hp(), false)
		if _should_bail(): return
	if opponent_active_pokemon != null:
		await card_ops.heal_pokemon(opponent_active_pokemon, opponent_active_pokemon.get_max_hp(), true)
		if _should_bail(): return

# B: fully heal all benched Pokemon on both sides.
func debug_key_heal_bench() -> void:
	for p in player_bench:
		await card_ops.heal_pokemon(p, p.get_max_hp(), false)
		if _should_bail(): return
	for p in opponent_bench:
		await card_ops.heal_pokemon(p, p.get_max_hp(), true)
		if _should_bail(): return

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Chrome and board geometry first: everything below draws into the positions
	# this sets, and the old scrolling background is freed here.
	_build_board_layout()

	# ISSUE #34: pick up the player's Options rule choices for this match.
	burn_rules = GameState.burn_rule_setting
	confusion_rules = GameState.confusion_rule_setting

	# Instantiate helper scripts
	attack_effects = Node.new()
	attack_effects.set_script(preload("res://Scripts/Main_Match_Gameplay_Scripts/Attack_Effects.gd"))
	add_child(attack_effects)
	attack_effects.main = self
	
	trainer_effects = Node.new()
	trainer_effects.set_script(preload("res://Scripts/Main_Match_Gameplay_Scripts/Trainer_Effects.gd"))
	add_child(trainer_effects)
	trainer_effects.main = self
	
	cpu_ai = Node.new()
	cpu_ai.set_script(preload("res://Scripts/Main_Match_Gameplay_Scripts/CPU_AI.gd"))
	add_child(cpu_ai)
	cpu_ai.main = self
	
	powers_and_bodies = Node.new()
	powers_and_bodies.set_script(preload("res://Scripts/Main_Match_Gameplay_Scripts/Powers_And_Bodies_Effects.gd"))
	add_child(powers_and_bodies)
	powers_and_bodies.main = self
	
	special_energy_effects = Node.new()
	special_energy_effects.set_script(preload("res://Scripts/Main_Match_Gameplay_Scripts/Special_Energy_Effects.gd"))
	add_child(special_energy_effects)
	special_energy_effects.main = self

	card_ops = Node.new()
	card_ops.set_script(preload("res://Scripts/Main_Match_Gameplay_Scripts/Card_Ops.gd"))
	add_child(card_ops)
	card_ops.main = self

	match_effects = Node.new()
	match_effects.set_script(preload("res://Scripts/Main_Match_Gameplay_Scripts/Match_Effects.gd"))
	add_child(match_effects)
	match_effects.main = self

	# Register all on-damage and pre-KO power hooks, then let attack_effects add its own.
	powers_and_bodies._register_all_power_hooks()
	attack_effects.register_on_damage_hooks(powers_and_bodies)

	var opponent_name = GameState.current_opponent_name
	
	if GameDataManager.player_data.has("coin"):
		var coin_loaded_text = GameDataManager.player_data["coin"]
		var _coin_tex = load("res://Image_Assets/Coins/" + coin_loaded_text + ".png")
		if _coin_tex != null:
			tex_heads = _coin_tex
		
	# ISSUE #288: 0.5 -> 1.0, the same doubling the intro, the outro and the
	# best-of-three tracker got. This is the "intro to main match" half of it.
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, MATCH_FADE_IN_TIME)
	print("ISSUE #288 FIX ACTIVE: match board fades in over ", MATCH_FADE_IN_TIME, "s")
	
	# Connect all the signals so that when parts of the UI are clicked by mouse they can perform actions
	player_bench_container.gui_input.connect(array_container_clicked.bind(player_bench))
	opponent_bench_container.gui_input.connect(array_container_clicked.bind(opponent_bench))
	player_prize_container.gui_input.connect(array_container_clicked.bind(player_prize_cards))
	opponent_prize_container.gui_input.connect(array_container_clicked.bind(opponent_prize_cards))
	player_discard_icon.gui_input.connect(array_container_clicked.bind(player_discard_pile))
	opponent_discard_icon.gui_input.connect(array_container_clicked.bind(opponent_discard_pile))

	cancel_button.pressed.connect(cancel_button_pressed_hide_selection_mode)
	action_button.pressed.connect(action_button_pressed_perform_action)
	attack_buttons_container.get_node("cancel_attack_mode_button").pressed.connect(hide_attack_buttons)
	# ATTACK / POWER / RETREAT are retired: those are rows on the Pokemon now.
	# _build_board_layout() hid the buttons and moved End Turn onto the footer, so
	# it is connected through the reference the layout kept.
	if _end_turn_btn != null and is_instance_valid(_end_turn_btn):
		# ISSUE #217: "End turn pressed = buttons disabled". The turn is committed
		# the instant it is pressed, so the rows and the button itself go dead here
		# rather than waiting for the state change to propagate.
		_end_turn_btn.pressed.connect(_on_end_turn_pressed)
	attack_buttons_container.visible = false
	
	
	


	opponent_deck_name = GameState.current_opponent_deck
	load_opponent_data_by_name(GameState.current_opponent_name)

	# Parse this opponent's match-wide rule modifiers (must happen before setup_player —
	# opening_hand_size and max_hp_modifier act during setup)
	match_effects.initialize(opponent_data)

	# Load the opponent's coin texture for "opponent flips" animations.
	# Falls back to the player's coin (tex_heads) at flip time if absent.
	var _opp_coin_name: String = opponent_data.get("coin_reward", "")
	if _opp_coin_name != "":
		var _opp_tex = load("res://Image_Assets/Coins/" + _opp_coin_name + ".png")
		if _opp_tex != null:
			tex_opp_heads = _opp_tex

	# Read prize card count from opponent JSON (default 6 if not specified)
	amount_of_prize_cards = int(opponent_data.get("prize_cards", 6))
	
	play_opponent_music()

	# Load the player's deck name from their save data
	var pfile = FileAccess.open("user://Player_Current_Data.json", FileAccess.READ)
	var pdata = JSON.parse_string(pfile.get_as_text())
	pfile.close()
	player_deck_name = pdata["deck"]
	# TEMP TESTING: T-key TEST match — player draws from the "TEST" deck, and the
	# opponent's hand + prize cards are shown face-up for inspection.
	if GameState.test_match_mode:
		player_deck_name = "TEST"
		hide_hidden_cards = false
		# ISSUE #5 FIX ACTIVE: tint the input blockers a pale red during TEST matches so gaps in
		# their coverage (e.g. areas that should be unclickable but aren't) are visible for
		# debugging. Normal matches keep them fully transparent. Kept at 20% alpha on a pale
		# (not saturated) red so a blocker appearing mid-match doesn't flash the whole screen.
		var debug_blocker_color = Color(1.0, 0.55, 0.55, 0.2)
		opponent_blocker.color = debug_blocker_color
		animation_blocker.color = debug_blocker_color
		buttons_only_blocker.color = debug_blocker_color

	# Load sleeve textures for player and opponent
	player_sleeve_small = _resolve_sleeve_path(pdata.get("sleeve", "default"), true)
	opponent_sleeve_small = _resolve_sleeve_path(opponent_data.get("sleeve", ""), true)
	card_back_texture = load(player_sleeve_small)
	opponent_card_back_texture = load(opponent_sleeve_small)
	player_sleeve_border_color = _derive_sleeve_border_color(card_back_texture)
	opponent_sleeve_border_color = _derive_sleeve_border_color(opponent_card_back_texture)

	# BEGIN THE GAME SETUP
	setup_player()
	setup_opponent(opponent_deck_name)

	# MATCH EFFECT: max_hp_modifier — shift every pokemon's max HP for the whole game.
	# Applied to deck + hand per side (prizes are drawn from the deck later, so this covers all cards).
	apply_max_hp_modifier_match_effect()
	
	# Player hand and opponent hand have to be connected after the intiial setup to prevent bugs on clicking
	player_hand_container.gui_input.connect(array_container_clicked.bind(player_hand))
	opponent_hand_container.gui_input.connect(array_container_clicked.bind(opponent_hand))
	
	cpu_ai.opponent_setup_pokemon_from_hand()
	draw_prize_cards(false)
	update_action_button()
	
	update_deck_icon(false)
	update_deck_icon(true)
	
	show_enlarged_array_selection_mode(player_hand)
	display_pokemon(false)
	
######################################################## END OF MAIN GAME RUNNING FUNCTIONS ##########################################################
######################################################################################################################################################

######################################################################################################################################################			
################################################################# END OF FUNCTIONS ###################################################################
######################################################################################################################################################
