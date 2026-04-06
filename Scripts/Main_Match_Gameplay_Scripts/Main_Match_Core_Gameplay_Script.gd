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
		or buzzap_mode_active or trainer_bench_token_discard_active)


# Fix 1: Returns cached card array for a set prefix
func get_set_cards(set_prefix: String) -> Array:
	if set_prefix in _set_metadata_cache:
		return _set_metadata_cache[set_prefix]
	return []

func _should_bail() -> bool:
	return game_is_over or not is_inside_tree()

# TESTING - There are different rulesets for burn and confusion depending on what generation/set is being played.
# Additionally I personally felt base set confusion retreat rule is horrendous, so I have created a personal rule that doesn't give free retreat but doesn't force discard then coin flip
var burn_rules: String = "base_set_burn_rules" # "base_set_burn_rules" or "modern_era_burn_rules"
var confusion_rules: String = "base_set_confusion_rules" # "base_set_confusion_rules" or "fairer_confusion_rules" or "modern_era_confusion_rules"

# Customisable in game textures
# Load coin textures
var tex_heads = load("res://Image_Assets/Coins/coin_pikachu_gold_1.png")
var tex_tails = load("res://Image_Assets/Coins/coin_back_basic.png")

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
var knockout_bench_selection_active: bool = false

var match_just_started_basic_pokemon_required = true
var bench_setup_phase_active = false

var player_energy_played_this_turn: bool = false
var opponent_energy_played_this_turn: bool = false

var energy_card_awaiting_target: card_object = null  # Stores the energy card while selecting its target
var card_attach_mode_active: bool = false

var evolution_card_awaiting_target: card_object = null
var evolution_mode_active: bool = false

var opponents_turn_active: bool = false

var retreat_mode_active: bool = false
var retreat_bench_selection_active: bool = false
var retreat_energies_selected: Array = []
var retreat_cost_remaining: int = 0
var player_retreat_disabled: bool = false
var opponent_retreat_disabled: bool = false
var player_retreated_this_turn: bool = false
var opponent_retreated_this_turn: bool = false

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
var trainer_energy_selection_active: bool = false
var trainer_reorder_active: bool = false
var trainer_bench_token_discard_active: bool = false

# Pokedex reorder tracking
var pokedex_cards: Array = []
var pokedex_reorder_result: Array = []

# Stadium zone placeholder (future-proofing)
var current_stadium_card: card_object = null

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

# PRELOADED RESOURCES
var theme_disabled = preload("res://UI_Themes/kenneyUI.tres")
var theme_green = preload("res://UI_Themes/kenneyUI-green.tres")
var theme_blue = preload("res://UI_Themes/kenneyUI-blue.tres")
var theme_red = preload("res://UI_Themes/kenneyUI-red.tres")
var card_display_script = preload("res://Scripts/Global_Scripts/Card_Image_Loader_Script.gd")
var card_back_texture = preload("res://Image_Assets/Card_Backs_And_Decks/cardbacksmall.png")

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
@onready var msgbox_texture = $messagebox_container/messagebox_texture
@onready var msgbox_label = $messagebox_container/messagebox_text_label
@onready var coin_container = $coin_flip_container
@onready var coin_texture = $coin_flip_container/coin_flip_texture
@onready var opponent_blocker = $opponent_turn_input_blocker
@onready var animation_blocker = $animation_input_blocker
@onready var buttons_only_blocker = $allow_buttons_only_blocker
@onready var trainer_block_container = $trainer_block_screen_container
@onready var played_trainer_container = $trainer_block_screen_container/played_trainer_card_container
@onready var player_attached_cards_container = $ACTIVE_POKEMON/PLAYER/player_active_pokemon_attached_cards
@onready var opponent_attached_cards_container = $ACTIVE_POKEMON/OPPONENT/opponent_active_pokemon_attached_cards

# QUICK REFERENCE VECTORS JUST USED FOR EASY SWAPPING OF SIZES FOR DEVELOPMENT
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
	
	var should_hide = hide_hidden_cards and (card_array == opponent_hand or card_array == player_prize_cards or card_array == opponent_prize_cards)
	
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
		display_hand_cards_array(card_array, large_selection_container, card_scales[5], should_hide)
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
		
		display_hand_cards_array(card_array, small_selection_container, card_size, should_hide)

# Both the cancel button and action button will hide selection mode so function is vaguely named for both actions
func hide_selection_mode_display_main() -> void:
	
	if selected_card_for_action != null:
		var card_ui = find_card_ui_for_object(selected_card_for_action)
		if card_ui:
			card_ui.set_selected(false)
	
	# End card selection mode and clear any selected card to prevent errors
	card_selection_mode_enabled = false
	selected_card_for_action = null  
	update_action_button()  
	
	# Hide the enlarged selection mode cards
	small_selection_container.visible = false
	selection_scroller.visible = false
	large_selection_container.visible = false
	
	# Hide the buttons
	cancel_button.visible = false
	action_button.visible = false
	
	# Show the player and opponents hands
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
func display_hand_cards_array(hand: Array, hand_container, card_size: Vector2, face_down: bool = false, max_hand_width: float = 1300.0, max_before_overlap: int = 12):
	
	# Clear existing cards from container to prevent stale entries when cards leave or enter the hand
	for child in hand_container.get_children():
		child.queue_free()
		
	if hand_container is HBoxContainer:
		var is_inside_scroller = hand_container.get_parent() is ScrollContainer
		if not is_inside_scroller and hand.size() > max_before_overlap:
			var card_width = card_size.x
			var n = hand.size()
			var sep = (max_hand_width - (n * card_width)) / (n - 1)
			hand_container.add_theme_constant_override("separation", int(sep))
		else:
			hand_container.add_theme_constant_override("separation", 3)
	
	# Determine if we are in a pokemon selection mode.
	var is_bench_view = (hand == player_bench or hand == opponent_bench)
	var is_pokemon_selection_mode = is_bench_view or is_pokemon_selection_mode_active()
	
	# Draw all cards in the hand
	for index in range(hand.size()):
		var this_card_in_hand = hand[index]
		
		var loc = this_card_in_hand.current_location
		var card_is_in_play = (loc == "bench" or loc == "active")
		var is_displayed_pokemon = is_pokemon_selection_mode and not face_down and this_card_in_hand.metadata.has("hp")
		var is_active_slot = is_pokemon_selection_mode and index == hand.size() - 1 and this_card_in_hand.current_location == "active"
		
		if is_displayed_pokemon:
			# Active pokemon shown 1.05x (halved from 1.1x as per requirement).
			var display_size = Vector2(card_size.x * 1.05, card_size.y * 1.05) if is_active_slot else card_size
			var show_hp_and_energies = card_is_in_play
			var slot = build_pokemon_slot_with_energies_and_hp(this_card_in_hand, display_size, 33, is_active_slot, show_hp_and_energies)
			slot.size_flags_vertical = Control.SIZE_SHRINK_END
			
			if is_active_slot:
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
			hand_container.add_child(hand_card_to_display)
			hand_card_to_display.load_card_image(this_card_in_hand.uid, card_size, this_card_in_hand, face_down)
			hand_card_to_display.card_clicked.connect(this_card_clicked)
						
# Refreshes the hand display for either player or opponent using standard sizes and containers
func refresh_hand_display(is_opponent: bool) -> void:
	if is_opponent:
		display_hand_cards_array(opponent_hand, opponent_hand_container, card_scales[11.55], hide_hidden_cards, 400, 7)
	else:
		display_hand_cards_array(player_hand, player_hand_container, card_scales[11])

# Display active and bench pokemon for either player or opponent. is_opponent: true for opponent, false for player
func display_pokemon(is_opponent: bool) -> void:
	var active_pokemon = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench_pokemon_array = opponent_bench if is_opponent else player_bench
	var active_container = opponent_active_container if is_opponent else player_active_container
	var bench_container = opponent_bench_container if is_opponent else player_bench_container
	
	# Clear active pokemon container
	for child in active_container.get_children():
		child.queue_free()
	
	# Display active pokemon if exists
	if active_pokemon != null:
		
		var active_card_display = TextureRect.new()
		active_card_display.set_script(card_display_script)
		active_container.add_child(active_card_display)
		active_card_display.load_card_image(active_pokemon.uid, card_scales[3.5], active_pokemon)
		active_card_display.card_clicked.connect(this_card_clicked)
	
	# Clear bench container
	for child in bench_container.get_children():
		child.queue_free()
	
	# Display bench pokemon
	# Each bench pokemon is wrapped in a VBoxContainer slot containing:
	#   - a Control card_area (free-layout) with energy cards stacked behind the pokemon card
	#   - a Label showing current/max HP
	# bench_container is an HBoxContainer so slots are laid out horizontally.
	if bench_pokemon_array.size() > 0:
		for bench_pokemon in bench_pokemon_array:
			var slot = build_pokemon_slot_with_energies_and_hp(bench_pokemon, card_scales[11], 16)
			bench_container.add_child(slot)
			
	# Display HP circles for active Pokemon
	display_hp_circles_above_align(active_pokemon, is_opponent)

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
		if player_bench.size() >= 5:
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
	var prize_cards_container: HBoxContainer
	var prize_cards: Array
	
	if is_opponent:
		prize_cards_container = opponent_prize_container
		prize_cards = opponent_prize_cards		
	else:
		prize_cards_container = player_prize_container
		prize_cards = player_prize_cards

	# Clear any existing cards from the container
	for child in prize_cards_container.get_children():
		child.queue_free()
	
	# If prize cards array is empty, nothing to display
	if prize_cards.size() == 0:
		return
	
	# Display each prize card
	for prize_card in prize_cards:
		var prize_card_display = TextureRect.new()
		
		# Attach the card display script
		prize_card_display.set_script(card_display_script)
		
		# Add to container
		prize_cards_container.add_child(prize_card_display)
		
		# Load the card image with a size appropriate for prize cards
		prize_card_display.load_card_image(prize_card.uid, card_scales[11.55], prize_card, hide_hidden_cards)
		
		# Connect the signal so prize cards can be clicked if needed
		prize_card_display.card_clicked.connect(this_card_clicked)	

# Displays attached energy cards next to the active Pokemon, stacking with overlap
func display_active_pokemon_energies(is_opponent: bool = false) -> void:
	var energy_container = opponent_energy_container if is_opponent else player_energy_container
	var active_pokemon = opponent_active_pokemon if is_opponent else player_active_pokemon

	# Always refresh attached trainer cards display (PlusPower, Defender)
	trainer_effects.display_attached_trainer_cards(is_opponent)

	for child in energy_container.get_children():
		child.queue_free()

	if active_pokemon == null:
		return

	if active_pokemon.attached_energies.size() == 0:
		return

	
	var energy_card_size = card_scales[11]
	var card_width = energy_card_size.x
	var overlap_offset = 80

	if active_pokemon.attached_energies.size() > 6:
		var target_width = 480.0
		var n = active_pokemon.attached_energies.size()
		overlap_offset = (target_width - card_width) / (n - 1)

	for i in range(active_pokemon.attached_energies.size()):
		var attached_energy = active_pokemon.attached_energies[i]
		var energy_display = TextureRect.new()
		energy_display.set_script(card_display_script)
		energy_container.add_child(energy_display)
		energy_display.load_card_image(attached_energy.uid, energy_card_size, attached_energy)
		energy_display.position.x = overlap_offset * i if is_opponent else -(i * overlap_offset)
		
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
func build_pokemon_slot_with_energies_and_hp(card_obj: card_object, card_size: Vector2, label_font_size: int, _is_active: bool = false, show_hp_and_energies: bool = true) -> VBoxContainer:
	
	var slot = VBoxContainer.new()
	slot.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var energy_count = card_obj.attached_energies.size() if show_hp_and_energies else 0
	
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
		var hp_label = Label.new()
		hp_label.text = str(current_hp) + "/" + str(max_hp) + "hp"
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_label.add_theme_font_size_override("font_size", label_font_size)
		hp_label.add_theme_color_override("font_color", Color.BLACK)
		slot.add_child(hp_label)
	
	return slot

# Displays HP circles above the active pokemon, colouring red from damage taken
func display_hp_circles_above_align(active_pokemon: card_object, is_opponent: bool) -> void:
	var hp_grid_container = opponent_hp_container if is_opponent else player_hp_container
	
	for child in hp_grid_container.get_children():
		child.queue_free()
	
	hp_grid_container.columns = 12
	
	if active_pokemon == null or not active_pokemon.metadata.has("hp"):
		return
	
	var max_hp = int(active_pokemon.metadata["hp"])
	var total_circles = max_hp / 10
	var red_circles = (max_hp - active_pokemon.current_hp) / 10
	
	var circles_per_row = 12
	var bottom_row_circles = min(total_circles, circles_per_row)
	var top_row_circles = max(0, total_circles - circles_per_row)
	var top_row_spacers = circles_per_row - top_row_circles
	var bottom_row_spacers = circles_per_row - bottom_row_circles
	
	# Damage fills top row entirely first, remainder spills into bottom row
	var top_red = min(red_circles, top_row_circles)
	var bottom_red = red_circles - top_red
	
	# Opponent draws circles first (left-aligned), player draws spacers first (right-aligned)
	_add_hp_row(hp_grid_container, top_row_circles, top_row_spacers, top_red, is_opponent, false)
	_add_hp_row(hp_grid_container, bottom_row_circles, bottom_row_spacers, bottom_red, is_opponent, is_opponent)

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
	
	# Loop through each attack and generate a button for it
	for i in range(attacks.size()):
		var attack = attacks[i]
		var btn = Button.new()
		btn.text = attack.get("name", "Attack")
		btn.custom_minimum_size = Vector2(350, 50)
		attack_buttons_container.add_child(btn)
		
		# Check if attack is disabled (Farfetch'd permanent, Amnesia, etc.)
		var attack_name = attack.get("name", "")
		if is_attack_disabled(player_active_pokemon, attack_name):
			btn.disabled = true
			btn.theme = theme_disabled
			btn.text = attack_name + " (DISABLED)"
		# Enable and colour green if requirements met, disable and grey out if not
		elif check_attack_requirements(attack, player_active_pokemon):
			btn.disabled = false
			btn.theme = theme_green
		else:
			btn.disabled = true
			btn.theme = theme_disabled
		
		# bind(i) locks the current index into the callable so each button calls with its own attack index
		btn.pressed.connect(perform_attack.bind(i))

# Clears generated attack buttons and restores the main action buttons
func hide_attack_buttons() -> void:
	for child in attack_buttons_container.get_children():
		# Skip the cancel button — it's a permanent node, not dynamically generated
		if child.name == "cancel_attack_mode_button":
			continue
		child.queue_free()
	
	attack_buttons_container.visible = false
	main_buttons_container.visible = true

# Displays the message box with given text and pauses execution until the player clicks
func show_message(message_text: String) -> void:
	msgbox_container.visible = true
	msgbox_texture.visible = true
	msgbox_label.visible = true
	msgbox_label.text = message_text
	await message_acknowledged
	msgbox_label.visible = false
	msgbox_texture.visible = false
	msgbox_container.visible = false

# Changes the deck icon to show how many cards are (roughly)
func update_deck_icon(is_opponent: bool) -> void:
	var deck = opponent_deck if is_opponent else player_deck
	var widget = opponent_deck_icon if is_opponent else player_deck_icon
	var count = deck.size()

	var count_label = widget.get_node("opponent_deck_count_label") if is_opponent else widget.get_node("player_deck_count_label")
	count_label.text = str(count)

	if count == 0:
		widget.texture = null
		return

	var image_path: String
	if count >= 42:
		image_path = "res://Image_Assets/Card_Backs_And_Decks/1deckfulltrans_clean.png"
	elif count >= 35:
		image_path = "res://Image_Assets/Card_Backs_And_Decks/2deck3quarts.png"
	elif count >= 20:
		image_path = "res://Image_Assets/Card_Backs_And_Decks/3deckhalf.png"
	elif count >= 10:
		image_path = "res://Image_Assets/Card_Backs_And_Decks/4deckquarter.png"
	else:
		image_path = "res://Image_Assets/Card_Backs_And_Decks/cardbacksmall.png"
	widget.texture = load(image_path)
	
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

	var btn_theme = theme_disabled if should_disable else theme_blue
	var buttons = [
		main_buttons_container.get_node("button_main_attack"),
		main_buttons_container.get_node("button_main_power"),
		main_buttons_container.get_node("button_main_retreat"),
		main_buttons_container.get_node("button_main_endturn"),
	]
	for btn in buttons:
		btn.theme = btn_theme
		btn.disabled = should_disable

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
	top_display.load_card_image(top_card.uid, Vector2(110, 141), top_card)
	icon.move_child(icon.get_node(label_name), -1)

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

	for icon_file in icons_to_show:
		var icon = TextureRect.new()
		icon.texture = load("res://Image_Assets/Icons/Status_Icons/" + icon_file)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(100, 30)
		icon.size = Vector2(100, 30)
		container.add_child(icon)

############################################################### END DISPLAY FUNCTIONS ################################################################
######################################################################################################################################################

#	   ##      ####    ##  ########      ##      ##          ##    ########  ########
#     ####     ## ##   ##     ##        ####    ####        ####      ##     ##
#    ##  ##    ##  ##  ##     ##       ##  ##  ##  ##      ##  ##     ##     ########
#   ########   ##   ## ##     ##      ##    ####    ##    ########    ##     ##
#  ##      ##  ##    ####  ########  ##      ##      ##  ##      ##   ##     ########

######################################################################################################################################################
################################################################ ANIMATION FUNCTIONS #################################################################

# Creates a floating label at a given position that drifts upward and fades out over 2 seconds
func show_floating_label(message: String, spawn_position: Vector2, upwards: bool = true) -> void:
	var label = Label.new()
	label.text = message
	
	# uncomment these to make it centrally aligned instead of left aligned
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(300, 0)
	
	label.position = spawn_position
	label.modulate = Color(1, 1, 1, 1)
	
	# Apply kenney theme for the pixel font, then override colour and size
	label.theme = theme_disabled
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_font_size_override("font_size", 36)
	
	add_child(label)
	
	var tween = create_tween()
	tween.set_parallel(true)
	if upwards:
		tween.tween_property(label, "position:y", spawn_position.y - 250, 1.5)
	else:
		tween.tween_property(label, "position:y", spawn_position.y + 250, 1.5)		
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	
	await tween.finished
	label.queue_free()

# Animates a card back image sliding from one node's position to another
func animate_card_a_to_b(from_node: Control, to_node: Control, animation_speed: float = 0.8, custom_texture: Texture2D = null, custom_size: Vector2 = Vector2(83, 113)) -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_card_draw_sound)
	animation_blocker.visible = true
	var card_image = TextureRect.new()
	card_image.texture = custom_texture if custom_texture else card_back_texture
	card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_image.custom_minimum_size = custom_size
	card_image.size = custom_size
	card_image.z_index = 100
	add_child(card_image)
	
	card_image.global_position = from_node.global_position
	var target_pos = to_node.global_position + Vector2(to_node.size.x / 2, 0,)
	
	var tween = create_tween()
	tween.tween_property(card_image, "global_position", target_pos, animation_speed).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(card_image.queue_free)
	await tween.finished
	animation_blocker.visible = false

# Animate discarding for reatreat and knockout
func animate_energies_to_discard(energy_cards: Array, pokemon: card_object, is_opponent: bool) -> void:
	var discard_node = opponent_discard_icon if is_opponent else player_discard_icon
	var discard_pile = opponent_discard_pile if is_opponent else player_discard_pile
	var from_node = find_card_ui_for_object(pokemon)

	if from_node == null:
		return

	for energy in energy_cards:
		var energy_texture = get_card_texture(energy)
		animate_card_a_to_b(from_node, discard_node, 0.2, energy_texture, card_scales[10])

		# Remove this energy from the pokemon's attached list NOW,
		# so the redraw reflects one fewer energy each frame
		pokemon.attached_energies.erase(energy)

		# Actually add the energy to the discard pile array
		energy.current_location = "discard"
		discard_pile.append(energy)

		display_active_pokemon_energies(is_opponent)
		await get_tree().create_timer(0.2).timeout

	# Update the discard pile visual to show the new top card
	update_discard_pile_display(is_opponent)
				
# Animates the retreat sequence: energies to discard, message, then swap pokemon positions
func animate_retreat(old_active: card_object, new_active: card_object, discarded_energies: Array, is_opponent: bool) -> void:
	var active_container = opponent_active_container if is_opponent else player_active_container
	var bench_container = opponent_bench_container if is_opponent else player_bench_container
	
	if discarded_energies.size() > 0:
		await animate_energies_to_discard(discarded_energies, old_active, is_opponent)
		update_discard_pile_display(is_opponent)
	
	display_active_pokemon_energies(is_opponent)
	
	await show_message(old_active.metadata["name"].to_upper() + " RETREATED TO THE BENCH!")
	
	var old_texture = get_card_texture(old_active)
	var new_texture = get_card_texture(new_active)
	
	animate_card_a_to_b(active_container, bench_container, 0.3, old_texture, card_scales[10])
	await animate_card_a_to_b(bench_container, active_container, 0.3, new_texture, card_scales[10])

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
	if "_red" in coin_name:
		return Color(1.0, 0.2, 0.2)
	elif "_gold" in coin_name:
		return Color(1.0, 0.85, 0.2)
	elif "_silver" in coin_name:
		return Color(0.85, 0.85, 0.9)
	elif "_blue" in coin_name:
		return Color(0.3, 0.5, 1.0)
	elif "_green" in coin_name:
		return Color(0.2, 0.9, 0.3)
	elif "_pink" in coin_name:
		return Color(1.0, 0.2, 0.7)
	elif "_purple" in coin_name:
		return Color(0.55, 0.1, 1)
	elif "_black" in coin_name:
		return Color(0, 0, 0)
	elif "_brown" in coin_name:
		return Color(0.5, 0.3, 0.2)
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
func get_pokemon_screen_location(pokemon: card_object) -> Dictionary:
	if pokemon == opponent_active_pokemon:
		return {"position": opponent_active_container.global_position, "size": card_scales[3.5], "is_active": true}
	elif pokemon == player_active_pokemon:
		return {"position": player_active_container.global_position, "size": card_scales[3.5], "is_active": true}
	elif pokemon in opponent_bench:
		var index = opponent_bench.find(pokemon)
		var size = card_scales[11]
		var separation = opponent_bench_container.get_theme_constant("separation")
		return {"position": opponent_bench_container.global_position + Vector2(index * (size.x + separation), 0), "size": size, "is_active": false}
	elif pokemon in player_bench:
		var index = player_bench.find(pokemon)
		var size = card_scales[11]
		var separation = player_bench_container.get_theme_constant("separation")
		return {"position": player_bench_container.global_position + Vector2(index * (size.x + separation), 0), "size": size, "is_active": false}
	return {}

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

	await get_tree().create_timer(1).timeout
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
	await get_tree().create_timer(1).timeout
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
	var player_deck_path = "res://Player_Data/Player_Decks/"+player_deck_name+".json"
	
	# Load and shuffle deck
	player_deck = load_deck_from_file(player_deck_path)
	
	# Draw opening hand with mulligan
	player_hand = draw_opening_hand(player_deck, "Player")
	
	# Display the hand on the main screen at the top centre
	display_hand_cards_array(player_hand, player_hand_container, card_scales[11])

# Main function to set up the opponents's deck and hand at match start. Looks up the NPC name and finds the corresponding deck file
func setup_opponent(opponent_id: String):
	
	# We will need to eventually pass a number of different decks depending on the NPC opponent so load the correct one from file
	var opponent_deck_path = "res://Opponent_Data/Opponent_Deck_Data/"+opponent_id+".json"
	
	# Load the deck from the opponent data folder file
	opponent_deck = load_deck_from_file(opponent_deck_path)
	
	# Draw opening cards and mulligan
	opponent_hand = draw_opening_hand(opponent_deck, "Opponent")
	
	# Display the cards in the top right in tiny size just for visual cue
	display_hand_cards_array(opponent_hand, opponent_hand_container, card_scales[11.55], hide_hidden_cards)

# Function to draw opening hand with mulligan logic for both player and opponent
func draw_opening_hand(deck: Array, player_name: String = "") -> Array:
	# Set the opening variables that will be overwritten by the function
	var hand = []
	var has_basic_pokemon = false
	
	# We need to mulligan if no basic pokemon in hand for each draw. May take multiple attempts
	while not has_basic_pokemon:
		
		# Clear the hand every time this loops otherwise cards would just be continued to be added
		hand.clear()
		
		# Now draw X (default is 7) cards and put them in the hand
		for i in range(amount_of_cards_to_draw):
			
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

# Draws the top 6 cards from the specified player's deck and adds them to prize cards
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
	
	# Check if there are at least 6 cards in the deck
	if deck.size() < 6:
		print("Error: Not enough cards in deck to draw 6 prize cards. Current deck size: ", deck.size())
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

# Quit the game when called
func end_game() -> void:
	# Fix 6: Escape key = forfeit, not quit application
	game_end_logic(true)
	
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
	
	# Set max on bench to 5
	if player_bench.size() >= 5:
		print("Error: Bench is full (maximum 5 pokemon)")
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
	
	target_pokemon.attached_energies.append(energy_card)
	print("Attached ", energy_card.metadata.get("name", "Unknown Energy"), " to ", target_pokemon.metadata.get("name", "Unknown Pokemon"))
	player_hand.erase(energy_card)
	player_energy_played_this_turn = true
	
	# Clear the attachment variables and exit attach mode
	energy_card_awaiting_target = null
	selected_card_for_action = null
	card_attach_mode_active = false
	
	hide_selection_mode_display_main()
	refresh_hand_display(false)
	
	# Animate energy flying from hand to the target pokemon
	var target_node = player_energy_container if target_pokemon == player_active_pokemon else player_bench_container
	var energy_texture = get_card_texture(energy_card)
	await animate_card_a_to_b(player_hand_container, target_node, 0.2, energy_texture, card_scales[12])
		
	display_pokemon(false)	
	display_active_pokemon_energies(false)

	await get_tree().process_frame
	await play_energy_attached_effect(target_pokemon, energy_card)
	
	# Apply special energy on-attach effects (Rainbow self-damage, Full Heal cure, Potion heal, etc.)
	if "Special" in subtypes:
		await special_energy_effects.apply_on_attach_effects(energy_card, target_pokemon, false)

# Called when any win/loss condition is met to end the match
func game_end_logic(loser_is_player: bool) -> void:
	# Set the flag immediately so no other async functions continue processing
	game_is_over = true
	
	if loser_is_player:
		print("GAME OVER: Player has lost the game!")
		await show_message("GAME OVER: YOU LOST!!!!!")
		GameState.battle_result = "loss"
	else:
		print("GAME OVER: Opponent has lost the game!")
		await show_message("CONGRATULATIONS: YOU WON!!!!!")
		GameState.battle_result = "win"
	
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
		get_tree().change_scene_to_file("res://Scenes/Main_Match_Gameplay_Scenes/Match_End_Outro_Scene.tscn")
	)

# Draws one card from the top of the deck and adds it to the hand
func draw_card_from_deck(is_opponent: bool) -> card_object:
	var deck = opponent_deck if is_opponent else player_deck
	var hand = opponent_hand if is_opponent else player_hand
	if deck.size() == 0:
		game_end_logic(not is_opponent)
		return null

	var drawn_card = deck.pop_front()
	drawn_card.current_location = "hand"
	hand.append(drawn_card)

	if is_opponent:
		await animate_card_a_to_b(opponent_deck_icon, opponent_hand_container, 0.2)
	else:
		await animate_card_a_to_b(player_deck_icon, player_hand_container,0.3)

	return drawn_card

# Flips a coin with animation, blocks input, shows result message, returns true for heads
func flip_coin(silent: bool = false) -> bool:
	var result: bool = (randi() % 2 == 0)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_coin_flip_sound)

	# Show the input-blocking overlay and set initial coin image to heads
	coin_container.visible = true
	var coin = coin_texture
	coin.texture = tex_heads
	coin.visible = true
	
	# Force coin to a fixed display size regardless of source image dimensions
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.custom_minimum_size = Vector2(129, 129)
	coin.size = Vector2(129, 129)
	
	# Set pivot to center so the squish effect scales from the middle, not the top edge
	coin.pivot_offset = coin.size / 2
	var start_y = coin.position.y
	var flip_count = 12
	var half_flip_time = 0.04
	var total_time = flip_count * half_flip_time * 1.5
	
	# Position tween: arc up then back down
	var pos_tween = create_tween()
	pos_tween.tween_property(coin, "position:y", start_y - 400, total_time / 1.5).set_ease(Tween.EASE_OUT)
	pos_tween.tween_property(coin, "position:y", start_y, total_time / 1.5).set_ease(Tween.EASE_IN)
	
	# Flip tween: squish scale.y to 0, swap texture, unsquish back to 1
	var flip_tween = create_tween()
	var textures = [tex_tails, tex_heads]
	for i in flip_count:
		flip_tween.tween_property(coin, "scale:y", 0.0, half_flip_time)
		flip_tween.tween_callback(coin.set.bind("texture", textures[i % 2]))
		flip_tween.tween_property(coin, "scale:y", 1.0, half_flip_time)
	
	await flip_tween.finished
	
	# Set the final coin face to match the actual result
	coin.texture = tex_heads if result else tex_tails
	var sparkles = null
	if result:
		sparkles = start_sparkle_effect(coin)
	coin.scale.y = 1.0
	
	if silent:
		# In silent mode, just wait briefly and clean up without showing a message
		await get_tree().create_timer(0.2).timeout
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
		energy.current_location = "discard"
		discard.append(energy)
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
	card.no_prize_on_ko = false
	card.is_bench_token = false
	card.power_used_this_turn = false
	card.is_electrode_energy = false
	card.electrode_energy_type = ""
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
	var card_texture = card_back_texture if is_opponent else get_card_texture(card)
	
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

# Resets placed_on_field_this_turn to false for all pokemon on the specified player's field
func reset_field_pokemon_turn_flags(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench

	if active != null:
		active.placed_on_field_this_turn = false

	for bench_pokemon in bench:
		bench_pokemon.placed_on_field_this_turn = false

# Called at the start of the player's turn to perform mandatory actions
func player_start_turn_checks() -> void:
	if _should_bail():
		return
	# Reset trainer lock from Headache
	trainer_effects.reset_trainer_lock(false)
	opponent_blocker.visible = false
	show_floating_label("Start turn", Vector2(50, 180), false)
	turn_number += 1
	print("PLAYER'S TURN START. TURN NUMBER IS ", turn_number)
	var drawn_card = await draw_card_from_deck(false)
	
	opponents_turn_active = false
	update_main_screen_buttons()
	
	if drawn_card == null:
		return

	refresh_hand_display(false)
	update_deck_icon(false)
	
	# Update Ditto Transform state (may need to re-transform after opponent turn changes)
	powers_and_bodies.update_ditto_transform(false)
	powers_and_bodies.update_ditto_transform(true)
	
# Called when the player presses the end turn button to reset per-turn variables and begin next turn
func player_end_turn_checks() -> void:
	opponent_blocker.visible = true
	opponents_turn_active = true
	update_main_screen_buttons()
	show_floating_label("End turn", Vector2(1500, 880))
	
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
	reset_field_pokemon_turn_flags(false)
	reset_field_pokemon_turn_flags(true)
	
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
		clear_end_of_turn_statuses(player_active_pokemon, false)
		clear_defensive_statuses(opponent_active_pokemon, true)
		clear_jungle_defensive_statuses(opponent_active_pokemon, true)
		player_retreat_disabled = false
		# Discard PlusPower from player's active at end of player's turn
		if player_active_pokemon != null:
			await trainer_effects.discard_pluspower_from_pokemon(player_active_pokemon, false)
		# Tick down Defender on opponent's pokemon (Defender discards at end of opponent's NEXT turn)
		await trainer_effects.tick_defender_counters(true)
	else:
		clear_end_of_turn_statuses(opponent_active_pokemon, true)
		clear_defensive_statuses(player_active_pokemon, false)
		clear_jungle_defensive_statuses(player_active_pokemon, false)
		opponent_retreat_disabled = false
		# Discard PlusPower from opponent's active at end of opponent's turn
		if opponent_active_pokemon != null:
			await trainer_effects.discard_pluspower_from_pokemon(opponent_active_pokemon, true)
		# Tick down Defender on player's pokemon
		await trainer_effects.tick_defender_counters(false)
	
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
	
	# Clear power_disabled_until_end_of_next_turn (Dark Arbok Stare)
	if player_turn_just_ended:
		# Clear on opponent's pokemon at end of player's turn
		for bp in opponent_bench:
			bp.power_disabled_until_end_of_next_turn = false
		if opponent_active_pokemon != null:
			opponent_active_pokemon.power_disabled_until_end_of_next_turn = false
	else:
		for bp in player_bench:
			bp.power_disabled_until_end_of_next_turn = false
		if player_active_pokemon != null:
			player_active_pokemon.power_disabled_until_end_of_next_turn = false
	
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
	
	# Clear end_of_turn disabled attacks
	var keys_to_remove = []
	for atk_name in pokemon.disabled_attacks:
		if pokemon.disabled_attacks[atk_name] == "end_of_turn":
			keys_to_remove.append(atk_name)
			print("END OF TURN: ", pokemon_name, " attack '", atk_name, "' re-enabled")
			changed = true
	for key in keys_to_remove:
		pokemon.disabled_attacks.erase(key)

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

########################################################### Evolution functions ##############################################################

# Scans active and bench for Pokemon that the given evolution card can legally evolve from
func get_valid_evolution_targets(evolution_card: card_object, is_opponent: bool) -> Array:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var valid_targets = []
	
	if turn_number <= 2:
		return []
	
	for bench_pokemon in bench:
		if not bench_pokemon.placed_on_field_this_turn:
			if can_evolve_from(evolution_card, bench_pokemon):
				valid_targets.append(bench_pokemon)
	
	if active != null and not active.placed_on_field_this_turn:
		if can_evolve_from(evolution_card, active):
			valid_targets.append(active)
	
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
	
	# Transfer existing pre-evolutions then add the old card itself to the chain
	evo_card.attached_pre_evolutions = target_card.attached_pre_evolutions.duplicate()
	target_card.attached_pre_evolutions.clear()
	evo_card.attached_pre_evolutions.append(target_card)
	
	# Mark as played this turn so it can't evolve again immediately
	evo_card.placed_on_field_this_turn = true
	
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
	
	# BASE5: When-played powers trigger when evolved from hand
	var evo_name = evo_card.metadata.get("name", "")
	if evo_name == "Dark Dragonite":
		await powers_and_bodies.trigger_summon_minions(evo_card, is_opponent)
	elif evo_name == "Dark Golbat":
		await powers_and_bodies.trigger_sneak_attack(evo_card, is_opponent)
	elif evo_name == "Dark Slowbro":
		await powers_and_bodies.trigger_reel_in(evo_card, is_opponent)
	 
########################################################### Retreat functions ##############################################################

# Checks if a Pokemon can retreat, returning a dictionary with "can_retreat" and "reason" if blocked
func can_retreat(is_opponent: bool) -> Dictionary:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var is_disabled = opponent_retreat_disabled if is_opponent else player_retreat_disabled
	var already_retreated = opponent_retreated_this_turn if is_opponent else player_retreated_this_turn
	
	if already_retreated:
		return {"can_retreat": false, "reason": "You have already retreated this turn!"}
	if active == null:
		return {"can_retreat": false, "reason": "No active Pokemon!"}
	if active.is_bench_token:
		return {"can_retreat": false, "reason": active.metadata.get("name", "") + " cannot retreat!"}
	if bench.size() == 0:
		return {"can_retreat": false, "reason": "Cannot retreat with no Pokemon on your bench!"}
	if is_disabled:
		return {"can_retreat": false, "reason": "You have been prevented from retreating!"}
	if active.special_condition == "Paralyzed":
		return {"can_retreat": false, "reason": active.metadata.get("name", "") + " is Paralyzed and cannot retreat!"}
	if active.special_condition == "Asleep":
		return {"can_retreat": false, "reason": active.metadata.get("name", "") + " is Asleep and cannot retreat!"}
	if active.attached_energies.size() < get_retreat_cost(active):
		return {"can_retreat": false, "reason": "Not enough energy to retreat!"}
	
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
	
	# Get the attacks if they exist
	var attacks = card.metadata.get("attacks", [])
	
	return attacks

# Read an energy card passed to this function and return what energies this card actually provides.
func get_energy_provided_by_card(energy_card: card_object) -> Array:
	if energy_card == null:
		return []
	
	# Electrode Buzzap: this card is an Electrode acting as energy
	if energy_card.is_electrode_energy:
		return [energy_card.electrode_energy_type]
	
	var supertype = energy_card.metadata.get("supertype", "").to_lower()
	if supertype != "energy":
		return []
	
	var subtypes = energy_card.metadata.get("subtypes", [])
	var card_name = energy_card.metadata.get("name", "")
	
	# Basic energy: strip " Energy" from name to get the type string
	if "Basic" in subtypes:
		var energy_type = card_name.replace(" Energy", "").strip_edges()
		return [energy_type]
	
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
	show_floating_label("NO EFFECT", label_pos, true)
	print("INVINCIBLE: Attack fully blocked on ", defender.metadata["name"])
	return true

# Checks if the defender has a no-damage shield active
# Returns the adjusted damage (0 if shielded, otherwise the original value)
func apply_defender_no_damage_shield(defender: card_object, damage: int, is_opponent: bool = false) -> int:
	if not defender.has_no_damage:
		return damage
	var label_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
	show_floating_label("NO DAMAGE", label_pos, true)
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
	
	var defender_label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
	for modifier in modifiers:
		show_floating_label(modifier, defender_label_pos, true)
		await get_tree().create_timer(0.5).timeout
	# Only show damage label if there is actual damage, or if the attack originally had damage
	# but it was reduced to 0 by resistance/other modifiers (not shields)
	var has_shield_modifier = "NO DAMAGE" in modifiers
	var show_damage_label = final_damage > 0 or (base_damage > 0 and modifiers.size() > 0 and not has_shield_modifier)
	if show_damage_label:
		show_floating_label("-" + str(final_damage) + "HP", defender_label_pos, true)
	defender.current_hp = max(0, defender.current_hp - final_damage)
	print(attacker.metadata["name"] + " dealt " + str(final_damage) + " damage to " + defender.metadata["name"] + "! HP remaining: " + str(defender.current_hp))
	display_hp_circles_above_align(defender, !is_opponent)
	
	# Check for Machamp's Strikes Back power (triggers when Machamp takes damage)
	if final_damage > 0:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_damage_sound)
		await powers_and_bodies.check_strikes_back(defender, attacker, !is_opponent)
		# Check for Dark Wartortle's Mirror Shell (counter equal damage)
		await attack_effects.check_mirror_shell(defender, attacker, final_damage, !is_opponent)

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
	
	# Handle special attacks that have completely unique flows
	var text_lower = attack.get("text", "").to_lower()
	

	# SWORDS DANCE: Buff Slash damage next turn (no damage attack)
	if "swords dance" in attack_name.to_lower() or ("during your next turn" in text_lower and "slash" in text_lower and "instead of" in text_lower):
		hide_attack_buttons()
		await attack_effects.execute_swords_dance(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# HURRICANE: Return defender to hand unless KO
	if "return the defending" in text_lower and "to your opponent" in text_lower and "hand" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_hurricane(player_active_pokemon, opponent_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# CHAIN LIGHTNING: Damage same-type benched pokemon on both sides
	if "chain lightning" in attack_name.to_lower() or ("same type as the defending" in text_lower and "damage to each benched" in text_lower):
		hide_attack_buttons()
		await attack_effects.execute_chain_lightning(player_active_pokemon, opponent_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# BIG EGGSPLOSION: Flip coins equal to attached energy count
	if "number of energy attached" in text_lower and "times the number of heads" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_big_eggsplosion(player_active_pokemon, opponent_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# BOYFRIENDS (Nidoqueen): +20 per Nidoking in play
	if "boyfriends" in attack_name.to_lower() or "for each nidoking" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_boyfriends(player_active_pokemon, opponent_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# MEGA DRAIN: Deal damage, heal half
	if "mega drain" in attack_name.to_lower() or ("remove" in text_lower and "equal to half the damage" in text_lower):
		hide_attack_buttons()
		await attack_effects.execute_mega_drain(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 40, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# LEECH LIFE (Venonat): Deal damage, heal equal to damage dealt
	if "leech life" in attack_name.to_lower() or ("remove" in text_lower and "equal to the damage done" in text_lower and "half" not in text_lower and "unless" not in text_lower):
		hide_attack_buttons()
		var base_dmg = attack_effects.parse_attack_base_damage(attack)
		await attack_effects.execute_leech_life(player_active_pokemon, opponent_active_pokemon, false, base_dmg)
		last_attack_on_opponent = {"damage": base_dmg, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# ABSORB (Kabutops): Same as Mega Drain
	if "equal to half the damage done" in text_lower and "remove" in text_lower and "mega drain" not in attack_name.to_lower():
		hide_attack_buttons()
		await attack_effects.execute_mega_drain(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 40, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# --- BASE5 SPECIAL ATTACKS (must come before Sonicboom handler) ---
	
	# TARGET ANY POKEMON: Stare, Flitter, Dig Under, Coin Hurl (choose opponent Pokemon, damage no W/R)
	if "choose 1 of your opponent's pokémon" in text_lower and "damage to that pokémon" in text_lower:
		hide_attack_buttons()
		var disable_power = "power stops working" in text_lower
		if disable_power:
			await attack_effects.execute_stare(player_active_pokemon, opponent_active_pokemon, false)
		else:
			var base_dmg = attack_effects.parse_attack_base_damage(attack)
			if base_dmg <= 0:
				base_dmg = attack_effects.extract_number_before(text_lower, "damage to that")
			var flip_req = "flip a coin" in text_lower and "if heads" in text_lower
			await attack_effects.execute_snipe_no_wr(player_active_pokemon, opponent_active_pokemon, false, base_dmg, flip_req)
		# Apply remaining effects (Poison Vapor bench damage + poison)
		var pae_target = attack_effects.parse_card_text_effects(attack.get("text", ""), player_active_pokemon.metadata.get("name", ""))
		if pae_target.size() > 0:
			await attack_effects.apply_card_text_effects(pae_target, player_active_pokemon, opponent_active_pokemon, false, "")
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# BENCH MANIPULATION (Dark Hypno): Opponent flip coins = bench, 20×tails, no W/R
	if "number of coins equal to the number of pokémon on" in text_lower and "tails" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_bench_manipulation(player_active_pokemon, opponent_active_pokemon, false)
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# CONTINUOUS FIREBALL (Dark Charizard): Flip coins = Fire Energy, 50×heads
	if "flip a number of coins equal to the number of fire energy" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_continuous_fireball(player_active_pokemon, opponent_active_pokemon, false)
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# FLING (Dark Machamp): Shuffle opponent active into deck
	if "shuffles his or her active pokémon" in text_lower and "into his or her deck" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_fling(player_active_pokemon, opponent_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# MAGNETIC LINES (Dark Magneton): 30 + move energy to bench
	if "choose 1 of them and attach that energy card to it" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_magnetic_lines(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 30, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# PETAL WHIRLWIND (Dark Vileplume): 3 coin flips, 30×heads, 2+ = confused
	if "30 damage times the number of heads" in text_lower and "2 or more heads" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_petal_whirlwind(player_active_pokemon, opponent_active_pokemon, false)
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# MASS EXPLOSION (Dark Weezing)
	if "total number of koffing" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_mass_explosion(player_active_pokemon, opponent_active_pokemon, false)
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# ENERGY BOMB (Dark Electrode): 30 + move energy to bench
	if "take all energy cards attached" in text_lower and "benched pokémon" in text_lower and "any way you choose" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_energy_bomb(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 30, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# THIRD EYE (Dark Golduck): Discard energy, draw cards
	if "discard 1 energy card attached" in text_lower and "draw up to" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_third_eye(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# DRAG OFF (Dark Machoke): Switch bench to active, then damage
	if "before doing damage, choose 1 of your opponent" in text_lower and "switch it with the defending" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_drag_off(player_active_pokemon, opponent_active_pokemon, false)
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# FLAME PILLAR (Dark Rapidash): 30 + optional fire discard for 10 bench damage
	if "you may discard 1 fire energy" in text_lower and "10 damage to it" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_flame_pillar(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 30, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# MIRROR SHELL (Dark Wartortle): Counter damage next turn
	if "attacks the defending pokémon for an equal amount of damage" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_mirror_shell(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# RAPID EVOLUTION (Magikarp): Search deck for Gyarados/Dark Gyarados
	if "evolution card named gyarados or dark gyarados" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_rapid_evolution(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# VANISH (Abra): Shuffle self into deck
	if "shuffle" in text_lower and "into your deck" in text_lower and "discard all cards attached" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_vanish(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# MAGNETISM (Magnemite): 10+ per bench Magnemite/Magneton
	if "magnemite" in text_lower and "magneton" in text_lower and "on your bench" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_magnetism(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 10, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# MISCHIEF (Mankey): Shuffle opponent deck (no damage)
	if "shuffle your opponent" in text_lower and "deck" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_mischief(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# SURPRISE THUNDER (Dark Raichu): 30 + double flip bench damage
	if "second coin" in text_lower and "benched pokémon" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_surprise_thunder(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 30, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# AFTERNOON NAP (Slowpoke): Search deck for Psychic Energy
	if "search your deck for a psychic energy" in text_lower and "attach it" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_afternoon_nap(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# FASCINATE (Dark Persian): Flip to force switch
	if "fascinate" in attack_name.to_lower() or ("choose 1 of your opponent's benched" in text_lower and "switch it with the defending" in text_lower and "this attack does" not in text_lower):
		hide_attack_buttons()
		await attack_effects.execute_fascinate(player_active_pokemon, opponent_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# SONICBOOM: Fixed damage ignoring W/R
	if "don't apply weakness and resistance for this attack" in text_lower:
		hide_attack_buttons()
		var base_dmg = attack_effects.parse_attack_base_damage(attack)
		await attack_effects.execute_sonicboom(player_active_pokemon, opponent_active_pokemon, false, base_dmg)
		last_attack_on_opponent = {"damage": base_dmg, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# WILDFIRE: Discard Fire Energy to mill opponent deck
	if "discard any number of fire energy" in text_lower and "discard that many cards" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_wildfire(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# GIGASHOCK: 30 damage + 10 to up to 3 bench
	if "choose 3 of your opponent's benched" in text_lower and "10 damage to each of them" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_gigashock(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 30, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# THUNDERSTORM: 40 + per-bench flip + self recoil
	if "for each of your opponent's benched" in text_lower and "flip a coin" in text_lower and "damage times the number of tails" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_thunderstorm(player_active_pokemon, opponent_active_pokemon, false)
		last_attack_on_opponent = {"damage": 40, "attack": attack, "attacker_types": player_active_pokemon.metadata.get("types", ["Colorless"])}
		player_attacked_this_turn = true
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# PROPHECY: Look at top 3, rearrange
	if "look at up to 3 cards" in text_lower and "rearrange" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_prophecy(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# ENERGY CONVERSION: Get energy from discard + self damage
	if "energy cards from your discard pile into your hand" in text_lower and "damage to itself" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_energy_conversion(player_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# SPACING OUT: Flip to heal self, can't use if no damage
	if "remove a damage counter from" in text_lower and "can't be used if" in text_lower and "no damage counters" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_spacing_out(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# SCAVENGE: Discard Psychic Energy, get Trainer from discard
	if "discard 1 psychic energy" in text_lower and "trainer card from your discard pile" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_scavenge(player_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# CALL FOR FAMILY/FRIEND/SPROUT: Search deck for specific Basic Pokemon
	if "search your deck for" in text_lower and ("put it onto your bench" in text_lower or "put it on your bench" in text_lower):
		hide_attack_buttons()
		var search_names: Array = []
		var search_type: String = ""
		var search_text = attack.get("text", "")
		if "named Bellsprout" in search_text:
			search_names = ["Bellsprout"]
		elif "named Oddish" in search_text:
			search_names = ["Oddish"]
		elif "named Krabby" in search_text:
			search_names = ["Krabby"]
		elif "Nidoran" in search_text:
			search_names = ["Nidoran \u2640", "Nidoran \u2642"]
		elif "Fighting Basic" in search_text:
			search_type = "Fighting"
		else:
			var atk_types = player_active_pokemon.metadata.get("types", [])
			if atk_types.size() > 0:
				search_type = atk_types[0]
		await attack_effects.execute_call_for_pokemon(player_active_pokemon, false, search_names, search_type)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# METRONOME: Copy one of the opponent's attacks
	if "choose 1 of the defending" in text_lower and "copies that attack" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_metronome(player_active_pokemon, opponent_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# MIRROR MOVE: Replay the last attack received
	if "mirror move" in attack_name.to_lower() or ("was attacked last turn" in text_lower and "final result" in text_lower):
		hide_attack_buttons()
		await attack_effects.execute_mirror_move(player_active_pokemon, opponent_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# AMNESIA: Disable one of the opponent's attacks
	if "choose 1 of the defending" in text_lower and "can't use that attack" in text_lower:
		hide_attack_buttons()
		await attack_effects.execute_amnesia(player_active_pokemon, opponent_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# CONVERSION 1: Change opponent's weakness
	if "conversion 1" in attack_name.to_lower() or ("change it to a type" in text_lower and "weakness" in text_lower):
		hide_attack_buttons()
		await attack_effects.execute_conversion(player_active_pokemon, opponent_active_pokemon, false, true)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# CONVERSION 2: Change own resistance
	if "conversion 2" in attack_name.to_lower() or ("resistance to a type" in text_lower and "change" in text_lower):
		hide_attack_buttons()
		await attack_effects.execute_conversion(player_active_pokemon, opponent_active_pokemon, false, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# Check attack_blocked flag (Tail Wag / Leer) - benching either pokemon ends this
	if player_active_pokemon.attack_blocked_next_turn:
		if opponent_active_pokemon.get_instance_id() == player_active_pokemon.attack_blocked_by_id:
			await show_message(player_active_pokemon.metadata["name"].to_upper() + " CAN'T ATTACK!")
			hide_attack_buttons()
			player_active_pokemon.attack_blocked_next_turn = false
			player_active_pokemon.attack_blocked_by_id = -1
			await get_tree().create_timer(0.5).timeout
			player_end_turn_checks()
			return
		else:
			# Benching broke the effect
			player_active_pokemon.attack_blocked_next_turn = false
			player_active_pokemon.attack_blocked_by_id = -1
	
	# Swords Dance: If active, boost Slash base damage
	if player_active_pokemon.swords_dance_active and attack_name.to_lower() == "slash":
		attack = attack.duplicate()
		attack["damage"] = "60"
		player_active_pokemon.swords_dance_active = false
		await show_message("SWORDS DANCE BOOST! SLASH DOES 60 DAMAGE!")
	
	if await attack_effects.handle_attack_confusion(player_active_pokemon, false):
		hide_attack_buttons()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	if await attack_effects.handle_attack_blind(player_active_pokemon, false):
		hide_attack_buttons()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# Resolve variable damage (coin flips, per-energy, per-counter, etc.) BEFORE weakness/resistance
	var variable_result = await attack_effects.resolve_attack_variable_damage(attack, player_active_pokemon, opponent_active_pokemon, false)
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
		await get_tree().create_timer(0.5).timeout
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
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return

	final_damage = apply_defender_no_damage_shield(opponent_active_pokemon, final_damage, true)

	await display_and_apply_attack_damage(player_active_pokemon, opponent_active_pokemon, final_damage, result["modifiers"], false, resolved_base)
	hide_attack_buttons()
	
	# Store last attack for Mirror Move tracking
	last_attack_on_opponent = {"damage": final_damage, "attack": attack, "attacker_types": attacking_types}
	player_attacked_this_turn = true
	
	var _pae_effects = attack_effects.parse_card_text_effects(attack.get("text", ""), player_active_pokemon.metadata.get("name", ""))
	
	# Clear swords dance after any attack
	player_active_pokemon.swords_dance_active = false
	if _pae_effects.size() > 0:
		await attack_effects.apply_card_text_effects(_pae_effects, player_active_pokemon, opponent_active_pokemon, false, flip_result)
	
	await check_all_knockouts()
	
	await get_tree().create_timer(0.5).timeout
	player_end_turn_checks()
	
# Returns final damage and a list of modifiers applied, for display purposes
func calculate_final_damage(base_damage: int, attacking_types: Array, defending_pokemon: card_object, attacker_pokemon: card_object = null) -> Dictionary:
	var damage = base_damage
	var modifiers_applied = []
	
	if defending_pokemon == null:
		return {"damage": damage, "modifiers": modifiers_applied}
	
	# Apply weakness (check temporary override from Porygon Conversion 1 first)
	var weaknesses = defending_pokemon.metadata.get("weaknesses", [])
	for weakness in weaknesses:
		var weakness_type = weakness["type"]
		# If Conversion 1 changed this pokemon's weakness, use the override
		if defending_pokemon.temporary_weakness != "":
			weakness_type = defending_pokemon.temporary_weakness
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
	var resistances = defending_pokemon.metadata.get("resistances", [])
	for resistance in resistances:
		var resistance_type = resistance["type"]
		if defending_pokemon.temporary_resistance != "":
			resistance_type = defending_pokemon.temporary_resistance
		if resistance_type in attacking_types:
			var value = int(resistance["value"])
			damage = max(0, damage + value)
			modifiers_applied.append("RESISTANCE " + resistance["value"])
	
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
	
	# Apply PlusPower bonus (+10 per PlusPower attached to the attacker)
	# PlusPower is applied AFTER weakness/resistance per original TCG rules
	if damage > 0 and attacker_pokemon != null and attacker_pokemon.pluspower_count > 0:
		var pp_bonus = attacker_pokemon.pluspower_count * 10
		damage += pp_bonus
		modifiers_applied.append("PLUSPOWER +" + str(pp_bonus))
	
	# Apply Defender reduction (-20 damage if Defender is attached to the defending pokemon)
	if damage > 0 and defending_pokemon.defender_turns_remaining >= 0:
		var reduction = min(damage, 20)
		damage -= reduction
		modifiers_applied.append("DEFENDER -" + str(reduction))
	
	# Apply Kabuto Armor (halve damage, rounded down to nearest 10)
	if damage > 0:
		damage = powers_and_bodies.apply_kabuto_armor(defending_pokemon, damage)
	
	return {"damage": damage, "modifiers": modifiers_applied}

############################################################# Knockout functions ##################################################################
													
# Checks a single Pokemon's HP and if zero or below, animates KO and discards it
func check_and_handle_knockout(pokemon: card_object, is_opponent: bool) -> bool:
	if pokemon == null or pokemon.current_hp > 0:
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
	
	# BASE5: Dark Gyarados Final Beam - triggers when KO'd by attack
	var ko_abilities = pokemon.metadata.get("abilities", [])
	for ab in ko_abilities:
		if ab.get("name", "") == "Final Beam":
			# Find the attacker (the other side's active)
			var attacker = player_active_pokemon if is_opponent else opponent_active_pokemon
			await powers_and_bodies.check_final_beam(pokemon, attacker, is_opponent)
			break
	
	# Grab UI references before any animations that might free nodes
	var pokemon_ui = find_card_ui_for_object(pokemon)
	var pokemon_texture = get_card_texture(pokemon)
	
	# Animate energies before send_card_to_discard clears them
	if pokemon.attached_energies.size() > 0:
		await animate_energies_to_discard(pokemon.attached_energies.duplicate(), pokemon, is_opponent)
		display_active_pokemon_energies(is_opponent)
	
	# Use the container as fallback if pokemon_ui was freed
	var from_node = pokemon_ui if is_instance_valid(pokemon_ui) else active_container

	await animate_card_a_to_b(from_node, discard_node, 0.3, pokemon_texture, card_scales[10])
	
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
	
	# Fix 2: Invalidate CPU evaluation cache after board state change
	cpu_ai.invalidate_cpu_evaluation()
	
	await get_tree().create_timer(0.3).timeout
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
		var should_award_prize = not pokemon.no_prize_on_ko
		if await check_and_handle_knockout(pokemon, true):
			results["opponent_kos"] += 1
			if should_award_prize:
				opponent_prize_kos += 1
	
	for pokemon in player_to_check:
		var should_award_prize = not pokemon.no_prize_on_ko
		if await check_and_handle_knockout(pokemon, false):
			results["player_kos"] += 1
			if should_award_prize:
				player_prize_kos += 1
			
	for i in range(opponent_prize_kos):
		if player_prize_cards.size() > 0:
			opponent_blocker.visible = false
			await player_pick_prize_card()
			await prize_card_taken
			opponent_blocker.visible = true
	
	# Opponent takes prizes for player KOs
	for i in range(player_prize_kos):
		if opponent_prize_cards.size() > 0:
			await cpu_ai.opponent_take_prize_card()
	
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

		bench.erase(new_active)
		var new_texture = get_card_texture(new_active)
		
		await animate_card_a_to_b(bench_container, active_container, 0.3, new_texture, card_scales[9])
		
		new_active.current_location = "active"
		opponent_active_pokemon = new_active
		display_pokemon(true)
		display_active_pokemon_energies(true)
		display_active_pokemon_energies(false)
		await show_message("OPPONENT SET " + new_active.metadata["name"].to_upper() + " AS THEIR ACTIVE POKEMON!")
		# Fix 2: Invalidate CPU evaluation cache after replacement
		cpu_ai.invalidate_cpu_evaluation()
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

# Processes poison damage, burn damage/flip, and sleep wake-up between turns for one pokemon
func process_status_between_turns(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null:
		return

	var pokemon_name = pokemon.metadata.get("name", "Unknown")

	if pokemon.is_poisoned:
		pokemon.current_hp = max(0, pokemon.current_hp - pokemon.poison_damage)
		var label = "TOXIC" if pokemon.poison_damage == 20 else "POISON"
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_poison_sound)
		show_floating_label("-" + str(pokemon.poison_damage) + "HP", Vector2(530 if !is_opponent else 1030, 300), true)
		display_hp_circles_above_align(pokemon, is_opponent)
		await show_message(pokemon_name.to_upper() + " TAKES " + str(pokemon.poison_damage) + " " + label + " DAMAGE!")
		print("BETWEEN TURNS: ", pokemon_name, " took ", pokemon.poison_damage, " poison damage. HP: ", pokemon.current_hp)

	if pokemon.is_burned:
		if burn_rules == "base_set_burn_rules":
			await show_message(pokemon_name.to_upper() + " IS BURNED! FLIPPING COIN...")
			var coin = await flip_coin()
			if not coin:
				pokemon.current_hp = max(0, pokemon.current_hp - 20)
				await show_message(pokemon_name.to_upper() + " TAKES 20 BURN DAMAGE!")
				show_floating_label("-20HP", Vector2(530 if !is_opponent else 1030, 300), is_opponent)
				display_hp_circles_above_align(pokemon, is_opponent)
				print("BETWEEN TURNS: ", pokemon_name, " took 20 burn damage. HP: ", pokemon.current_hp)
			else:
				await show_message(pokemon_name.to_upper() + " AVOIDED BURN DAMAGE!")
				print("BETWEEN TURNS: ", pokemon_name, " avoided burn damage (heads)")
		elif burn_rules == "modern_era_burn_rules":
			pokemon.current_hp = max(0, pokemon.current_hp - 20)
			await show_message(pokemon_name.to_upper() + " TAKES 20 BURN DAMAGE!")
			show_floating_label("-20HP", Vector2(530 if !is_opponent else 1030, 300), is_opponent)
			display_hp_circles_above_align(pokemon, is_opponent)
			print("BETWEEN TURNS: ", pokemon_name, " took 20 burn damage. HP: ", pokemon.current_hp)
			await show_message("FLIPPING COIN TO CURE BURN...")
			var coin = await flip_coin()
			if coin:
				pokemon.is_burned = false
				await show_message(pokemon_name.to_upper() + " IS NO LONGER BURNED!")
				update_status_icons(pokemon, is_opponent)
				print("BETWEEN TURNS: ", pokemon_name, " cured of burn (heads)")

	if pokemon.special_condition == "Asleep":
		await show_message(pokemon_name.to_upper() + " IS ASLEEP! FLIPPING COIN...")
		var coin = await flip_coin()
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
		var coin = await flip_coin()
		if not coin:
			pokemon.current_hp = max(0, pokemon.current_hp - 20)
			await show_message("RETREAT FAILED! " + pokemon_name.to_upper() + " HURT ITSELF FOR 20 DAMAGE!")
			var label_x = 1030 if is_opponent else 530
			show_floating_label("-20HP", Vector2(label_x, 300), is_opponent)
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
		var coin = await flip_coin()
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
func can_evolve_from(evolving_pokemon: card_object, base_pokemon: card_object) -> bool:
	if evolving_pokemon.metadata.has("evolvesFrom"):
		return evolving_pokemon.metadata["evolvesFrom"] == base_pokemon.metadata.get("name", "")
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
	
	# Dark Muk Sticky Goo: opponent pays 2 more to retreat
	var is_player_pokemon = (pokemon == player_active_pokemon or pokemon in player_bench)
	cost += powers_and_bodies.get_sticky_goo_cost(is_player_pokemon)
	
	return cost

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
func load_opponent_data_by_name(opp_name: String):
	var file = FileAccess.open("res://Opponent_Data/Area_Opponents/Shallow_Beach_Opponents.json", FileAccess.READ)
	if file == null:
		print("Error loading file")
		return
	
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		print("JSON parse error")
		return
	
	var opponents = json.data["opponents"]
	for opponent in opponents:
		if opponent.get("name") == opp_name:
			opponent_data = opponent
			return
	
	print("Opponent with name ", opp_name, " not found")

# Play the correct music via the global SoundManager
func play_opponent_music():
	var music_file = opponent_data.get("music")
	if music_file == null:
		print("No music file specified")
		return
	
	var music_path = "res://Audio/BGM/" + music_file + ".ogg"
	SoundManagerScript.play_bgm(music_path, true)

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

	var pre_check = await check_confused_retreat(player_active_pokemon, false, "pre_energy")
	if not pre_check:
		retreat_bench_selection_active = false
		selected_card_for_action = null
		hide_selection_mode_display_main()
		display_hp_circles_above_align(player_active_pokemon, false)
		await check_all_knockouts()
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

	player_bench.erase(new_active)
	player_bench.append(player_active_pokemon)

	player_active_pokemon.current_location = "bench"
	new_active.current_location = "active"

	player_retreated_this_turn = true
	retreat_bench_selection_active = false
	selected_card_for_action = null
	
	var retreating_pokemon = player_active_pokemon  # Save ref before reassignment

	hide_selection_mode_display_main()
	await animate_retreat(player_active_pokemon, new_active, retreat_energies_selected, false)

	clear_all_statuses(player_active_pokemon, false)
	player_active_pokemon = new_active
	retreat_energies_selected.clear()

	display_pokemon(false)
	display_active_pokemon_energies(false)
	
	# Update Ditto Transform after active switch
	powers_and_bodies.update_ditto_transform(false)
	powers_and_bodies.update_ditto_transform(true)
	
	# Sinkhole (Dark Dugtrio): damage to retreating Pokemon
	await powers_and_bodies.check_sinkhole(retreating_pokemon, false)
	await check_all_knockouts()

# Moves a bench pokemon to the active slot after a knockout and triggers post-knockout signals
func handle_action_knockout_bench() -> void:
	var new_active = selected_card_for_action
	player_bench.erase(new_active)
	new_active.current_location = "active"
	player_active_pokemon = new_active

	knockout_bench_selection_active = false
	selected_card_for_action = null

	hide_selection_mode_display_main()

	var new_texture = get_card_texture(new_active)
	await animate_card_a_to_b(player_bench_container, player_active_container, 0.3, new_texture, card_scales[9])

	display_pokemon(false)
	display_active_pokemon_energies(false)
	display_hp_circles_above_align(player_active_pokemon, false)

	knockout_replacement_chosen.emit()

# Evolves the selected target pokemon, plays animations, and refreshes the display
func handle_action_evolution() -> void:
	var evo_card = evolution_card_awaiting_target
	var target_card = selected_card_for_action
	
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
	await animate_card_a_to_b(player_hand_container, target_node, 0.3, evo_texture, card_scale_to_animate)
	
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
					await animate_card_a_to_b(player_hand_container, player_bench_container, 0.3, bench_texture, card_scales[11])
					display_pokemon(false)
		
		"PLAY_TRAINER":
			var trainer_to_play = selected_card_for_action
			# Pre-validate that the trainer card can actually have an effect before playing it
			var validation_error = trainer_effects.validate_trainer_can_be_played(trainer_to_play, false)
			if validation_error != "":
				await show_message(validation_error)
				return
			hide_selection_mode_display_main()
			await trainer_effects.play_trainer_card(trainer_to_play, false)
		
		"ATTACH_ENERGY":
			start_energy_attachment()
		
		"EVOLVE":
			start_evolution()
		
		_:
			print("Unknown action: ", action_type)

# When the cancel button is clicked, hide everthing in card selection mode and show main screen again
func cancel_button_pressed_hide_selection_mode() -> void:
	
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
		if msgbox_container.visible or coin_container.visible: return
		if card_array.size() > 0:
			show_enlarged_array_selection_mode(card_array)

# Called when a card in selection mode is clicked
func this_card_clicked(clicked_card: card_object) -> void:
	# Don't allow card selection if action button is hidden (view-only mode) or messagebox is being displayed
	if msgbox_container.visible or coin_container.visible: return
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
		
		# TRAINER DISCARD SELECTION MODE
		elif trainer_discard_selection_active:
			select_card_in_ui(clicked_card)
			if clicked_card in trainer_discard_selected:
				action_button.text = "CONFIRM"
				action_button.disabled = false
				action_button.theme = theme_green
			else:
				action_button.text = "SELECT"
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
	
func _input(event: InputEvent) -> void:
	
	# Press the escape key to quit the game
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			end_game()
			
	if event is InputEventMouseButton and event.pressed:
		
		if msgbox_container.visible:
			message_acknowledged.emit()
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
		
		# If no card was clicked, clear selection
		if not clicked_on_card:
			
			# During multi-card selection modes (trainer discard, pokedex reorder), 
			# do NOT clear the selection or reset the action button
			if trainer_discard_selection_active or trainer_reorder_active:
				return

			if selected_card_for_action != null:
				var card_ui = find_card_ui_for_object(selected_card_for_action)
				if card_ui:
					card_ui.set_selected(false)
			
			selected_card_for_action = null
			update_action_button()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
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
	
	var opponent_name = GameState.current_opponent_name
	
	if GameDataManager.player_data.has("coin"):
		var coin_loaded_text = GameDataManager.player_data["coin"]
		tex_heads = load("res://Image_Assets/Coins/"+coin_loaded_text+".png")
		
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	
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
	main_buttons_container.get_node("button_main_attack").pressed.connect(show_attack_buttons)
	attack_buttons_container.visible = false
	
	main_buttons_container.get_node("button_main_power").pressed.connect(powers_and_bodies.open_power_menu)
	
	main_buttons_container.get_node("button_main_retreat").pressed.connect(start_retreat)
	
	main_buttons_container.get_node("button_main_endturn").pressed.connect(player_end_turn_checks)


	opponent_deck_name = GameState.current_opponent_deck
	load_opponent_data_by_name(GameState.current_opponent_name)
	play_opponent_music()

	# Load the player's deck name from their save data
	var pfile = FileAccess.open("res://Player_Data/Player_Current_Data.json", FileAccess.READ)
	var pdata = JSON.parse_string(pfile.get_as_text())
	pfile.close()
	player_deck_name = pdata["deck"]

	# BEGIN THE GAME SETUP
	setup_player()
	setup_opponent(opponent_deck_name)
	
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
