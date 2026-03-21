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
		var is_pokemon_mode = is_bench_view or (card_attach_mode_active or evolution_mode_active or retreat_mode_active or trainer_pokemon_selection_active or forced_switch_selection_active or knockout_bench_selection_active or damage_swap_mode_active or rain_dance_mode_active or energy_trans_mode_active or buzzap_mode_active or trainer_bench_token_discard_active)
		
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
	var is_pokemon_selection_mode = is_bench_view or (card_attach_mode_active or evolution_mode_active or retreat_mode_active or trainer_pokemon_selection_active or forced_switch_selection_active or knockout_bench_selection_active or damage_swap_mode_active or rain_dance_mode_active or energy_trans_mode_active or buzzap_mode_active or trainer_bench_token_discard_active)
	
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
	display_attached_trainer_cards(is_opponent)

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
	var player_hand_container = player_hand_container
	
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
	var opponent_hand_container = opponent_hand_container
	
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
	get_tree().quit()
	
# Main function to get metadata of any card passed to it. Goes off UID to lookup JSON data in game file
func get_card_metadata(card_uid: String):
	
	# Check the UID to make sure it's valid and if not error out 
	var split_uid = card_uid.split("-")
	if split_uid.size() != 2:
		print("Invalid UID provided, UID:", card_uid)
		return
	
	# Card details will be for example "Base1-1" "EX2-2"
	var card_set = split_uid[0]
	
	# the json data is in the same folder as the cardimages
	var card_set_json_metadata_path = "res://Card_Set_Data/" + card_set + ".json"
	
	# Open and read the metadata file
	var metadata_file = FileAccess.open(card_set_json_metadata_path, FileAccess.READ)
	
	# Check to make sure the file can be opened and error if it can't then return null
	if metadata_file == null:
		print("Error: Could not open metadata file at: ", card_set_json_metadata_path)
		return null
	
	# If the card set can be found then open the data and parse the json
	var raw_json_card_set_text = metadata_file.get_as_text()
	metadata_file.close()
	
	# Parse the JSON
	var parsed_card_set_json = JSON.new()
	if parsed_card_set_json.parse(raw_json_card_set_text) != OK:
		print("Error: Failed to parse metadata JSON")
		return null
	
	# If the json was succesfully parsed we now have the whole card set metadata as a variable to read
	var card_set_data = parsed_card_set_json.data
	
	# Now loop through the entire card set data and find the specific card by UID
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
	display_active_pokemon_energies()

	await get_tree().process_frame
	await play_energy_attached_effect(target_pokemon, energy_card)

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
		player_retreat_disabled = false
		# Discard PlusPower from player's active at end of player's turn
		if player_active_pokemon != null:
			await discard_pluspower_from_pokemon(player_active_pokemon, false)
		# Tick down Defender on opponent's pokemon (Defender discards at end of opponent's NEXT turn)
		await tick_defender_counters(true)
	else:
		clear_end_of_turn_statuses(opponent_active_pokemon, true)
		clear_defensive_statuses(player_active_pokemon, false)
		opponent_retreat_disabled = false
		# Discard PlusPower from opponent's active at end of opponent's turn
		if opponent_active_pokemon != null:
			await discard_pluspower_from_pokemon(opponent_active_pokemon, true)
		# Tick down Defender on player's pokemon
		await tick_defender_counters(false)
	
	if _should_bail():
		return
	
	# Reset power_used_this_turn for all pokemon
	if player_turn_just_ended:
		reset_power_used_flags(false)
	else:
		reset_power_used_flags(true)

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
		opponent_start_turn_checks()
	else:
		player_start_turn_checks()
		
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
	
	# Special energy: explicit name-based lookup since JSON has no structured provision data
	if "Special" in subtypes:
		match card_name:
			"Double Colorless Energy":
				return ["Colorless", "Colorless"]
			"Double Rainbow Energy":
				return ["Any", "Any"]
			_:
				print("Warning: Unknown special energy card: ", card_name)
				return []
	
	return []

# Check energy requirements of any attack passed to it and return true if requirements are met
func check_attack_requirements(attack_dict: Dictionary, pokemon_card: card_object) -> bool:
	if pokemon_card == null:
		return false
	return get_unmet_energy_count(attack_dict, pokemon_card) == 0

													######## Actual attacking functions ##########
													
# Parses the numeric base damage value from an attack's "damage" field string
# Strips non-numeric characters (e.g. "30+" becomes 30, "×2" etc.)
func parse_attack_base_damage(attack: Dictionary) -> int:
	var raw_damage = attack.get("damage", "0")
	var numeric_damage = ""
	for character in raw_damage:
		if character.is_valid_int():
			numeric_damage += character
	return int(numeric_damage) if numeric_damage != "" else 0

# Handles the confusion coin flip when an attacker is confused
# Returns true if the attack FAILS (attacker hurt itself), false if the attack can proceed
func handle_attack_confusion(attacker: card_object, is_opponent: bool) -> bool:
	if attacker.special_condition != "Confused":
		return false
	await show_message(attacker.metadata["name"].to_upper() + " IS CONFUSED! FLIPPING COIN...")
	var coin = await flip_coin()
	if coin:
		return false
	var self_damage = 20
	if confusion_rules == "modern_era_confusion_rules":
		self_damage = 30
	if confusion_rules == "base_set_confusion_rules":
		var self_types = attacker.metadata.get("types", ["Colorless"])
		var result = calculate_final_damage(self_damage, self_types, attacker)
		self_damage = result["damage"]
	attacker.current_hp = max(0, attacker.current_hp - self_damage)
	await show_message("THE ATTACK FAILED! " + attacker.metadata["name"].to_upper() + " HURT ITSELF FOR " + str(self_damage) + " DAMAGE!")
	var attacker_label_pos = Vector2(1030, 300) if is_opponent else Vector2(530, 300)
	show_floating_label("-" + str(self_damage) + "HP", attacker_label_pos, true)
	display_hp_circles_above_align(attacker, is_opponent)
	print("CONFUSED: ", attacker.metadata["name"], " hurt itself for ", self_damage)
	await check_all_knockouts()
	return true

# Handles the blind coin flip when an attacker cannot see
# Returns true if the attack FAILS (missed), false if the attack can proceed
func handle_attack_blind(attacker: card_object, is_opponent: bool) -> bool:
	if not attacker.is_blind:
		return false
	await show_message(attacker.metadata["name"].to_upper() + " CAN'T SEE! FLIPPING COIN...")
	var blind_coin = await flip_coin()
	if not blind_coin:
		await show_message("THE ATTACK FAILED!")
		attacker.is_blind = false
		update_status_icons(attacker, is_opponent)
		return true
	attacker.is_blind = false
	update_status_icons(attacker, is_opponent)
	return false

# Checks if the defender is fully invincible and blocks the attack entirely
# Returns true if the attack is blocked
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
func resolve_attack_variable_damage(attack: Dictionary, attacker: card_object, defender: card_object, is_opponent: bool) -> Dictionary:
	var base_damage = parse_attack_base_damage(attack)
	var damage_str = str(attack.get("damage", ""))
	var text = attack.get("text", "").to_lower()
	var attacker_name = attacker.metadata.get("name", "").to_lower()
	var resolved_damage = base_damage
	var messages: Array = []
	var flip_result: String = ""
	var attack_failed: bool = false
	
	# ---- CONDITION-GATED ATTACKS (must check first - attack may not proceed) ----
	if "can't use this attack" in text and "unless the defending" in text:
		if "asleep" in text and defender.special_condition != "Asleep":
			resolved_damage = 0
			attack_failed = true
			messages.append("ATTACK FAILED! TARGET NOT ASLEEP!")
			return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
		if "poisoned" in text and not defender.is_poisoned:
			resolved_damage = 0
			attack_failed = true
			messages.append("ATTACK FAILED! TARGET NOT POISONED!")
			return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
		if "confused" in text and defender.special_condition != "Confused":
			resolved_damage = 0
			attack_failed = true
			messages.append("ATTACK FAILED! TARGET NOT CONFUSED!")
			return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- COIN FLIP MULTIPLICATIVE DAMAGE (×) ----
	if ("×" in damage_str or "x" in damage_str or "X" in damage_str) and "times the number of heads" in text:
		var flip_count = 0
		var flip_until_tails = false
		
		if "flip a coin until you get tails" in text:
			flip_until_tails = true
		elif "flip 5 coins" in text:
			flip_count = 5
		elif "flip 4 coins" in text:
			flip_count = 4
		elif "flip 3 coins" in text:
			flip_count = 3
		elif "flip 2 coins" in text:
			flip_count = 2
		elif "flip a coin" in text:
			flip_count = 1
		
		var heads_count = 0
		# Use silent mode for multi-flips — just animate quickly, show summary at end
		var use_silent = (flip_count > 1 or flip_until_tails)
		if flip_until_tails:
			while true:
				var coin = await flip_coin(use_silent)
				if coin:
					heads_count += 1
				else:
					break
		else:
			for i in range(flip_count):
				var coin = await flip_coin(use_silent)
				if coin:
					heads_count += 1
		
		resolved_damage = base_damage * heads_count
		# Always show the final summary as a message
		messages.append("GOT " + str(heads_count) + " HEADS! " + str(resolved_damage) + " DAMAGE!")
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- "IF TAILS, THIS ATTACK DOES NOTHING" (Nidoran Horn Hazard) ----
	if "if tails, this attack does nothing" in text:
		var coin = await flip_coin()
		if not coin:
			resolved_damage = 0
			attack_failed = true
			flip_result = "tails"
			messages.append("ATTACK DOES NOTHING!")
		else:
			flip_result = "heads"
		# Check for Farfetch'd style permanent disable
		if "can't use this attack again" in text:
			var attack_name = attack.get("name", "")
			if "as long as" in text and "stays in play" in text:
				attacker.disabled_attacks[attack_name] = "while_in_play"
				print("ATTACK DISABLED: ", attack_name, " disabled while ", attacker_name, " is in play")
			else:
				attacker.disabled_attacks[attack_name] = "entire_game"
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- HEADS/TAILS BONUS DAMAGE (Nidoking Thrash "30+", Electabuzz Thunderpunch) ----
	if "+" in damage_str and "if heads" in text and "more damage" in text and "flip a coin" in text:
		var bonus = extract_number_before(text, "more damage")
		if bonus <= 0:
			bonus = 10
		var coin = await flip_coin()
		if coin:
			resolved_damage = base_damage + bonus
			flip_result = "heads"
			print("COIN BONUS: +", bonus, " damage")
		else:
			flip_result = "tails"
	
	# ---- HALF HP DAMAGE (Raticate Super Fang) ----
	if "equal to half" in text and "remaining hp" in text:
		var half_hp = defender.current_hp / 2.0
		resolved_damage = int(ceil(half_hp / 10.0)) * 10
		print("SUPER FANG: ", resolved_damage, " damage (half of ", defender.current_hp, " HP)")
		return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}
	
	# ---- PER DEFENDER ENERGY (Mewtwo Psychic) ----
	if "for each energy card attached to the defending" in text:
		var per_energy = 10
		var energy_pos = text.find("more damage for each energy")
		if energy_pos != -1:
			var extracted = extract_number_before(text, "more damage for each energy")
			if extracted > 0:
				per_energy = extracted
		var energy_count = defender.attached_energies.size()
		var bonus = per_energy * energy_count
		resolved_damage += bonus
		print("PER DEFENDER ENERGY: +", bonus, " (", energy_count, " energies)")
	
	# ---- EXTRA ENERGY BEYOND COST (Poliwag Water Gun, Blastoise Hydro Pump) ----
	if "more damage for each" in text and "not used to pay" in text:
		var bonus_energy_type = ""
		var type_keywords = ["water", "fire", "grass", "lightning", "psychic", "fighting"]
		for tkw in type_keywords:
			if tkw + " energy attached" in text and "not used to pay" in text:
				bonus_energy_type = tkw.capitalize()
				break
		
		if bonus_energy_type != "":
			# Count how many of that energy type are attached
			var total_of_type = 0
			for attached in attacker.attached_energies:
				var provided = get_energy_provided_by_card(attached)
				if bonus_energy_type in provided:
					total_of_type += 1
			
			# Calculate how many bonus-type energies are consumed by the FULL attack cost
			# This includes typed requirements AND colorless slots filled by bonus-type energy
			var cost = attack.get("cost", [])
			var typed_needed = 0
			var colorless_needed = 0
			for c in cost:
				if c == bonus_energy_type:
					typed_needed += 1
				elif c == "Colorless":
					colorless_needed += 1
			
			# Non-bonus energies fill colorless slots first
			var non_bonus_attached = attacker.attached_energies.size() - total_of_type
			var colorless_filled_by_non_bonus = min(colorless_needed, non_bonus_attached)
			var colorless_from_bonus = colorless_needed - colorless_filled_by_non_bonus
			
			var used_for_cost = typed_needed + colorless_from_bonus
			var extra_count = max(0, total_of_type - used_for_cost)
			
			# Parse the cap: "Extra Water Energy after the 2nd don't count"
			var cap = 99
			if "after the" in text and "don't count" in text:
				var after_pos = text.find("after the")
				var after_text = text.substr(after_pos + 10, 10)
				var cap_num = ""
				for ch in after_text:
					if ch.is_valid_int():
						cap_num += ch
					else:
						break
				if cap_num != "":
					# Cap is the max total bonus-type that count, minus those used for cost
					cap = max(0, int(cap_num) - used_for_cost)
			
			extra_count = min(extra_count, cap)
			
			var per_energy_bonus = 10
			var extracted_per = extract_number_before(text, "more damage for each")
			if extracted_per > 0:
				per_energy_bonus = extracted_per
			
			var bonus = per_energy_bonus * extra_count
			resolved_damage += bonus
			print("EXTRA ENERGY: +", bonus, " (", extra_count, " extra ", bonus_energy_type, " beyond ", used_for_cost, " used for cost)")
	
	# ---- PER DAMAGE COUNTER ON DEFENDING (Jynx Meditate, Mr. Mime Meditate) ----
	if "for each damage counter on the defending" in text:
		var per_counter = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per_counter = extracted
		var damage_counters = defender.get_damage_counters()
		var bonus = per_counter * damage_counters
		resolved_damage += bonus
		print("DEFENDER COUNTERS: +", bonus, " (", damage_counters, " counters)")
	
	# ---- PER DAMAGE COUNTER ON SELF - ADDITIONAL (Tauros Rampage) ----
	if ("for each damage counter on " + attacker_name) in text and "minus" not in text and "defending" not in text:
		var per_counter = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per_counter = extracted
		var damage_counters = attacker.get_damage_counters()
		var bonus = per_counter * damage_counters
		resolved_damage += bonus
		print("SELF COUNTERS: +", bonus, " (", damage_counters, " counters)")
	
	# ---- MINUS PER DAMAGE COUNTER ON SELF (Machoke Karate Chop "50-") ----
	if "-" in damage_str and ("minus" in text or "damage minus" in text) and "damage counter" in text:
		var per_counter = 10
		var extracted = extract_number_before(text, "damage for each damage counter")
		if extracted > 0:
			per_counter = extracted
		var damage_counters = attacker.get_damage_counters()
		var reduction = per_counter * damage_counters
		resolved_damage = max(0, base_damage - reduction)
		print("KARATE CHOP: -", reduction, " (", damage_counters, " counters)")
	
	# ---- PER BENCHED POKEMON (Wigglytuff Do the Wave) ----
	if "for each of your benched" in text:
		var per_bench = 10
		var extracted = extract_number_before(text, "more damage for each")
		if extracted > 0:
			per_bench = extracted
		var bench = opponent_bench if is_opponent else player_bench
		var bonus = per_bench * bench.size()
		resolved_damage += bonus
		print("BENCH BONUS: +", bonus, " (", bench.size(), " benched)")
	
	# ---- ADDITIONAL DAMAGE IF DEFENDER HAS STATUS ----
	if "if the defending pokémon is poisoned" in text and "more damage" in text:
		if defender.is_poisoned:
			var bonus = extract_number_before(text, "more damage")
			if bonus > 0:
				resolved_damage += bonus
				print("STATUS BONUS: +", bonus, " (poisoned)")
	if "if the defending pokémon is confused" in text and "more damage" in text:
		if defender.special_condition == "Confused":
			var bonus = extract_number_before(text, "more damage")
			if bonus > 0:
				resolved_damage += bonus
				print("STATUS BONUS: +", bonus, " (confused)")
	
	return {"damage": resolved_damage, "messages": messages, "flip_result": flip_result, "attack_failed": attack_failed}

# Displays modifier floating labels, the damage floating label, applies HP reduction,
# and updates the HP circles for the defender
func display_and_apply_attack_damage(attacker: card_object, defender: card_object, final_damage: int, modifiers: Array, is_opponent: bool, base_damage: int = -1) -> void:
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
		await check_strikes_back(defender, attacker, !is_opponent)

# Parses the attack text for card effects and applies them
# pre_flip_result: if a coin was already flipped during damage resolution, pass "heads" or "tails" to skip re-flipping
func process_attack_effects(attack: Dictionary, attacker: card_object, defender: card_object, is_opponent: bool, pre_flip_result: String = "") -> void:
	var attack_text = attack.get("text", "")
	var effects = parse_card_text_effects(attack_text, attacker.metadata.get("name", ""))
	if effects.size() > 0:
		await apply_card_text_effects(effects, attacker, defender, is_opponent, pre_flip_result)

# Applies damage from the chosen attack to the opponent's active pokemon and refreshes the HP display
func perform_attack(attack_index: int) -> void:
	if opponent_active_pokemon == null:
		print("Error: No opponent active pokemon to attack")
		return
	
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
	
	# METRONOME: Copy one of the opponent's attacks
	if "choose 1 of the defending" in text_lower and "copies that attack" in text_lower:
		hide_attack_buttons()
		await execute_metronome(player_active_pokemon, opponent_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# MIRROR MOVE: Replay the last attack received
	if "mirror move" in attack_name.to_lower() or ("was attacked last turn" in text_lower and "final result" in text_lower):
		hide_attack_buttons()
		await execute_mirror_move(player_active_pokemon, opponent_active_pokemon, false)
		await check_all_knockouts()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# AMNESIA: Disable one of the opponent's attacks
	if "choose 1 of the defending" in text_lower and "can't use that attack" in text_lower:
		hide_attack_buttons()
		await execute_amnesia(player_active_pokemon, opponent_active_pokemon, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# CONVERSION 1: Change opponent's weakness
	if "conversion 1" in attack_name.to_lower() or ("change it to a type" in text_lower and "weakness" in text_lower):
		hide_attack_buttons()
		await execute_conversion(player_active_pokemon, opponent_active_pokemon, false, true)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# CONVERSION 2: Change own resistance
	if "conversion 2" in attack_name.to_lower() or ("resistance to a type" in text_lower and "change" in text_lower):
		hide_attack_buttons()
		await execute_conversion(player_active_pokemon, opponent_active_pokemon, false, false)
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	if await handle_attack_confusion(player_active_pokemon, false):
		hide_attack_buttons()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	if await handle_attack_blind(player_active_pokemon, false):
		hide_attack_buttons()
		await get_tree().create_timer(0.5).timeout
		player_end_turn_checks()
		return
	
	# Resolve variable damage (coin flips, per-energy, per-counter, etc.) BEFORE weakness/resistance
	var variable_result = await resolve_attack_variable_damage(attack, player_active_pokemon, opponent_active_pokemon, false)
	var resolved_base = variable_result["damage"]
	var flip_result = variable_result["flip_result"]
	
	if variable_result["attack_failed"]:
		for msg in variable_result["messages"]:
			await show_message(msg)
		hide_attack_buttons()
		# Still process non-damage effects (like Farfetch'd disable)
		await process_attack_effects(attack, player_active_pokemon, opponent_active_pokemon, false, flip_result)
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
	
	await process_attack_effects(attack, player_active_pokemon, opponent_active_pokemon, false, flip_result)
	
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
	
	# Apply shielded damage threshold (Onix Harden / Mr. Mime Invisible Wall)
	# If the damage after weakness/resistance is AT OR BELOW the threshold, prevent it entirely
	if defending_pokemon.shielded_damage_threshold > 0 and damage > 0:
		if damage <= defending_pokemon.shielded_damage_threshold:
			modifiers_applied.append("NO DAMAGE")
			damage = 0
	
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
			await opponent_take_prize_card()
	
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
		var cpu_eval = build_cpu_evaluation()
		var new_active = pick_best_bench_replacement(opponent_bench, player_active_pokemon, cpu_eval)
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
func get_flip_context(text: String, effect_pos: int) -> String:
	var before = text.substr(0, effect_pos)
	var heads_pos = before.rfind("if heads")
	var tails_pos = before.rfind("if tails")
	if heads_pos == -1 and tails_pos == -1:
		return "none"
	if heads_pos > tails_pos:
		return "heads"
	return "tails"
		
# Searches for a defender status across three text patterns, returns position or -1
func find_defender_status_pos(text: String, status: String, has_defender_prefix: bool) -> int:
	var direct_pos = text.find("the defending pokémon is now " + status)
	if direct_pos != -1:
		return direct_pos
	if has_defender_prefix:
		var and_pos = text.find("and " + status)
		if and_pos != -1:
			return and_pos
		var it_pos = text.find("it is now " + status)
		if it_pos != -1:
			return it_pos
	return -1
	
# Applies a single parsed status effect to the correct pokemon and updates the UI
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
func extract_number_before(text: String, keyword: String) -> int:
	var pos = text.find(keyword)
	if pos == -1:
		return -1
	var i = pos - 1
	while i >= 0 and text[i] == " ":
		i -= 1
	var num_str = ""
	while i >= 0 and text[i].is_valid_int():
		num_str = text[i] + num_str
		i -= 1
	if num_str != "":
		return int(num_str)
	return -1

														######### Effects from text ##########
																
# Applies self-damage from an attack effect to the attacker
func apply_self_damage(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var damage = effect.get("damage", 0)
	attacker.current_hp = max(0, attacker.current_hp - damage)
	var name = attacker.metadata.get("name", "Unknown")
	var label_x = 1030 if is_opponent_attacking else 530
	await show_message(name.to_upper() + " DEALT " + str(damage) + " DAMAGE TO ITSELF!")
	show_floating_label("-" + str(damage) + "HP", Vector2(label_x, 300), true)
	display_hp_circles_above_align(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", name, " took ", damage, " self-damage. HP: ", attacker.current_hp)

# Discards energy from the attacker as an attack cost
func apply_energy_discard_self(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var count = effect.get("count", 1)
	var energy_type = effect.get("energy_type", "any")
	var name = attacker.metadata.get("name", "Unknown")
	var to_discard: Array = []

	if count == -1:
		to_discard = attacker.attached_energies.duplicate()
	else:
		for i in range(count):
			var found = false
			for j in range(attacker.attached_energies.size() - 1, -1, -1):
				var energy = attacker.attached_energies[j]
				if energy in to_discard:
					continue
				if energy_type == "any":
					to_discard.append(energy)
					found = true
					break
				else:
					var provided = get_energy_provided_by_card(energy)
					if energy_type in provided:
						to_discard.append(energy)
						found = true
						break
			if not found and energy_type != "any":
				for j in range(attacker.attached_energies.size() - 1, -1, -1):
					var energy = attacker.attached_energies[j]
					if energy not in to_discard:
						to_discard.append(energy)
						break

	var discard_node = opponent_discard_icon if is_opponent_attacking else player_discard_icon
	var from_node = find_card_ui_for_object(attacker)
	if from_node == null:
		from_node = opponent_active_container if is_opponent_attacking else player_active_container

	for energy in to_discard:
		var energy_texture = get_card_texture(energy)
		attacker.attached_energies.erase(energy)
		energy.current_location = "discard"
		var discard_pile = opponent_discard_pile if is_opponent_attacking else player_discard_pile
		discard_pile.append(energy)
		await animate_card_a_to_b(from_node, discard_node, 0.2, energy_texture, card_scales[10])
		display_active_pokemon_energies(is_opponent_attacking)

	# Update discard pile display immediately (no message box)
	update_discard_pile_display(is_opponent_attacking)
	display_active_pokemon_energies(is_opponent_attacking)
	print("EFFECT APPLIED: ", name, " discarded ", to_discard.size(), " energy cards")

# Discards energy from the defending pokemon - with selection UI for choosing which energy
func apply_energy_discard_defender(effect: Dictionary, defender: card_object, is_opponent_attacking: bool) -> void:
	if defender.attached_energies.size() == 0:
		print("EFFECT SKIPPED: Defender has no energy to discard")
		return
	var name = defender.metadata.get("name", "Unknown")
	var is_defender_player = is_opponent_attacking
	var is_defender_opponent = !is_opponent_attacking
	
	var energy_to_discard: card_object = null
	
	if is_defender_opponent:
		# Player is attacking — player chooses which of opponent's energies to discard
		defender_energy_discard_active = true
		show_enlarged_array_selection_mode(defender.attached_energies)
		cancel_button.visible = false
		header_label.text = "DISCARD AN ENERGY FROM " + name.to_upper()
		hint_label.text = "Choose an energy card to discard from the defending Pokemon"
		action_button.text = "DISCARD"
		action_button.disabled = true
		action_button.theme = theme_disabled
		await defender_energy_chosen
		energy_to_discard = selected_card_for_action
		defender_energy_discard_active = false
		hide_selection_mode_display_main()
	elif is_defender_player:
		# Opponent is attacking — player chooses which of their own energies to discard
		defender_energy_discard_active = true
		show_enlarged_array_selection_mode(defender.attached_energies)
		cancel_button.visible = false
		header_label.text = "DISCARD AN ENERGY FROM " + name.to_upper()
		hint_label.text = "Your opponent forces you to discard an energy card"
		action_button.text = "DISCARD"
		action_button.disabled = true
		action_button.theme = theme_disabled
		await defender_energy_chosen
		energy_to_discard = selected_card_for_action
		defender_energy_discard_active = false
		hide_selection_mode_display_main()
	
	if energy_to_discard != null:
		var energy_texture = get_card_texture(energy_to_discard)
		var from_node = find_card_ui_for_object(defender)
		var defender_is_opp = is_defender_opponent
		if from_node == null:
			from_node = opponent_active_container if defender_is_opp else player_active_container
		var discard_node = opponent_discard_icon if defender_is_opp else player_discard_icon
		
		defender.attached_energies.erase(energy_to_discard)
		energy_to_discard.current_location = "discard"
		var discard_pile = opponent_discard_pile if defender_is_opp else player_discard_pile
		discard_pile.append(energy_to_discard)
		
		await animate_card_a_to_b(from_node, discard_node, 0.2, energy_texture, card_scales[10])
		update_discard_pile_display(defender_is_opp)
		
		await show_message("AN ENERGY WAS DISCARDED FROM " + name.to_upper() + "!")
		# Refresh the defender's energy display (not the attacker's)
		display_active_pokemon_energies(defender_is_opp)
		print("EFFECT APPLIED: Discarded energy from ", name)

# Applies damage to benched pokemon based on target scope
# Applies damage to benched pokemon based on target scope, showing floating labels sequentially
func apply_bench_damage(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var bench_target = effect.get("target", "opponent_bench")
	var damage = effect.get("damage", 10)
	var benches_to_hit: Array = []

	if bench_target == "opponent_bench":
		if is_opponent_attacking:
			benches_to_hit.append({"bench": player_bench, "is_opponent": false})
		else:
			benches_to_hit.append({"bench": opponent_bench, "is_opponent": true})
	elif bench_target == "own_bench":
		if is_opponent_attacking:
			benches_to_hit.append({"bench": opponent_bench, "is_opponent": true})
		else:
			benches_to_hit.append({"bench": player_bench, "is_opponent": false})
	elif bench_target == "all_benches":
		benches_to_hit.append({"bench": player_bench, "is_opponent": false})
		benches_to_hit.append({"bench": opponent_bench, "is_opponent": true})

	for bench_info in benches_to_hit:
		var bench_container = opponent_bench_container if bench_info["is_opponent"] else player_bench_container
		for i in range(bench_info["bench"].size()):
			var pokemon = bench_info["bench"][i]
			pokemon.current_hp = max(0, pokemon.current_hp - damage)
			print("BENCH DAMAGE: ", pokemon.metadata.get("name", ""), " took ", damage, " damage. HP: ", pokemon.current_hp)
			
			# Show floating label at this bench pokemon's approximate position
			var bench_card_ui = null
			if i < bench_container.get_child_count():
				bench_card_ui = bench_container.get_child(i)
			if bench_card_ui != null and is_instance_valid(bench_card_ui):
				var label_pos = bench_card_ui.global_position + Vector2(0, -20)
				show_floating_label("-" + str(damage), label_pos, true)
			
			# Stagger labels by 0.1 seconds for visual sequence
			await get_tree().create_timer(0.1).timeout

# Sets the blind flag on the defending pokemon and updates icons
func apply_blind_effect(defender: card_object, is_opponent_attacking: bool) -> void:
	defender.is_blind = true
	var is_def_opponent = !is_opponent_attacking
	update_status_icons(defender, is_def_opponent)
	await show_message(defender.metadata.get("name", "").to_upper() + " CAN'T SEE! MUST FLIP TO ATTACK!")
	print("EFFECT APPLIED: ", defender.metadata.get("name", ""), " is now Blind")

# Sets the no_damage flag on the attacker and updates icons
func apply_no_damage_effect(attacker: card_object, is_opponent_attacking: bool) -> void:
	attacker.has_no_damage = true
	update_status_icons(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " has no_damage shield")

# Sets the invincible flag on the attacker and updates icons
func apply_invincible_effect(attacker: card_object, is_opponent_attacking: bool) -> void:
	attacker.is_invincible = true
	update_status_icons(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " is invincible")

# Sets the retreat lock on the defending pokemon
func apply_retreat_lock(defender: card_object, is_opponent_attacking: bool) -> void:
	if is_opponent_attacking:
		player_retreat_disabled = true
	else:
		opponent_retreat_disabled = true
	await show_message(defender.metadata.get("name", "").to_upper() + " CAN'T RETREAT!")
	print("EFFECT APPLIED: Retreat locked for ", defender.metadata.get("name", ""))

# Draws cards for the attacker
func apply_draw_effect(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var count = effect.get("count", 1)
	for i in range(count):
		await draw_card_from_deck(is_opponent_attacking)
	var who = "CPU" if is_opponent_attacking else "Player"
	await show_message(who.to_upper() + " DREW " + str(count) + " CARD(S)!")
	if is_opponent_attacking:
		refresh_hand_display(true)
	else:
		refresh_hand_display(false)
	print("EFFECT APPLIED: ", who, " drew ", count, " card(s)")

# Heals damage from the attacker
func apply_self_heal(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var name = attacker.metadata.get("name", "Unknown")
	var max_hp = int(attacker.metadata.get("hp", "0"))
	var amount = effect.get("amount", -1)
	var healed = 0

	if amount == -1:
		healed = max_hp - attacker.current_hp
		attacker.current_hp = max_hp
	else:
		var heal_hp = amount * 10
		healed = min(heal_hp, max_hp - attacker.current_hp)
		attacker.current_hp = min(max_hp, attacker.current_hp + heal_hp)

	if healed > 0:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		display_hp_circles_above_align(attacker, is_opponent_attacking)
		await show_message(name.to_upper() + " HEALED " + str(healed) + " HP!")
		print("EFFECT APPLIED: ", name, " healed ", healed, " HP. Now at: ", attacker.current_hp)
	else:
		print("EFFECT SKIPPED: ", name, " already at full HP")

# Applies the toxic upgrade setting poison damage to 20
func apply_toxic(defender: card_object, is_opponent_attacking: bool) -> void:
	defender.is_poisoned = true
	defender.poison_damage = 20
	var is_def_opponent = !is_opponent_attacking
	update_status_icons(defender, is_def_opponent)
	print("EFFECT APPLIED: ", defender.metadata.get("name", ""), " poison upgraded to Toxic (20 damage)")

# Sets destiny bond flag on the attacker
func apply_destiny_bond(attacker: card_object, is_opponent_attacking: bool) -> void:
	attacker.has_destiny_bond = true
	update_status_icons(attacker, is_opponent_attacking)
	await show_message(attacker.metadata.get("name", "").to_upper() + " IS BOUND BY DESTINY!")
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " has Destiny Bond")

# Sets the shielded damage threshold on the attacker (Onix Harden)
func apply_shielded_damage(effect: Dictionary, attacker: card_object, is_opponent_attacking: bool) -> void:
	var threshold = effect.get("threshold", 30)
	attacker.shielded_damage_threshold = threshold
	update_status_icons(attacker, is_opponent_attacking)
	print("EFFECT APPLIED: ", attacker.metadata.get("name", ""), " shielded damage threshold = ", threshold)

# Forces the defending player to switch their active pokemon with a bench pokemon
# chooser: "defender" = defender picks (Whirlwind), "attacker" = attacker picks (Lure)
func apply_force_switch(effect: Dictionary, is_opponent_attacking: bool) -> void:
	var target_bench = player_bench if is_opponent_attacking else opponent_bench
	var is_target_opponent = !is_opponent_attacking
	var chooser = effect.get("chooser", "defender")
	
	if target_bench.size() == 0:
		print("FORCE SWITCH: No bench pokemon available")
		return
	
	var new_active: card_object = null
	
	if is_target_opponent:
		# Target is the opponent (CPU)
		if chooser == "attacker":
			# Lure: PLAYER picks from opponent's bench
			forced_switch_selection_active = true
			show_enlarged_array_selection_mode(opponent_bench)
			cancel_button.visible = false
			header_label.text = "CHOOSE A POKEMON TO SWITCH IN!"
			hint_label.text = "Select an opponent's bench Pokemon to force into active"
			action_button.text = "FORCE SWITCH"
			action_button.disabled = true
			action_button.theme = theme_disabled
			await forced_switch_chosen
			new_active = selected_card_for_action
			forced_switch_selection_active = false
			hide_selection_mode_display_main()
		else:
			# Whirlwind: CPU picks its own bench replacement
			var cpu_eval = build_cpu_evaluation()
			new_active = pick_best_bench_replacement(opponent_bench, player_active_pokemon, cpu_eval)
			if new_active == null:
				new_active = opponent_bench[0]
		
		if new_active != null:
			var old_active = opponent_active_pokemon
			await show_message("OPPONENT WAS FORCED TO SWITCH TO " + new_active.metadata["name"].to_upper() + "!")
			
			# Animate the swap
			await animate_retreat(old_active, new_active, [], true)
			
			# Perform the swap
			opponent_bench.erase(new_active)
			opponent_bench.append(old_active)
			old_active.current_location = "bench"
			new_active.current_location = "active"
			opponent_active_pokemon = new_active
			clear_all_statuses(old_active, true)
			
			display_pokemon(true)
			display_active_pokemon_energies(true)
	else:
		# Target is the player
		if chooser == "attacker":
			# Lure: CPU picks from player's bench (pick the weakest)
			var worst_pokemon: card_object = null
			var worst_hp = 9999
			for bp in player_bench:
				if bp.current_hp < worst_hp:
					worst_hp = bp.current_hp
					worst_pokemon = bp
			new_active = worst_pokemon if worst_pokemon else player_bench[0]
		else:
			# Whirlwind: Player picks their own bench replacement
			forced_switch_selection_active = true
			show_enlarged_array_selection_mode(player_bench)
			cancel_button.visible = false
			header_label.text = "FORCED SWITCH!"
			hint_label.text = "Choose a bench Pokemon to switch in as your new active"
			action_button.text = "SWITCH IN"
			action_button.disabled = true
			action_button.theme = theme_disabled
			await forced_switch_chosen
			new_active = selected_card_for_action
			forced_switch_selection_active = false
			hide_selection_mode_display_main()
		
		if new_active != null:
			var old_active = player_active_pokemon
			await show_message("FORCED TO SWITCH TO " + new_active.metadata["name"].to_upper() + "!")
			
			await animate_retreat(old_active, new_active, [], false)
			
			player_bench.erase(new_active)
			player_bench.append(old_active)
			old_active.current_location = "bench"
			new_active.current_location = "active"
			player_active_pokemon = new_active
			clear_all_statuses(old_active, false)
			
			display_pokemon(false)
			display_active_pokemon_energies(false)

######################################################### SPECIAL ATTACK FUNCTIONS ############################################################

# METRONOME (Clefairy): Copy one of the opponent's attacks and execute it
func execute_metronome(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var defender_attacks = get_attacks_for_card(defender)
	if defender_attacks.size() == 0:
		await show_message("NO ATTACKS TO COPY!")
		return
	
	var chosen_attack: Dictionary = {}
	
	if is_opponent:
		# CPU chooses: pick the attack with highest damage potential
		var best_score = -999.0
		var cpu_types = attacker.metadata.get("types", ["Colorless"])
		for attack in defender_attacks:
			var dmg_range = get_attack_damage_range(attack, attacker, defender)
			var result = calculate_final_damage(dmg_range["max"], cpu_types, defender)
			var score = float(result["damage"])
			var parsed = parse_card_text_effects(attack.get("text", ""), attacker.metadata.get("name", ""))
			score += score_parsed_effects(parsed, defender)
			if score > best_score:
				best_score = score
				chosen_attack = attack
	else:
		# Player chooses: show attack names as buttons
		special_attack_selection_active = true
		buttons_only_blocker.visible = true
		
		# Clear and show attack buttons
		for child in attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				continue
			child.queue_free()
		
		attack_buttons_container.visible = true
		main_buttons_container.visible = false
		# Hide the cancel button within the attack buttons container
		for child in attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = false
		
		for i in range(defender_attacks.size()):
			var atk = defender_attacks[i]
			var btn = Button.new()
			btn.text = atk.get("name", "Attack") + " (" + str(atk.get("damage", "0")) + ")"
			btn.custom_minimum_size = Vector2(350, 50)
			btn.theme = theme_green
			attack_buttons_container.add_child(btn)
			btn.pressed.connect(func(): special_attack_selected.emit(i))
		
		var selected_index = await special_attack_selected
		chosen_attack = defender_attacks[selected_index]
		
		# Clean up buttons
		for child in attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = true
				continue
			child.queue_free()
		attack_buttons_container.visible = false
		main_buttons_container.visible = true
		special_attack_selection_active = false
		buttons_only_blocker.visible = false
	
	await show_message(attacker.metadata["name"].to_upper() + " COPIES " + chosen_attack.get("name", "").to_upper() + "!")
	
	# Execute the copied attack (ignore energy costs and energy discard requirements)
	var variable_result = await resolve_attack_variable_damage(chosen_attack, attacker, defender, is_opponent)
	var resolved_base = variable_result["damage"]
	var flip_result = variable_result["flip_result"]
	
	if variable_result["attack_failed"]:
		for msg in variable_result["messages"]:
			await show_message(msg)
		return
	
	for msg in variable_result["messages"]:
		await show_message(msg)
	
	# Use attacker's own type for Metronome (Clefairy stays Colorless)
	var attacking_types = attacker.metadata.get("types", ["Colorless"])
	var result = calculate_final_damage(resolved_base, attacking_types, defender)
	var final_damage = result["damage"]
	
	if defender.is_invincible:
		var inv_label_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
		show_floating_label("NO EFFECT", inv_label_pos, true)
		return
	
	final_damage = apply_defender_no_damage_shield(defender, final_damage, !is_opponent)
	await display_and_apply_attack_damage(attacker, defender, final_damage, result["modifiers"], is_opponent, resolved_base)
	
	# Apply non-discard effects from the copied attack
	var attack_text = chosen_attack.get("text", "")
	var effects = parse_card_text_effects(attack_text, attacker.metadata.get("name", ""))
	var filtered_effects = []
	for effect in effects:
		if effect["type"] != "energy_discard_self":
			filtered_effects.append(effect)
	if filtered_effects.size() > 0:
		await apply_card_text_effects(filtered_effects, attacker, defender, is_opponent, flip_result)

# MIRROR MOVE (Pidgeotto): Replay the last attack received
func execute_mirror_move(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var last_attack = last_attack_on_opponent if is_opponent else last_attack_on_player
	
	if last_attack.is_empty() or not last_attack.has("damage"):
		await show_message("MIRROR MOVE FAILED! NO ATTACK TO MIRROR!")
		return
	
	var mirrored_damage = last_attack["damage"]
	var mirrored_attack = last_attack.get("attack", {})
	
	await show_message(attacker.metadata["name"].to_upper() + " MIRRORS THE LAST ATTACK FOR " + str(mirrored_damage) + " DAMAGE!")
	
	if defender.is_invincible:
		var inv_label_pos = Vector2(530, 300) if !is_opponent else Vector2(1030, 300)
		show_floating_label("NO EFFECT", inv_label_pos, true)
		return
	
	mirrored_damage = apply_defender_no_damage_shield(defender, mirrored_damage, !is_opponent)
	
	if mirrored_damage > 0:
		var defender_label_pos = Vector2(530, 300) if is_opponent else Vector2(1030, 300)
		show_floating_label("-" + str(mirrored_damage) + "HP", defender_label_pos, true)
		defender.current_hp = max(0, defender.current_hp - mirrored_damage)
		display_hp_circles_above_align(defender, !is_opponent)
	
	if mirrored_attack.has("text"):
		var effects = parse_card_text_effects(mirrored_attack.get("text", ""), attacker.metadata.get("name", ""))
		if effects.size() > 0:
			await apply_card_text_effects(effects, attacker, defender, is_opponent)

# AMNESIA (Poliwhirl): Disable one of the opponent's attacks for next turn
func execute_amnesia(attacker: card_object, defender: card_object, is_opponent: bool) -> void:
	var defender_attacks = get_attacks_for_card(defender)
	if defender_attacks.size() == 0:
		await show_message("NO ATTACKS TO DISABLE!")
		return
	
	var chosen_attack_name: String = ""
	
	if is_opponent:
		var best_score = -999.0
		var defender_types = defender.metadata.get("types", ["Colorless"])
		for attack in defender_attacks:
			var dmg_range = get_attack_damage_range(attack, defender, attacker)
			var result = calculate_final_damage(dmg_range["max"], defender_types, attacker)
			var score = float(result["damage"])
			if score > best_score:
				best_score = score
				chosen_attack_name = attack.get("name", "")
	else:
		special_attack_selection_active = true
		buttons_only_blocker.visible = true
		
		for child in attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				continue
			child.queue_free()
		
		attack_buttons_container.visible = true
		main_buttons_container.visible = false
		# Hide the cancel button within the attack buttons container
		for child in attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = false
		
		for i in range(defender_attacks.size()):
			var atk = defender_attacks[i]
			var btn = Button.new()
			btn.text = "DISABLE: " + atk.get("name", "Attack")
			btn.custom_minimum_size = Vector2(350, 50)
			btn.theme = theme_green
			attack_buttons_container.add_child(btn)
			btn.pressed.connect(func(): special_attack_selected.emit(i))
		
		var selected_index = await special_attack_selected
		chosen_attack_name = defender_attacks[selected_index].get("name", "")
		
		for child in attack_buttons_container.get_children():
			if child.name == "cancel_attack_mode_button":
				child.visible = true
				continue
			child.queue_free()
		attack_buttons_container.visible = false
		main_buttons_container.visible = true
		special_attack_selection_active = false
		buttons_only_blocker.visible = false
	
	if chosen_attack_name != "":
		defender.disabled_attacks[chosen_attack_name] = "end_of_turn"
		await show_message(defender.metadata["name"].to_upper() + " FORGOT HOW TO USE " + chosen_attack_name.to_upper() + "!")
		print("AMNESIA: Disabled ", chosen_attack_name, " on ", defender.metadata["name"])

# CONVERSION (Porygon): Change weakness (1) or resistance (2) type
func execute_conversion(attacker: card_object, defender: card_object, is_opponent: bool, is_conversion_1: bool) -> void:
	var energy_types = ["Fighting", "Fire", "Grass", "Lightning", "Psychic", "Water"]
	var chosen_type: String = ""
	
	# Conversion 1: Only works if the defending pokemon has a weakness
	if is_conversion_1:
		var weaknesses = defender.metadata.get("weaknesses", [])
		if weaknesses.size() == 0:
			await show_message("CONVERSION FAILED! OPPONENT HAS NO WEAKNESS!")
			return
	
	if is_opponent:
		if is_conversion_1:
			var cpu_type = attacker.metadata.get("types", ["Colorless"])[0]
			chosen_type = cpu_type if cpu_type in energy_types else energy_types[0]
		else:
			var player_type = defender.metadata.get("types", ["Colorless"])[0]
			if player_type != "Colorless" and player_type in energy_types:
				chosen_type = player_type
			else:
				chosen_type = energy_types[0]
	else:
		var energy_uids = ["base1-97", "base1-98", "base1-99", "base1-100", "base1-101", "base1-102"]
		var energy_cards: Array = []
		for uid in energy_uids:
			var meta = get_card_metadata(uid)
			if meta != null:
				var card = card_object.new(uid, meta)
				energy_cards.append(card)
		
		if energy_cards.size() > 0:
			energy_type_selection_active = true
			show_enlarged_array_selection_mode(energy_cards)
			cancel_button.visible = false
			if is_conversion_1:
				header_label.text = "CONVERSION 1: CHANGE OPPONENT'S WEAKNESS"
			else:
				header_label.text = "CONVERSION 2: CHANGE YOUR RESISTANCE"
			hint_label.text = "Select an energy type"
			action_button.text = "SELECT TYPE"
			action_button.disabled = true
			action_button.theme = theme_disabled
			await energy_type_selected
			chosen_type = selected_card_for_action.metadata.get("name", "").replace(" Energy", "").strip_edges() if selected_card_for_action else ""
			energy_type_selection_active = false
			hide_selection_mode_display_main()
	
	if chosen_type != "" and chosen_type != "Colorless":
		if is_conversion_1:
			defender.temporary_weakness = chosen_type
			await show_message(defender.metadata["name"].to_upper() + "'S WEAKNESS CHANGED TO " + chosen_type.to_upper() + "!")
		else:
			attacker.temporary_resistance = chosen_type
			await show_message(attacker.metadata["name"].to_upper() + "'S RESISTANCE CHANGED TO " + chosen_type.to_upper() + "!")
	else:
		await show_message("CONVERSION FAILED!")

												######### Main effect parsers helpers ##########

# Parses attack effect text and returns an array of effect dictionaries for evaluation or application
func parse_card_text_effects(attack_text: String, attacker_name: String) -> Array:
	if attack_text == "":
		return []

	var effects: Array = []
	var text = attack_text.to_lower()
	var lower_name = attacker_name.to_lower()
	var has_defender_prefix = "the defending pokémon is now" in text

	# --- STATUS: Defender status conditions ---
	var defender_statuses = ["paralyzed", "asleep", "poisoned", "confused", "burned"]
	for status in defender_statuses:
		var pos = find_defender_status_pos(text, status, has_defender_prefix)
		if pos != -1:
			var flip = get_flip_context(text, pos)
			effects.append({"type": "status", "target": "defender", "status": status.capitalize(), "flip": flip})
			print("EFFECT PARSED: Status -> Defender ", status.capitalize(), " | Flip: ", flip)

	# --- STATUS: Self-inflicted status ---
	var self_statuses = ["confused", "asleep", "poisoned", "paralyzed", "burned"]
	for status in self_statuses:
		if lower_name + " is now " + status in text:
			var pos = text.find(lower_name + " is now " + status)
			var flip = get_flip_context(text, pos)
			effects.append({"type": "status", "target": "self", "status": status.capitalize(), "flip": flip})
			print("EFFECT PARSED: Status -> Self ", status.capitalize(), " | Flip: ", flip)

	# --- TOXIC: Enhanced poison (20 instead of 10) ---
	if "20 poison damage instead of 10" in text or "put 2 damage counters instead of 1" in text:
		var flip = get_flip_context(text, text.find("instead"))
		effects.append({"type": "toxic", "target": "defender", "flip": flip})
		print("EFFECT PARSED: Toxic upgrade | Flip: ", flip)

	# --- SELF DAMAGE: Attacker damages itself ---
	if lower_name in text and "damage to itself" in text:
		var damage = extract_number_before(text, "damage to itself")
		if damage > 0:
			var flip = get_flip_context(text, text.find("damage to itself"))
			effects.append({"type": "self_damage", "target": "self", "damage": damage, "flip": flip})
			print("EFFECT PARSED: Self Damage -> ", damage, " | Flip: ", flip)

	# --- ENERGY DISCARD SELF: Attacker discards own energy ---
	if "discard" in text and "energy" in text and ("attached to " + lower_name) in text:
		var discard_pos = text.find("discard")
		var flip = get_flip_context(text, discard_pos)
		var count = 0
		var energy_type = "any"
		if "discard all" in text and ("energy cards attached to " + lower_name) in text:
			count = -1
		elif "discard a " in text or "discard 1 " in text:
			count = 1
		elif "discard 2" in text:
			count = 2
		elif "discard 3" in text:
			count = 3
		else:
			count = 1
		var type_keywords = ["fire", "water", "grass", "lightning", "psychic", "fighting", "darkness", "metal"]
		for type_name in type_keywords:
			if "discard" in text and type_name + " energy" in text and ("attached to " + lower_name) in text:
				energy_type = type_name.capitalize()
				break
		effects.append({"type": "energy_discard_self", "target": "self", "count": count, "energy_type": energy_type, "flip": flip})
		print("EFFECT PARSED: Energy Discard Self -> Count: ", count, " Type: ", energy_type, " | Flip: ", flip)

	# --- ENERGY DISCARD DEFENDER: Remove energy from defending pokemon ---
	if "discard" in text and "energy" in text and "attached to" in text:
		var is_defender_energy = false
		if "attached to the defending" in text:
			is_defender_energy = true
		if "attached to it" in text and "defending" in text:
			is_defender_energy = true
		if "choose 1 of them and discard it" in text and "energy cards attached to it" in text:
			is_defender_energy = true
		if is_defender_energy:
			var discard_pos = text.find("discard")
			var flip = get_flip_context(text, discard_pos)
			effects.append({"type": "energy_discard_defender", "target": "defender", "count": 1, "flip": flip})
			print("EFFECT PARSED: Energy Discard Defender | Flip: ", flip)

	# --- BENCH DAMAGE: Damage to benched pokemon ---
	if "damage to each" in text and "bench" in text:
		# Special case: Articuno-style where heads = opponent bench, tails = own bench
		if "your opponent's benched" in text and "your own benched" in text:
			var damage = extract_number_before(text, "damage to each")
			if damage <= 0:
				damage = 10
			effects.append({"type": "bench_damage", "target": "opponent_bench", "damage": damage, "flip": "heads"})
			effects.append({"type": "bench_damage", "target": "own_bench", "damage": damage, "flip": "tails"})
			print("EFFECT PARSED: Bench Damage -> COIN FLIP: heads=opponent, tails=own for ", damage)
		else:
			var bench_target = "all_benches"
			if "your opponent's benched" in text or "opponent's benched" in text:
				bench_target = "opponent_bench"
			elif "your own benched" in text:
				bench_target = "own_bench"
			elif "each player's bench" in text:
				bench_target = "all_benches"
			var damage = extract_number_before(text, "damage to each")
			if damage <= 0:
				damage = 10
			var flip = get_flip_context(text, text.find("damage to each"))
			effects.append({"type": "bench_damage", "target": bench_target, "damage": damage, "flip": flip})
			print("EFFECT PARSED: Bench Damage -> ", bench_target, " for ", damage, " | Flip: ", flip)

	# --- BLIND / SMOKESCREEN: Defender must flip to attack next turn ---
	if "tries to attack" in text and "if tails" in text and "does nothing" in text:
		effects.append({"type": "blind", "target": "defender", "flip": "none"})
		print("EFFECT PARSED: Blind / Smokescreen -> Defender")

	# --- INVINCIBLE: Prevent all effects including damage next turn ---
	if "prevent all effects of attacks, including damage" in text:
		var flip = get_flip_context(text, text.find("prevent all effects"))
		effects.append({"type": "invincible", "target": "self", "flip": flip})
		print("EFFECT PARSED: Invincible -> Self | Flip: ", flip)

	# --- NO DAMAGE: Prevent damage only next turn (other effects still happen) ---
	if "prevent all damage done to" in text and "prevent all effects of attacks" not in text:
		var flip = get_flip_context(text, text.find("prevent all damage"))
		effects.append({"type": "no_damage", "target": "self", "flip": flip})
		print("EFFECT PARSED: No Damage -> Self | Flip: ", flip)

	# --- RETREAT LOCK: Defender can't retreat ---
	if "can't retreat" in text and "defending" in text:
		var flip = get_flip_context(text, text.find("can't retreat"))
		effects.append({"type": "retreat_lock", "target": "defender", "flip": flip})
		print("EFFECT PARSED: Retreat Lock -> Defender | Flip: ", flip)

	# --- DRAW CARDS ---
	if "draw a card" in text and "your opponent" not in text:
		effects.append({"type": "draw", "target": "self", "count": 1, "flip": "none"})
		print("EFFECT PARSED: Draw 1 card")
	elif "draw " in text and "cards" in text and "your opponent" not in text:
		var count = extract_number_before(text, "cards")
		if count > 0:
			effects.append({"type": "draw", "target": "self", "count": count, "flip": "none"})
			print("EFFECT PARSED: Draw ", count, " cards")

	# --- SELF HEAL ALL: Remove all damage from attacker ---
	if "remove all damage counters from " + lower_name in text:
		var flip = get_flip_context(text, text.find("remove all damage"))
		effects.append({"type": "self_heal", "target": "self", "amount": -1, "flip": flip})
		print("EFFECT PARSED: Self Heal All | Flip: ", flip)

	# --- SELF HEAL PARTIAL: Remove X damage counters from attacker ---
	if "remove" in text and "damage counter" in text and lower_name in text and "remove all" not in text:
		var amount = extract_number_before(text, "damage counter")
		if amount > 0:
			var flip = get_flip_context(text, text.find("remove"))
			effects.append({"type": "self_heal", "target": "self", "amount": amount, "flip": flip})
			print("EFFECT PARSED: Self Heal ", amount, " counters | Flip: ", flip)

	# --- DESTINY BOND ---
	if "knocks out " + lower_name in text and "knock out that" in text:
		effects.append({"type": "destiny_bond", "target": "self", "flip": "none"})
		print("EFFECT PARSED: Destiny Bond -> Self")

	# --- SHIELDED DAMAGE (Onix Harden): Prevent damage at or below threshold ---
	# "During your opponent's next turn, whenever 30 or less damage is done to Onix, prevent that damage."
	if "or less damage is done to" in text and "prevent that damage" in text:
		var threshold = extract_number_before(text, "or less damage")
		if threshold > 0:
			effects.append({"type": "shielded_damage", "target": "self", "threshold": threshold, "flip": "none"})
			print("EFFECT PARSED: Shielded Damage -> threshold ", threshold)

	# --- FORCE SWITCH (Pidgey/Pidgeotto Whirlwind, Ninetales Lure) ---
	# Whirlwind: "he or she chooses 1" = defender picks
	# Lure: "choose 1 of them and switch it" (without "he or she") = attacker picks
	if ("switches it with" in text or "switch it with" in text) and ("benched" in text or "bench" in text):
		if "defending pokémon" in text or "active pokémon" in text:
			var flip = get_flip_context(text, text.find("switch"))
			var chooser = "defender"
			# "he or she chooses" = defender picks (Whirlwind)
			# Otherwise attacker picks (Lure)
			if "he or she chooses" not in text and "they choose" not in text:
				chooser = "attacker"
			effects.append({"type": "force_switch", "target": "defender", "chooser": chooser, "flip": flip})
			print("EFFECT PARSED: Force Switch -> Defender | Chooser: ", chooser, " | Flip: ", flip)

	if effects.size() == 0:
		print("EFFECT PARSED: No recognised effects in: ", text.left(80))

	return effects
	
# Applies parsed effect dictionaries to the game state with coin flip gating
# pre_flip_result: if a coin was already flipped during damage resolution, use this instead of re-flipping
func apply_card_text_effects(effects: Array, attacker: card_object, defender: card_object, is_opponent_attacking: bool, pre_flip_result: String = "") -> void:
	var flip_result: String = pre_flip_result
	var needs_flip: bool = false
	
	# Only flip if we don't already have a result from damage resolution
	if flip_result == "":
		for effect in effects:
			if effect.get("flip", "none") != "none":
				needs_flip = true
				break

		if needs_flip:
			var coin = await flip_coin()
			flip_result = "heads" if coin else "tails"

	for effect in effects:
		var required_flip = effect.get("flip", "none")
		if required_flip != "none" and flip_result != required_flip:
			print("EFFECT SKIPPED: Needed ", required_flip, " but got ", flip_result)
			continue

		if effect.get("target") == "defender" and defender.is_invincible:
			print("EFFECT BLOCKED: Defender is invincible - skipping ", effect["type"])
			continue

		if effect["type"] == "status":
			await apply_status_effect(effect, attacker, defender, is_opponent_attacking)
		if effect["type"] == "toxic":
			await apply_toxic(defender, is_opponent_attacking)
		if effect["type"] == "self_damage":
			await apply_self_damage(effect, attacker, is_opponent_attacking)
		if effect["type"] == "energy_discard_self":
			await apply_energy_discard_self(effect, attacker, is_opponent_attacking)
		if effect["type"] == "energy_discard_defender":
			await apply_energy_discard_defender(effect, defender, is_opponent_attacking)
		if effect["type"] == "bench_damage":
			await apply_bench_damage(effect, is_opponent_attacking)
		if effect["type"] == "blind":
			await apply_blind_effect(defender, is_opponent_attacking)
		if effect["type"] == "no_damage":
			apply_no_damage_effect(attacker, is_opponent_attacking)
		if effect["type"] == "invincible":
			apply_invincible_effect(attacker, is_opponent_attacking)
		if effect["type"] == "retreat_lock":
			await apply_retreat_lock(defender, is_opponent_attacking)
		if effect["type"] == "draw":
			await apply_draw_effect(effect, is_opponent_attacking)
		if effect["type"] == "self_heal":
			await apply_self_heal(effect, attacker, is_opponent_attacking)
		if effect["type"] == "destiny_bond":
			await apply_destiny_bond(attacker, is_opponent_attacking)
		if effect["type"] == "shielded_damage":
			apply_shielded_damage(effect, attacker, is_opponent_attacking)
		if effect["type"] == "force_switch":
			await apply_force_switch(effect, is_opponent_attacking)
			
########################################################### END EFFECT PARSING FUNCTIONS #############################################################
######################################################################################################################################################

#                ##      ##      ########  ####    ##  ########
#               ####    ####        ##     ## ##   ##     ##
#              ##  ##  ##  ##       ##     ##  ##  ##     ##
#             ##    ####    ##      ##     ##   ## ##     ##
#            ##      ##      ##  ########  ##    ####   #######

######################################################################################################################################################
################################################### SMALL FUNCTIONS TO HELP WITH CODE READABILITY ####################################################

# Function to get all basic pokemon from a given array of cards
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
	return pokemon.metadata.get("retreatCost", []).size()

# Loads the small card image texture for any card object by its UID
func get_card_texture(card: card_object) -> Texture2D:
	var card_set = card.uid.split("-")[0]
	return load("res://Image_Assets/Card_Image_Library/" + card_set + "/Small/" + card.uid + ".png")	

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
func get_minimum_cost_attack(pokemon_card: card_object) -> Dictionary:
	if not pokemon_card.metadata.has("attacks") or pokemon_card.metadata["attacks"].size() == 0:
		return {}
	
	var min_cost_attack = null
	var min_cost = 999
	
	for attack in pokemon_card.metadata["attacks"]:
		var cost = int(attack.get("convertedEnergyCost", 999))
		if cost < min_cost:
			min_cost = cost
			min_cost_attack = attack
	
	if min_cost_attack == null:
		return {}
	
	return {
		"cost": min_cost,
		"damage": parse_attack_base_damage(min_cost_attack),
		"attack_name": min_cost_attack.get("name", ""),
		"text": min_cost_attack.get("text", "")
	}
	
# Helper function to get the highest damage attack and return all its data
func get_maximum_damage_attack(pokemon_card: card_object) -> Dictionary:
	if not pokemon_card.metadata.has("attacks") or pokemon_card.metadata["attacks"].size() == 0:
		return {}
	
	var max_damage = 0
	var max_damage_attack = null
	
	for attack in pokemon_card.metadata["attacks"]:
		var damage = parse_attack_base_damage(attack)
		if damage > max_damage:
			max_damage = damage
			max_damage_attack = attack
	
	if max_damage_attack == null:
		return {}
	
	return {
		"damage": max_damage,
		"cost": int(max_damage_attack.get("convertedEnergyCost", 1)),
		"text": max_damage_attack.get("text", ""),
		"attack_name": max_damage_attack.get("name", "")
	}

# Main function to evaluate a basic pokemon and return a score by calling criterion 1-5 and returns the total score with breakdown reasoning
func evaluate_opponents_start_setup_pokemon_choices(basic_pokemon: card_object, hand: Array) -> Dictionary:
	var total_score = 0.0
	var score_breakdown = []
	
	# Apply all 5 criteria
	var criterion_1 = criterion_1_single_energy_attack(basic_pokemon)
	total_score += criterion_1.get("score_change", 0)
	score_breakdown.append(criterion_1.get("reason", ""))
	
	var criterion_2 = criterion_2_evolution_available(basic_pokemon, hand)
	total_score += criterion_2.get("score_change", 0)
	score_breakdown.append(criterion_2.get("reason", ""))
	
	var criterion_3 = criterion_3_energy_type_match(basic_pokemon, hand)
	total_score += criterion_3.get("score_change", 0)
	score_breakdown.append(criterion_3.get("reason", ""))
	
	var criterion_4 = criterion_4_pokemon_hp(basic_pokemon)
	total_score += criterion_4.get("score_change", 0)
	score_breakdown.append(criterion_4.get("reason", ""))
	
	var criterion_5 = criterion_5_attack_damage(basic_pokemon)
	total_score += criterion_5.get("score_change", 0)
	score_breakdown.append(criterion_5.get("reason", ""))
	
	return {
		"pokemon_name": basic_pokemon.metadata.get("name", "Unknown"),
		"total_score": total_score,
		"breakdown": score_breakdown
	}

# Evaluates all basic pokemon, returns highest scorer as active and next 3 as bench
func select_opponent_pokemon_for_setup(hand: Array) -> Dictionary:
	var all_basic_pokemon = get_all_basic_pokemon(hand)
	
	if all_basic_pokemon.size() == 0:
		print("Error: No basic pokemon found in hand")
		return {"active": null, "bench": []}
	
	# Score all basic pokemon
	var scored_pokemon = []
	for pokemon in all_basic_pokemon:
		var evaluation = evaluate_opponents_start_setup_pokemon_choices(pokemon, hand)
		scored_pokemon.append({
			"pokemon": pokemon,
			"score": evaluation.get("total_score", 0),
			"breakdown": evaluation.get("breakdown", [])
		})
	
	# Sort by score (highest first)
	scored_pokemon.sort_custom(func(a, b): return a["score"] > b["score"])
	
	# First is active, next up to 3 are bench
	var active_pokemon = scored_pokemon[0]["pokemon"]
	var bench_pokemon = []
	for i in range(1, min(4, scored_pokemon.size())):
		bench_pokemon.append(scored_pokemon[i]["pokemon"])
	
	# Print results
	print("Opponent AI selected active: " + active_pokemon.metadata.get("name", "Unknown") + " (Score: " + str(int(scored_pokemon[0]["score"])) + ")")
	for reason in scored_pokemon[0]["breakdown"]:
		print("  - " + reason)
		
	print("__________________________________________________________________")
	
	print("Opponent AI selected " + str(bench_pokemon.size()) + " bench pokemon")
	for i in range(bench_pokemon.size()):
		print("  " + str(i + 1) + ". " + bench_pokemon[i].metadata.get("name", "Unknown") + " (Score: " + str(int(scored_pokemon[i + 1]["score"])) + ")")
		for reason in scored_pokemon[i+1]["breakdown"]:
			print("  - " + reason)
			
		print("__________________________________________________________________")
		
	return {
		"active": active_pokemon,
		"bench": bench_pokemon
	}

# PRIORITY CRITERION #1: Single energy attack check
# If pokemon can attack for only 1 energy: big boost (+100)
# If all attacks need 2+ energy: penalty (-50)
func criterion_1_single_energy_attack(basic_pokemon: card_object) -> Dictionary:
	var min_cost_attack = get_minimum_cost_attack(basic_pokemon)
	
	if min_cost_attack.is_empty():
		return {"score_change": 0, "reason": "No attacks found"}
	
	var min_cost = min_cost_attack.get("cost", 999)
	
	if min_cost == 1:
		return {
			"score_change": 100.0,
			"reason": "Can attack for only 1 energy. (+100 points)"
		}
	else:
		return {
			"score_change": -50.0,
			"reason": "Minimum attack cost is " + str(min_cost) + " energy. (-50 points)"
		}

# PRIORITY CRITERION #2: Check for evolution paths (Stage 1 and Stage 2)
# For Each Stage 1 evolution in hand that can evolve from the basic (+100)
# If there is a stage 1 that then also has a Stage 2 evolution then additional (+100)
func criterion_2_evolution_available(basic_pokemon: card_object, hand: Array) -> Dictionary:
	var score_change = 0.0
	var reason = "No evolutions in hand (+0)"
	var stage_1_list = []
	var has_stage_2_chain = false
	
	# Find all Stage 1 evolutions for this basic pokemon
	for card in hand:
		if card.metadata.has("subtypes") and card.metadata["subtypes"].has("Stage 1"):
			if can_evolve_from(card, basic_pokemon):
				stage_1_list.append(card)
				score_change += 100.0
	
	# Check if ANY of the Stage 1s has a Stage 2 evolution (only count once)
	if stage_1_list.size() > 0:
		for stage_1 in stage_1_list:
			if has_evolution(stage_1, hand, "Stage 2"):
				has_stage_2_chain = true
				break
		
		if has_stage_2_chain:
			score_change += 100.0
			reason = "Has " + str(stage_1_list.size()) + " Stage 1(s) with Stage 2 chain. (+"+str(score_change) +" points)"
		else:
			reason = "Has " + str(stage_1_list.size()) + " Stage 1 evolution(s) (+"+str(score_change) +" points)"
	
	return {
		"score_change": score_change,
		"reason": reason
	}
	
# PRIORITY CRITERION #3: Check if basic energy types in hand match pokemon type
# Pokemon type matches available basic energy: +30 per matching energy card
# Colorless pokemon: +15 per basic energy card in hand (flexible but lower priority)
# Pokemon type does NOT match available basic energy: -150
func criterion_3_energy_type_match(basic_pokemon: card_object, hand: Array) -> Dictionary:
	var pokemon_type = get_pokemon_type(basic_pokemon)
	
	# Count basic energy cards in hand
	var basic_energies_in_hand = []
	for card in hand:
		if is_basic_energy_card(card):
			basic_energies_in_hand.append(card)
	
	# If no basic energies at all, no match possible
	if basic_energies_in_hand.is_empty():
		return {
			"score_change": 0,
			"reason": "No basic energy cards in hand"
		}
	
	# Handle Colorless pokemon - gets +20 per basic energy available
	if pokemon_type == "Colorless":
		var score_bonus = 15.0 * basic_energies_in_hand.size()
		return {
			"score_change": score_bonus,
			"reason": "Colorless type - " + str(basic_energies_in_hand.size()) + " basic energies available (+"+str(score_bonus) +" points)"
		}
	
	# For typed pokemon, count matching energies
	var matching_energy_count = 0
	for energy_card in basic_energies_in_hand:
		var energy_type = get_energy_type_from_card(energy_card)
		if energy_type == pokemon_type:
			matching_energy_count += 1
	
	# If matching energies found
	if matching_energy_count > 0:
		var score_bonus = 30.0 * matching_energy_count
		return {
			"score_change": score_bonus,
			"reason": "Has " + str(matching_energy_count) + " " + pokemon_type + " energy card(s) (+"+str(score_bonus) +" points)"
		}
	
	# No matching energy found
	return {
		"score_change": -150.0,
		"reason": "No matching " + pokemon_type + " energy in hand (-150 points)"
	}	
	
# PRIORITY CRITERION #4: Higher HP is more durable and valuable
# Score = HP * 2
# e.g 50HP = +60
# e.g 100HP = +150
func criterion_4_pokemon_hp(basic_pokemon: card_object) -> Dictionary:
	var hp = get_pokemon_hp(basic_pokemon)
	var score_bonus = hp * 2
	
	return {
		"score_change": score_bonus,
		"reason": "HP: " + str(hp) + " (+" + str(int(score_bonus)) + " points)"
	}
	
# PRIORITY CRITERION #5: Damage output potential (either 1 bonus or 2 bonuses if more than 1 attack)
# 1-energy attack damage: damage * 3 (immediate threat). e.g 10 = +30, 20 = +60, 30 = +90
# Efficiency bonus (only if 2+ attacks): (highest_damage / energy_cost) * 3. e.g 4*Energy for 80 damage = +60
func criterion_5_attack_damage(basic_pokemon: card_object) -> Dictionary:
	if not basic_pokemon.metadata.has("attacks") or basic_pokemon.metadata["attacks"].size() == 0:
		return {
			"score_change": 0,
			"reason": "No attacks available"
		}
	
	var attack_count = basic_pokemon.metadata["attacks"].size()
	var score_bonus = 0.0
	var reason_parts = []
	
	# Check for 1-energy attack damage
	var min_cost_attack = get_minimum_cost_attack(basic_pokemon)
	if not min_cost_attack.is_empty() and min_cost_attack.get("cost") == 1:
		var one_energy_damage = min_cost_attack.get("damage", 0)
		var one_energy_bonus = one_energy_damage * 3
		score_bonus += one_energy_bonus
		reason_parts.append(str(one_energy_damage) + " damage at 1 energy (+" + str(one_energy_bonus) + " points)")
		
		# Check if the lowest cost attack has an effect (additional text)
		var attack_text = min_cost_attack.get("text", "")
		var attack_penalty = get_attack_text_penalty(attack_text, basic_pokemon.metadata.get("name", ""))
		
		if attack_penalty < 0:
			score_bonus += attack_penalty
			reason_parts.append("1-energy attack has penalty (" + str(attack_penalty) + " points)")
		elif attack_text != "":
			score_bonus += 20.0
			reason_parts.append("1-energy attack has beneficial effect (+20 points)")
	

	# Check if the lowest cost attack has an effect (additional text)	
	# Only add efficiency bonus if pokemon has 2+ attacks
	if attack_count >= 2:
		var max_attack = get_maximum_damage_attack(basic_pokemon)
		var max_damage = max_attack.get("damage", 0)
		var max_cost = max_attack.get("cost", 1)
		var attack_text = max_attack.get("text", "")
		
		# Check if highest damage attack has an effect
		var attack_penalty = get_attack_text_penalty(attack_text, basic_pokemon.metadata.get("name", ""))
		
		if attack_penalty < 0:
			score_bonus += attack_penalty
			reason_parts.append("Highest damage attack has penalty (" + str(attack_penalty) + " points)")
		elif attack_text != "":
			score_bonus += 20.0
			reason_parts.append("Highest damage attack has beneficial effect (+20 points)")
		
		# Only calculate efficiency if there's actual damage
		if max_damage > 0:
			var efficiency = float(max_damage) / float(max_cost)
			var efficiency_bonus = efficiency * 3.0
			score_bonus += efficiency_bonus
			reason_parts.append("highest damage efficiency " + str(max_damage) + "/" + str(max_cost) + " energy (+" + str(efficiency_bonus) + " points)")
	
	var reason = "Damage: " + ", ".join(reason_parts)
	
	return {
		"score_change": score_bonus,
		"reason": reason
	}	

# Helper function to check attack text for negative self-inflicted effects
# Only penalizes exact patterns where energy is discarded from the attacking pokemon
# Returns the penalty score (negative value) if found, 0 if no penalty
func get_attack_text_penalty(attack_text: String, pokemon_name: String) -> int:
	if attack_text == "":
		return 0
	
	var text = attack_text
	
	# Check for "discard all" attached to THIS pokemon (-70)
	if ("Discard all Energy cards attached to " + pokemon_name in text) or \
	   ("Discard all basic Energy cards attached to " + pokemon_name in text) or \
	   ("Discard all" in text and "Energy cards attached to " + pokemon_name in text):
		return -70
	
	# Check for "discard 3" attached to THIS pokemon (-50)
	if ("Discard 3 Energy cards attached to " + pokemon_name in text) or \
	   ("Discard 3 basic Energy cards attached to " + pokemon_name in text) or \
	   ("Discard 3" in text and "Energy cards attached to " + pokemon_name in text):
		return -50
	
	# Check for "discard 2" attached to THIS pokemon (-30)
	if ("Discard 2 Energy cards attached to " + pokemon_name in text) or \
	   ("Discard 2 basic Energy cards attached to " + pokemon_name in text) or \
	   ("Discard 2" in text and "Energy cards attached to " + pokemon_name in text):
		return -30
	
	# Check for "discard 1" or "discard a" attached to THIS pokemon (-10)
	if ("Discard 1" in text and "Energy card attached to " + pokemon_name in text) or \
	   ("Discard a" in text and "Energy card attached to " + pokemon_name in text) or \
	   ("Discard a basic Energy card attached to " + pokemon_name in text):
		return -10
	
	# Check for damage reduction effects (-20)
	if "damage minus" in text.to_lower():
		return -20
	
	# Check for self-damage effects (X damage to itself = -X*0.5)
	if pokemon_name in text and "damage to itself" in text.to_lower():
		var pattern = "does "
		var lower_text = text.to_lower()
		var start_index = lower_text.find(pattern)
		
		if start_index != -1:
			start_index += pattern.length()
			var number_str = ""
			for i in range(start_index, lower_text.length()):
				var numericalchar = lower_text[i]
				if numericalchar.is_valid_int():
					number_str += numericalchar
				elif number_str != "":
					break
			
			if number_str != "":
				var damage = int(number_str)
				var penalty = int(damage * 0.5)
				return -penalty
	
	return 0

# Criterion 2 is used simply just to check which cards have an evolution available at all. However,
# This scores each pairing (evolution_card, target_pokemon) for CPU evolution decisions, not just to check if there is one at all.
func evaluate_evolution_pair(evo_card: card_object, target: card_object) -> Dictionary:
	var score = 0.0
	var reasons = []

	# HP improvement: new max HP minus target's CURRENT HP (accounts for damage taken)
	var current_hp = target.current_hp
	var new_max_hp = int(evo_card.metadata.get("hp", "0"))
	var hp_gain = new_max_hp - current_hp
	score += hp_gain * 1.5
	reasons.append("HP gain: +" + str(hp_gain) + " (+" + str(hp_gain * 1.5) + " pts)")

	# Attack improvement: compare best damage output
	var old_best = get_maximum_damage_attack(target)
	var new_best = get_maximum_damage_attack(evo_card)
	var old_damage = old_best.get("damage", 0)
	var new_damage = new_best.get("damage", 0)
	var damage_gain = new_damage - old_damage
	score += damage_gain * 2.0
	reasons.append("Damage gain: +" + str(damage_gain) + " (+" + str(damage_gain * 2.0) + " pts)")

	# Energy compatibility: does target's attached energy satisfy any of the evolved form's attack costs
	var has_usable_attack_after = false
	for attack in evo_card.metadata.get("attacks", []):
		if check_attack_requirements(attack, target):
			has_usable_attack_after = true
			break
	if has_usable_attack_after:
		score += 150.0
		reasons.append("Can attack immediately after evolving (+150 pts)")

	# Active pokemon bonus: evolving the active is more urgent
	if target.current_location == "active":
		score += 75.0
		reasons.append("Target is active pokemon (+75 pts)")

	# Existing energy investment: more attached energy means more value preserved
	var energy_count = target.attached_energies.size()
	if energy_count > 0:
		score += energy_count * 25.0
		reasons.append("Target has " + str(energy_count) + " energy attached (+" + str(energy_count * 25.0) + " pts)")

	# Future evolution chain: check hand, deck, and prize cards
	var has_next_stage_in_hand = false
	var has_next_stage_in_deck_or_prizes = false
	for card in opponent_hand:
		if card != evo_card and can_evolve_from(card, evo_card):
			has_next_stage_in_hand = true
			break
	if not has_next_stage_in_hand:
		for card in opponent_deck + opponent_prize_cards:
			if can_evolve_from(card, evo_card):
				has_next_stage_in_deck_or_prizes = true
				break
	if has_next_stage_in_hand:
		score += 120.0
		reasons.append("Next evolution stage in hand (+120 pts)")
	elif has_next_stage_in_deck_or_prizes:
		score += 40.0
		reasons.append("Next evolution stage in deck or prizes (+40 pts)")

	return {
		"score": score,
		"evo_card": evo_card,
		"target": target,
		"reasons": reasons
	}
			
# Computes all Phase 1 helper evaluations and returns them as a dictionary
func build_cpu_evaluation() -> Dictionary:
	var eval = {}

	# Game state context (1.14, 1.15)
	eval["cpu_prizes_remaining"] = opponent_prize_cards.size()
	eval["player_prizes_remaining"] = player_prize_cards.size()
	eval["game_phase"] = "late" if (eval["cpu_prizes_remaining"] <= 2 or eval["player_prizes_remaining"] <= 2) else "early"

	# KO threat assessment (1.1, 1.2, 1.3)
	eval.merge(evaluate_ko_threats())

	# Per-pokemon data: energy requirements, evolution potential, attack readiness
	eval["pokemon_data"] = {}
	var all_cpu_pokemon = get_all_cpu_field_pokemon()
	for pokemon in all_cpu_pokemon:
		var key = pokemon.get_instance_id()
		eval["pokemon_data"][key] = evaluate_single_pokemon(pokemon)

	# CPU offensive capability (1.11, 1.13)
	eval["cpu_can_ko_player_active"] = can_cpu_ko_player_active()
	eval["has_viable_bench_attacker"] = check_viable_bench_attacker()

	return eval

# Returns an array of all CPU pokemon currently on the field (active + bench)
func get_all_cpu_field_pokemon() -> Array:
	var pokemon = []
	if opponent_active_pokemon != null:
		pokemon.append(opponent_active_pokemon)
	pokemon.append_array(opponent_bench)
	return pokemon

# Evaluates a single pokemon's energy requirements, attack readiness, and evolution potential
func evaluate_single_pokemon(pokemon: card_object) -> Dictionary:
	var data = {}

	# 1.4 and 1.5: Per-attack unmet energy and overall attack readiness
	var attack_data = []
	var can_attack = false
	for attack in pokemon.metadata.get("attacks", []):
		var unmet = get_unmet_energy_count(attack, pokemon)
		var damage_range = get_attack_damage_range(attack)
		attack_data.append({
			"name": attack.get("name", ""),
			"cost": attack.get("cost", []),
			"unmet": unmet,
			"damage_min": damage_range["min"],
			"damage_max": damage_range["max"],
			"text": attack.get("text", "")
		})
		if unmet == 0:
			can_attack = true
	data["attack_data"] = attack_data
	data["can_attack"] = can_attack

	# 1.7: Evolution in hand
	data["evolution_in_hand"] = null
	for card in opponent_hand:
		if can_evolve_from(card, pokemon):
			data["evolution_in_hand"] = card
			break

	# 1.8: Evolution in deck or prize cards
	data["evolution_in_deck_or_prizes"] = false
	if data["evolution_in_hand"] == null:
		for card in opponent_deck + opponent_prize_cards:
			if can_evolve_from(card, pokemon):
				data["evolution_in_deck_or_prizes"] = true
				break

	# 1.10: Can evolve further (check all sources)
	data["can_evolve_further"] = data["evolution_in_hand"] != null or data["evolution_in_deck_or_prizes"]

	# 1.9: If evolution exists, does the evolved form need more energy than currently attached
	data["evolved_form_needs_energy"] = false
	var evo_card = data["evolution_in_hand"]
	if evo_card == null:
		# Check deck/prizes for the actual card data to inspect attacks
		for card in opponent_deck + opponent_prize_cards:
			if can_evolve_from(card, pokemon):
				evo_card = card
				break
	if evo_card != null:
		for attack in evo_card.metadata.get("attacks", []):
			if get_unmet_energy_count(attack, pokemon) > 0:
				data["evolved_form_needs_energy"] = true
				break

	return data

# Parses an attack's damage string and returns min/max estimate (placeholder until full effect parsing)
func get_attack_damage_range(attack: Dictionary, attacker: card_object = null, defender: card_object = null) -> Dictionary:
	var base_damage = parse_attack_base_damage(attack)
	var damage_str = str(attack.get("damage", "0"))
	var text = attack.get("text", "").to_lower()
	var attacker_name = attacker.metadata.get("name", "").to_lower() if attacker else ""
	
	# --- COIN FLIP MULTIPLICATIVE (×) ---
	if "×" in damage_str or "x" in damage_str:
		if "flip a coin until" in text:
			return {"min": 0, "max": base_damage * 5}
		elif "flip 3 coins" in text:
			return {"min": 0, "max": base_damage * 3}
		elif "flip 2 coins" in text:
			return {"min": 0, "max": base_damage * 2}
		return {"min": 0, "max": base_damage * 2}
	
	# --- "IF TAILS, DOES NOTHING" ---
	if "if tails, this attack does nothing" in text:
		return {"min": 0, "max": base_damage}
	
	# --- HALF HP (Raticate Super Fang) ---
	if "equal to half" in text and "remaining hp" in text:
		if defender:
			var dmg = int(ceil(defender.current_hp / 2.0 / 10.0)) * 10
			return {"min": dmg, "max": dmg}
		return {"min": 10, "max": 60}
	
	# --- CONDITION-GATED (Haunter Dream Eater) ---
	if "can't use this attack unless" in text:
		if defender:
			if "asleep" in text and defender.special_condition != "Asleep":
				return {"min": 0, "max": 0}
			if "poisoned" in text and not defender.is_poisoned:
				return {"min": 0, "max": 0}
		return {"min": 0, "max": base_damage}
	
	var min_dmg = base_damage
	var max_dmg = base_damage
	
	# --- HEADS/TAILS +BONUS ---
	if "+" in damage_str and "if heads" in text and "more damage" in text:
		var bonus = extract_number_before(text, "more damage")
		if bonus <= 0:
			bonus = 10
		min_dmg = base_damage
		max_dmg = base_damage + bonus
	
	# --- PER DEFENDER ENERGY ---
	if "for each energy card attached to the defending" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each energy")
		if extracted > 0:
			per = extracted
		if defender:
			var count = defender.attached_energies.size()
			min_dmg += per * count
			max_dmg += per * count
		else:
			max_dmg += per * 4
	
	# --- EXTRA ENERGY BEYOND COST ---
	if "more damage for each" in text and "not used to pay" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each")
		if extracted > 0:
			per = extracted
		if attacker:
			var type_keywords = ["water", "fire", "grass", "lightning", "psychic", "fighting"]
			var bonus_type = ""
			for tkw in type_keywords:
				if tkw + " energy attached" in text:
					bonus_type = tkw.capitalize()
					break
			if bonus_type != "":
				var total = 0
				for e in attacker.attached_energies:
					if bonus_type in get_energy_provided_by_card(e):
						total += 1
				var cost_count = 0
				for c in attack.get("cost", []):
					if c == bonus_type:
						cost_count += 1
				var extra = max(0, total - cost_count)
				var cap = 99
				if "after the" in text and "don't count" in text:
					var after_pos = text.find("after the")
					var after_text = text.substr(after_pos + 10, 10)
					var cap_num = ""
					for ch in after_text:
						if ch.is_valid_int():
							cap_num += ch
						else:
							break
					if cap_num != "":
						cap = max(0, int(cap_num) - cost_count)
				extra = min(extra, cap)
				min_dmg += per * extra
				max_dmg += per * extra
		else:
			max_dmg += per * 2
	
	# --- PER DAMAGE COUNTER ON DEFENDING ---
	if "for each damage counter on the defending" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per = extracted
		if defender:
			var counters = defender.get_damage_counters()
			min_dmg += per * counters
			max_dmg += per * counters
		else:
			max_dmg += per * 8
	
	# --- PER SELF DAMAGE COUNTER ---
	if attacker_name != "" and ("for each damage counter on " + attacker_name) in text and "minus" not in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each damage counter")
		if extracted > 0:
			per = extracted
		if attacker:
			var counters = attacker.get_damage_counters()
			min_dmg += per * counters
			max_dmg += per * counters
	
	# --- MINUS PER SELF DAMAGE COUNTER ---
	if "-" in damage_str and ("minus" in text or "damage minus" in text) and "damage counter" in text:
		var per = 10
		var extracted = extract_number_before(text, "damage for each damage counter")
		if extracted > 0:
			per = extracted
		if attacker:
			var counters = attacker.get_damage_counters()
			min_dmg = max(0, base_damage - per * counters)
			max_dmg = min_dmg
		else:
			min_dmg = 0
	
	# --- PER BENCH COUNT ---
	if "for each of your benched" in text:
		var per = 10
		var extracted = extract_number_before(text, "more damage for each")
		if extracted > 0:
			per = extracted
		if attacker:
			var bench = opponent_bench if attacker == opponent_active_pokemon else player_bench
			min_dmg += per * bench.size()
			max_dmg += per * bench.size()
		else:
			max_dmg += per * 5
	
	return {"min": min_dmg, "max": max_dmg}

# Evaluates KO threats from the player against the CPU's active pokemon (1.1, 1.2, 1.3)
func evaluate_ko_threats() -> Dictionary:
	var result = {
		"cpu_active_guaranteed_ko": false,
		"cpu_active_potential_ko": false,
		"player_bench_ko_threat": false
	}

	if opponent_active_pokemon == null or player_active_pokemon == null:
		return result

	var cpu_active_hp = opponent_active_pokemon.current_hp
	var player_types = player_active_pokemon.metadata.get("types", ["Colorless"])

	# 1.1 and 1.2: Check each attack on the player's active pokemon
	for attack in player_active_pokemon.metadata.get("attacks", []):
		var unmet = get_unmet_energy_count(attack, player_active_pokemon)
		# Skip if player can't use this attack even with one more energy
		if unmet > 1:
			continue
		var damage_range = get_attack_damage_range(attack, player_active_pokemon, opponent_active_pokemon)
		var min_result = calculate_final_damage(damage_range["min"], player_types, opponent_active_pokemon)
		var max_result = calculate_final_damage(damage_range["max"], player_types, opponent_active_pokemon)

		if unmet == 0:
			# Attack is usable right now
			if min_result["damage"] >= cpu_active_hp:
				result["cpu_active_guaranteed_ko"] = true
			elif max_result["damage"] >= cpu_active_hp:
				result["cpu_active_potential_ko"] = true
		else:
			# Attack is 1 energy away — treat as potential since player will likely attach
			if min_result["damage"] >= cpu_active_hp:
				result["cpu_active_potential_ko"] = true

	# 1.3: Check if player could retreat into a bench KO threat
	var retreat_cost = get_retreat_cost(player_active_pokemon)
	var current_energy = player_active_pokemon.attached_energies.size()
	# Player can retreat now, or is 1 energy away from retreating
	var player_can_retreat = current_energy >= retreat_cost or current_energy >= (retreat_cost - 1)

	if player_can_retreat:
		for bench_pokemon in player_bench:
			var bench_types = bench_pokemon.metadata.get("types", ["Colorless"])
			for attack in bench_pokemon.metadata.get("attacks", []):
				var unmet = get_unmet_energy_count(attack, bench_pokemon)
				# Bench pokemon needs to be ready now — player can only attach 1 energy total
				# If they spend it on retreat cost they can't also power up the bench attacker
				if unmet > 0:
					continue
				var damage_range = get_attack_damage_range(attack, bench_pokemon, opponent_active_pokemon)
				var min_result = calculate_final_damage(damage_range["min"], bench_types, opponent_active_pokemon)
				if min_result["damage"] >= cpu_active_hp:
					result["player_bench_ko_threat"] = true
					break
			if result["player_bench_ko_threat"]:
				break

	return result

# Returns how many energy cards a pokemon still needs to use a specific attack
func get_unmet_energy_count(attack: Dictionary, pokemon: card_object) -> int:
	var required_cost = attack.get("cost", [])
	if required_cost.size() == 0:
		return 0

	var pool = []
	for attached in pokemon.attached_energies:
		# Charizard Energy Burn: all energy attached to Charizard counts as Fire
		if is_energy_burn_active(pokemon):
			pool.append("Fire")
			# If the energy provides 2 (like DCE), add a second Fire
			var provided = get_energy_provided_by_card(attached)
			if provided.size() > 1:
				for _i in range(provided.size() - 1):
					pool.append("Fire")
		else:
			pool.append_array(get_energy_provided_by_card(attached))

	var unmet = 0

	# Pass 1: typed requirements first
	for requirement in required_cost:
		if requirement == "Colorless":
			continue
		var exact_index = pool.find(requirement)
		if exact_index != -1:
			pool.remove_at(exact_index)
		else:
			var any_index = pool.find("Any")
			if any_index != -1:
				pool.remove_at(any_index)
			else:
				unmet += 1

	# Pass 2: colorless requirements consume whatever remains
	for requirement in required_cost:
		if requirement != "Colorless":
			continue
		if pool.size() > 0:
			pool.remove_at(0)
		else:
			unmet += 1

	return unmet

# Checks if the CPU's active can KO the player's active with currently usable attacks (1.11)
func can_cpu_ko_player_active() -> bool:
	if opponent_active_pokemon == null or player_active_pokemon == null:
		return false

	var cpu_types = opponent_active_pokemon.metadata.get("types", ["Colorless"])
	var player_hp = player_active_pokemon.current_hp

	for attack in opponent_active_pokemon.metadata.get("attacks", []):
		if get_unmet_energy_count(attack, opponent_active_pokemon) > 0:
			continue
		var damage_range = get_attack_damage_range(attack)
		var result = calculate_final_damage(damage_range["min"], cpu_types, player_active_pokemon)
		if result["damage"] >= player_hp:
			return true

	return false

# Checks if any bench pokemon is ready or near-ready to attack and can survive a hit (1.13)
func check_viable_bench_attacker() -> bool:
	if player_active_pokemon == null or opponent_active_pokemon == null:
		return false

	var player_types = player_active_pokemon.metadata.get("types", ["Colorless"])

	# Find the player's strongest currently usable attack damage
	var player_max_damage = 0
	for attack in player_active_pokemon.metadata.get("attacks", []):
		if get_unmet_energy_count(attack, player_active_pokemon) > 0:
			continue
		var damage_range = get_attack_damage_range(attack)
		var result = calculate_final_damage(damage_range["max"], player_types, opponent_active_pokemon)
		player_max_damage = max(player_max_damage, result["damage"])

	for bench_pokemon in opponent_bench:
		var is_ready = false
		for attack in bench_pokemon.metadata.get("attacks", []):
			var unmet = get_unmet_energy_count(attack, bench_pokemon)
			if unmet > 1:
				continue
			# Ready now, or 1 energy away with a matching energy in hand
			if unmet == 0:
				is_ready = true
				break
			for card in opponent_hand:
				if card.metadata.get("supertype", "").to_lower() != "energy":
					continue
				var energy_types = get_energy_provided_by_card(card)
				var cost = attack.get("cost", [])
				for req in cost:
					if req in energy_types or req == "Colorless":
						is_ready = true
						break
				if is_ready:
					break
			if is_ready:
				break

		if not is_ready:
			continue

		# Check if this bench pokemon would survive the player's strongest attack
		var bench_types = bench_pokemon.metadata.get("types", ["Colorless"])
		var damage_to_bench = calculate_final_damage(player_max_damage, player_types, bench_pokemon)
		if bench_pokemon.current_hp > damage_to_bench["damage"]:
			return true

	return false

# R.2, R.4: Evaluates whether the energy cost of retreating is worth paying
func is_retreat_cost_worthwhile(cpu_eval: Dictionary) -> bool:
	var active = opponent_active_pokemon
	var retreat_cost = get_retreat_cost(active)
	var active_key = active.get_instance_id()
	var active_data = cpu_eval["pokemon_data"].get(active_key, {})

	# Free retreat is always worthwhile
	if retreat_cost == 0:
		return true

	# Check what state the active ends up in after losing retreat cost energy
	var energy_after_retreat = active.attached_energies.size() - retreat_cost
	var can_attack_after = false
	for attack in active.metadata.get("attacks", []):
		# Simulate the energy pool after discarding retreat cost
		var simulated_pool = []
		for i in range(energy_after_retreat):
			simulated_pool.append_array(get_energy_provided_by_card(active.attached_energies[i]))
		var required = attack.get("cost", [])
		if simulated_pool.size() >= required.size():
			can_attack_after = true
			break

	# R.2 rule of thumb: if retreat strips more than half the energy needed for primary attack
	var max_attack = get_maximum_damage_attack(active)
	var primary_attack_cost = max_attack.get("cost", 1)
	var energy_lost_ratio = float(retreat_cost) / float(max(primary_attack_cost, 1))

	# R.4: High-investment pokemon preservation overrides the ratio check
	var guaranteed_ko = cpu_eval.get("cpu_active_guaranteed_ko", false)
	var has_evo = active_data.get("can_evolve_further", false)
	var high_investment = active.attached_energies.size() >= 3 or has_evo
	var high_hp = active.current_hp > int(active.metadata.get("hp", "0")) * 0.5

	if guaranteed_ko and high_investment and high_hp:
		print("CPU retreat worthwhile: preserving high-investment pokemon")
		return true

	# Losing more than half the energy for primary attack is generally bad
	if energy_lost_ratio > 0.5 and not can_attack_after:
		print("CPU retreat not worthwhile: would lose " + str(retreat_cost) + " energy and cannot attack from bench")
		return false

	# If active can still contribute from the bench after retreating, it's worthwhile
	if can_attack_after:
		print("CPU retreat worthwhile: active retains enough energy to attack from bench")
		return true

	# Default: retreat is worthwhile if there's a real threat
	if guaranteed_ko:
		return true

	return false

# Evaluates whether active should retreat before energy attachment (R.1-R.4)
func cpu_phase_retreat_first_pass(cpu_eval: Dictionary) -> bool:
	if opponent_active_pokemon == null or opponent_bench.size() == 0:
		return false
	if opponent_retreated_this_turn:
		return false
	if opponent_active_pokemon.special_condition in ["Paralyzed", "Asleep"]:
		print("CPU cannot retreat: active is ", opponent_active_pokemon.special_condition)
		return false

	# R.1: Should the active pokemon retreat?
	var should_consider = evaluate_retreat_reasons(cpu_eval)
	if not should_consider:
		return false

	var retreat_cost = get_retreat_cost(opponent_active_pokemon)
	var current_energy = opponent_active_pokemon.attached_energies.size()

	# R.3: Exactly 1 energy short — defer to after energy attachment
	if current_energy == retreat_cost - 1 and not opponent_energy_played_this_turn:
		print("CPU retreat deferred: 1 energy short, will re-evaluate after attachment")
		return true

	# R.2: Can the active actually pay retreat cost right now?
	if current_energy < retreat_cost:
		print("CPU cannot retreat: not enough energy (" + str(current_energy) + "/" + str(retreat_cost) + ")")
		return false

	# R.2 continued: Is paying the retreat cost worth the energy loss?
	if not is_retreat_cost_worthwhile(cpu_eval):
		print("CPU retreat not worthwhile: energy loss too high")
		return false

	# R.5: Pick the best replacement and execute
	await execute_cpu_retreat(cpu_eval)
	return false

# Re-evaluates retreat after energy attachment if first pass deferred (R.3)
func cpu_phase_retreat_second_pass(cpu_eval: Dictionary) -> void:
	if opponent_active_pokemon == null or opponent_bench.size() == 0:
		return
	if opponent_retreated_this_turn:
		return
	if opponent_active_pokemon.special_condition in ["Paralyzed", "Asleep"]:
		print("CPU retreat second pass: active is ", opponent_active_pokemon.special_condition)
		return

	var retreat_cost = get_retreat_cost(opponent_active_pokemon)
	var current_energy = opponent_active_pokemon.attached_energies.size()

	# Verify retreat is now mechanically possible after energy attachment
	if current_energy < retreat_cost:
		print("CPU retreat second pass: still cannot pay retreat cost")
		return

	# Re-check if retreat reasons still apply with updated board state
	if not evaluate_retreat_reasons(cpu_eval):
		print("CPU retreat second pass: reasons no longer apply")
		return

	# Re-check if the cost is worthwhile
	if not is_retreat_cost_worthwhile(cpu_eval):
		print("CPU retreat second pass: cost not worthwhile")
		return

	await execute_cpu_retreat(cpu_eval)
	
# Scores each bench pokemon as a potential active replacement, returns the best choice
func pick_best_bench_replacement(bench: Array, against_pokemon: card_object, cpu_eval: Dictionary) -> card_object:
	var best_replacement: card_object = null
	var best_score: float = -999.0

	for bench_pokemon in bench:
		var score = score_bench_as_replacement(bench_pokemon, against_pokemon, cpu_eval)
		if score > best_score:
			best_score = score
			best_replacement = bench_pokemon

	return best_replacement

# Scores a single bench pokemon as a potential active replacement considering attacks, survivability, and type matchups
func score_bench_as_replacement(bench_pokemon: card_object, against_pokemon: card_object, cpu_eval: Dictionary) -> float:
	var score = 0.0
	var bench_key = bench_pokemon.get_instance_id()
	var bench_data = cpu_eval["pokemon_data"].get(bench_key, {})
	if bench_data.is_empty():
		bench_data = evaluate_single_pokemon(bench_pokemon)

	var bench_types = bench_pokemon.metadata.get("types", ["Colorless"])

	# Can already attack: strong preference
	if bench_data.get("can_attack", false):
		score += 200.0

	# Among attackers, prefer one that can KO the opposing active
	if bench_data.get("can_attack", false) and against_pokemon != null:
		for attack in bench_data.get("attack_data", []):
			if attack["unmet"] > 0:
				continue
			var result = calculate_final_damage(attack["damage_min"], bench_types, against_pokemon)
			if result["damage"] >= against_pokemon.current_hp:
				score += 150.0
				break

	# Closest to attacking if can't attack yet
	if not bench_data.get("can_attack", false):
		var lowest_unmet = 999
		for attack in bench_data.get("attack_data", []):
			if attack["unmet"] < lowest_unmet:
				lowest_unmet = attack["unmet"]
		if lowest_unmet < 999:
			score += max(0.0, 80.0 - (lowest_unmet * 25.0))

	# Survivability: can this pokemon take a hit from the opposing active
	if against_pokemon != null:
		var enemy_types = against_pokemon.metadata.get("types", ["Colorless"])
		var enemy_max_damage = 0
		for attack in against_pokemon.metadata.get("attacks", []):
			if get_unmet_energy_count(attack, against_pokemon) > 0:
				continue
			var damage_range = get_attack_damage_range(attack)
			var result = calculate_final_damage(damage_range["max"], enemy_types, bench_pokemon)
			enemy_max_damage = max(enemy_max_damage, result["damage"])
		if bench_pokemon.current_hp > enemy_max_damage:
			score += 100.0

	# Type advantage: our attacks hit the opponent's weakness
	if against_pokemon != null:
		for weakness in against_pokemon.metadata.get("weaknesses", []):
			if weakness["type"] in bench_types:
				score += 75.0
				break

	# Type disadvantage: opponent's attacks hit our weakness
	if against_pokemon != null:
		var enemy_types = against_pokemon.metadata.get("types", ["Colorless"])
		for weakness in bench_pokemon.metadata.get("weaknesses", []):
			if weakness["type"] in enemy_types:
				score -= 60.0
				break

	# Resistance bonus: we resist the opponent's type
	if against_pokemon != null:
		var enemy_types = against_pokemon.metadata.get("types", ["Colorless"])
		for resistance in bench_pokemon.metadata.get("resistances", []):
			if resistance["type"] in enemy_types:
				score += 50.0
				break

	# HP tiebreaker
	score += bench_pokemon.current_hp * 0.1

	return score

# Scores a single (pokemon, energy_card) pair using all Phase 2 rules
func score_energy_pair(pokemon: card_object, energy_card: card_object, cpu_eval: Dictionary, pokemon_data: Dictionary) -> float:
	var score = 0.0
	var is_active = (pokemon == opponent_active_pokemon)
	var energy_types = get_energy_provided_by_card(energy_card)
	
	# DCE restriction: only attach to pokemon with an attack requiring 2+ Colorless
	if is_double_colorless_energy(energy_card):
		var has_2_colorless_attack = false
		for attack in pokemon.metadata.get("attacks", []):
			var colorless_count = 0
			for req in attack.get("cost", []):
				if req == "Colorless":
					colorless_count += 1
			if colorless_count >= 2:
				has_2_colorless_attack = true
				break
		if not has_2_colorless_attack:
			return -500.0  # Hard disqualification: this pokemon can't effectively use DCE
	
	# Flat active/bench modifier: active pokemon almost always takes priority
	if is_active:
		score += 40.0
	else:
		score -= 20.0
	
	# 2.1, 2.2, 2.3: Energy type matching (can disqualify a pair)
	score += score_energy_type_match(pokemon, energy_types, pokemon_data, is_active)

	# 2.4, 2.5: Active pokemon needs energy
	if is_active:
		score += score_active_needs_energy(pokemon, energy_types, pokemon_data)

	# 2.6: Active pokemon already fully powered
	if is_active:
		score += score_active_overpowered(pokemon_data, cpu_eval)

	# 2.7, 2.8, 2.9: Active pokemon under KO threat
	if is_active:
		score += score_active_ko_threat(pokemon, energy_types, pokemon_data, cpu_eval)

	# 2.10, 2.11: Evolution potential
	score += score_evolution_potential(pokemon, pokemon_data, cpu_eval, is_active)

	# 2.12, 2.13, 2.14: Bench pokemon scoring
	if not is_active:
		score += score_bench_candidate(pokemon, pokemon_data, cpu_eval)

	# 2.15: Attack self-discard consideration
	score += score_self_discard_penalty(pokemon)

	# EXTRA ENERGY BEYOND COST: Score bonus for attacks like Poliwag/Blastoise that do more damage with extra energy
	if is_active:
		for attack in pokemon.metadata.get("attacks", []):
			var atk_text = attack.get("text", "").to_lower()
			if "more damage for each" in atk_text and "not used to pay" in atk_text:
				# Check if we haven't hit the cap yet
				var cost = attack.get("cost", [])
				var bonus_type = ""
				var type_keywords = ["water", "fire", "grass", "lightning", "psychic", "fighting"]
				for tkw in type_keywords:
					if tkw + " energy attached" in atk_text:
						bonus_type = tkw.capitalize()
						break
				if bonus_type != "":
					var current_of_type = 0
					for e in pokemon.attached_energies:
						if bonus_type in get_energy_provided_by_card(e):
							current_of_type += 1
					var needed_for_cost = 0
					for c in cost:
						if c == bonus_type:
							needed_for_cost += 1
					var extra = max(0, current_of_type - needed_for_cost)
					# Parse cap
					var cap = 99
					if "after the" in atk_text and "don't count" in atk_text:
						var after_pos = atk_text.find("after the")
						var after_text = atk_text.substr(after_pos + 10, 10)
						var cap_num = ""
						for ch in after_text:
							if ch.is_valid_int():
								cap_num += ch
							else:
								break
						if cap_num != "":
							cap = max(0, int(cap_num) - needed_for_cost)
					
					if extra < cap:
						# We can benefit from more energy of this type
						var provides_bonus_type = false
						for provided in energy_types:
							if provided == bonus_type:
								provides_bonus_type = true
								break
						if provides_bonus_type:
							# Check if CPU won't be KO'd next turn (no point in over-investing)
							var ko_threats = evaluate_ko_threats()
							if not ko_threats["cpu_active_guaranteed_ko"]:
								score += 60.0
								print("ENERGY SCORE: +60 for extra energy bonus attack on ", pokemon.metadata["name"])

	return score
	
# 2.1, 2.2, 2.3: Checks if energy type is useful for this pokemon
func score_energy_type_match(pokemon: card_object, energy_types: Array, pokemon_data: Dictionary, is_active: bool) -> float:
	var score = 0.0
	var attack_data = pokemon_data.get("attack_data", [])

	# Gather all specific (non-colorless) energy types needed across all attacks
	var needed_types = []
	for attack in attack_data:
		for req in attack.get("cost", []):
			if req != "Colorless" and req not in needed_types:
				needed_types.append(req)

	# Check if this energy provides a type that matches any attack cost
	var has_type_match = false
	for provided in energy_types:
		if provided in needed_types or provided == "Any":
			has_type_match = true
			break

	# Direct type match — this energy is exactly what the pokemon wants
	if has_type_match:
		score += 80.0 if is_active else 60.0
		return score

	# Check if this pokemon has any attacks with unmet colorless slots
	var has_unmet_colorless_slots = false
	for attack in attack_data:
		if attack["unmet"] <= 0:
			continue
		# Count how many colorless slots exist in this attack's cost
		var colorless_in_cost = attack["cost"].count("Colorless")
		if colorless_in_cost > 0:
			has_unmet_colorless_slots = true
			break

	# Any energy can fill colorless slots — moderate positive match
	if has_unmet_colorless_slots:
		score += 50.0 if is_active else 35.0
		return score

	# 2.2: Does attaching this energy fill a colorless slot and unlock an attack?
	var unlocks_via_colorless = false
	for attack in attack_data:
		if attack["unmet"] <= 0:
			continue
		var colorless_in_cost = attack["cost"].count("Colorless")
		if colorless_in_cost == 0:
			continue
		if attack["unmet"] == 1:
			var typed_unmet = attack["unmet"] - colorless_in_cost
			if typed_unmet <= 0:
				unlocks_via_colorless = true
				break

	if unlocks_via_colorless:
		score += 40.0 if is_active else 30.0
		return score

	# 2.3: Check if ANY pokemon in play needs this energy type specifically
	var any_pokemon_needs_type = false
	for field_pokemon in get_all_cpu_field_pokemon():
		if field_pokemon == pokemon:
			continue
		for attack in field_pokemon.metadata.get("attacks", []):
			for req in attack.get("cost", []):
				if req != "Colorless":
					for provided in energy_types:
						if provided == req or provided == "Any":
							any_pokemon_needs_type = true

	if any_pokemon_needs_type:
		score -= 200.0
		return score

	# Nobody needs this type — colorless fallback scoring
	var total_unmet_colorless = 0
	for attack in attack_data:
		if attack["unmet"] > 0:
			total_unmet_colorless += attack["cost"].count("Colorless")

	if total_unmet_colorless > 0:
		score += total_unmet_colorless * 5.0
		if is_active:
			score += 10.0
		return score

	score -= 200.0
	return score
	
# 2.4, 2.5: Active pokemon has unmet energy requirements
func score_active_needs_energy(pokemon: card_object, energy_types: Array, pokemon_data: Dictionary) -> float:
	var score = 0.0
	var attack_data = pokemon_data.get("attack_data", [])

	# 2.4: Active has at least one attack with unmet energy
	var has_unmet = false
	var lowest_unmet = 999
	for attack in attack_data:
		if attack["unmet"] > 0:
			has_unmet = true
			if attack["unmet"] < lowest_unmet:
				lowest_unmet = attack["unmet"]

	if has_unmet:
		score += 80.0
		# Progress bonus: the closer to unlocking, the more valuable each energy is
		if lowest_unmet <= 3:
			score += max(0.0, 80.0 - (lowest_unmet * 20.0))

	# 2.5: Would this specific energy unlock a currently unusable attack?
	for attack in attack_data:
		if attack["unmet"] != 1:
			continue
		var remaining_type = get_remaining_requirement(attack, pokemon)
		if remaining_type == null:
			continue
		if remaining_type == "Colorless":
			score += 100.0
			break
		for provided in energy_types:
			if provided == remaining_type or provided == "Any":
				score += 100.0
				break

	return score
	
# Returns the energy type of the single remaining unmet requirement, or null if not exactly 1 unmet
func get_remaining_requirement(attack_info: Dictionary, pokemon: card_object) -> String:
	if attack_info["unmet"] != 1:
		return ""
	var cost = attack_info["cost"].duplicate()

	# Build the available energy pool from attached energies
	var pool = []
	for attached in pokemon.attached_energies:
		pool.append_array(get_energy_provided_by_card(attached))

	# Remove typed requirements that are already satisfied
	for req in cost:
		if req == "Colorless":
			continue
		var idx = pool.find(req)
		if idx != -1:
			pool.remove_at(idx)
			cost[cost.find(req)] = "_SATISFIED_"
		else:
			var any_idx = pool.find("Any")
			if any_idx != -1:
				pool.remove_at(any_idx)
				cost[cost.find(req)] = "_SATISFIED_"
			else:
				return req

	# All typed requirements met — remaining must be colorless
	for req in cost:
		if req == "Colorless":
			if pool.size() > 0:
				pool.remove_at(0)
			else:
				return "Colorless"

	return ""

# 2.6: Penalises over-investment when active is already fully powered
func score_active_overpowered(pokemon_data: Dictionary, cpu_eval: Dictionary) -> float:
	var attack_data = pokemon_data.get("attack_data", [])

	# Check if all attacks already have energy requirements met
	var all_attacks_met = true
	for attack in attack_data:
		if attack["unmet"] > 0:
			all_attacks_met = false
			break

	if not all_attacks_met:
		return 0.0

	# Exception: if this pokemon can evolve and the evolved form needs more energy
	if pokemon_data.get("can_evolve_further", false) and pokemon_data.get("evolved_form_needs_energy", false):
		return 0.0

	return -100.0

# 2.7, 2.8, 2.9: Adjusts score when active is threatened with KO
func score_active_ko_threat(pokemon: card_object, energy_types: Array, pokemon_data: Dictionary, cpu_eval: Dictionary) -> float:
	var score = 0.0
	var can_attack = pokemon_data.get("can_attack", false)
	var guaranteed_ko = cpu_eval.get("cpu_active_guaranteed_ko", false)
	var potential_ko = cpu_eval.get("cpu_active_potential_ko", false)
	var bench_ko_threat = cpu_eval.get("player_bench_ko_threat", false)

	if not guaranteed_ko and not potential_ko and not bench_ko_threat:
		return 0.0

	# 2.8: Check if attaching this energy would enable a KO on the player's active
	var enables_ko = false
	if player_active_pokemon != null:
		var cpu_types = pokemon.metadata.get("types", ["Colorless"])
		var player_hp = player_active_pokemon.current_hp
		var attack_data = pokemon_data.get("attack_data", [])

		for attack in attack_data:
			if attack["unmet"] != 1:
				continue
			var remaining = get_remaining_requirement(attack, pokemon)
			if remaining == "":
				continue
			var type_matches = remaining == "Colorless"
			if not type_matches:
				for provided in energy_types:
					if provided == remaining or provided == "Any":
						type_matches = true
						break
			if not type_matches:
				continue
			var result = calculate_final_damage(attack["damage_min"], cpu_types, player_active_pokemon)
			if result["damage"] >= player_hp:
				enables_ko = true
				break

	if enables_ko:
		# Striking first is extremely valuable — override KO threat penalties
		if cpu_eval.get("cpu_prizes_remaining", 6) == 1:
			return 500.0
		return 250.0

	# 2.7a: Guaranteed KO and active can already attack — don't invest further
	if guaranteed_ko and can_attack:
		# 2.9: Partial override — extra damage before going down if bench backup exists
		if cpu_eval.get("has_viable_bench_attacker", false):
			var unlocks_stronger = false
			for attack in pokemon_data.get("attack_data", []):
				if attack["unmet"] == 1:
					unlocks_stronger = true
					break
			if unlocks_stronger:
				return -80.0
		return -150.0

	# 2.7c: Guaranteed KO and cannot attack yet
	if guaranteed_ko and not can_attack:
		var would_enable_attack = false
		for attack in pokemon_data.get("attack_data", []):
			if attack["unmet"] == 1:
				would_enable_attack = true
				break
		
		if not would_enable_attack:
			return -200.0
		else:
			return -100.0
			
	return 0.0

# 2.10, 2.11: Scores evolution potential for energy investment
func score_evolution_potential(pokemon: card_object, pokemon_data: Dictionary, cpu_eval: Dictionary, is_active: bool) -> float:
	var score = 0.0
	var has_evo_in_hand = pokemon_data.get("evolution_in_hand", null) != null
	var has_evo_in_deck = pokemon_data.get("evolution_in_deck_or_prizes", false)
	var needs_energy = pokemon_data.get("evolved_form_needs_energy", false)

	# 2.10a: Evolution in hand and evolved form needs more energy
	if has_evo_in_hand and needs_energy:
		score += 100.0

	# 2.10b: Evolution in deck/prizes only — less certain
	elif has_evo_in_deck and needs_energy:
		score += 50.0

	# 2.11: Active already doing its job — redirect to evolving bench pokemon
	if is_active and cpu_eval.get("cpu_can_ko_player_active", false):
		var dominated_by_bench_evo = false
		for bench_pokemon in opponent_bench:
			var bench_key = bench_pokemon.get_instance_id()
			var bench_data = cpu_eval["pokemon_data"].get(bench_key, {})
			var bench_has_evo = bench_data.get("evolution_in_hand", null) != null or bench_data.get("evolution_in_deck_or_prizes", false)
			var bench_needs_energy = bench_data.get("evolved_form_needs_energy", false)
			if bench_has_evo and bench_needs_energy:
				dominated_by_bench_evo = true
				break

		if dominated_by_bench_evo:
			score -= 70.0

	return score

# 2.12, 2.13, 2.14: Scores bench pokemon as energy targets
func score_bench_candidate(pokemon: card_object, pokemon_data: Dictionary, cpu_eval: Dictionary) -> float:
	var score = 0.0
	var attack_data = pokemon_data.get("attack_data", [])

	# 2.12: Base score for bench pokemon with unmet energy
	var has_unmet = false
	for attack in attack_data:
		if attack["unmet"] > 0:
			has_unmet = true
			break

	if has_unmet:
		score += 50.0

	# 2.13: Boost bench when active is doomed and can already attack
	var active_doomed = cpu_eval.get("cpu_active_guaranteed_ko", false)
	var active_key = opponent_active_pokemon.get_instance_id() if opponent_active_pokemon != null else -1
	var active_data = cpu_eval["pokemon_data"].get(active_key, {})
	var active_can_attack = active_data.get("can_attack", false)

	if active_doomed and active_can_attack:
		score += 100.0

		# Prefer bench pokemon that can survive the player's strongest usable attack
		if player_active_pokemon != null:
			var player_types = player_active_pokemon.metadata.get("types", ["Colorless"])
			var player_max_damage = 0
			for attack in player_active_pokemon.metadata.get("attacks", []):
				if get_unmet_energy_count(attack, player_active_pokemon) > 0:
					continue
				var damage_range = get_attack_damage_range(attack)
				var result = calculate_final_damage(damage_range["max"], player_types, pokemon)
				player_max_damage = max(player_max_damage, result["damage"])

			if pokemon.current_hp > player_max_damage:
				score += 40.0

	# 2.14: Proximity bonus — fewer unmet energy means closer to attacking
	var lowest_unmet = 999
	for attack in attack_data:
		if attack["unmet"] > 0 and attack["unmet"] < lowest_unmet:
			lowest_unmet = attack["unmet"]

	if lowest_unmet < 999:
		score += max(0.0, 60.0 - (lowest_unmet * 20.0))

	return score

# 2.15: Penalises pokemon whose preferred attack discards attached energy
func score_self_discard_penalty(pokemon: card_object) -> float:
	var pokemon_name = pokemon.metadata.get("name", "")
	var max_attack = get_maximum_damage_attack(pokemon)

	if max_attack.is_empty():
		return 0.0

	var penalty = get_attack_text_penalty(max_attack.get("text", ""), pokemon_name)

	# Scale down — this is a tiebreaker, not a dealbreaker
	return penalty * 0.3

# Resolves tiebreaks when multiple pairs share the highest score (3.3)
func resolve_energy_tiebreak(scored_pairs: Array, cpu_eval: Dictionary) -> Dictionary:
	var best_score = scored_pairs[0]["score"]

	# Collect all pairs that share the top score
	var tied = []
	for pair in scored_pairs:
		if pair["score"] == best_score:
			tied.append(pair)
		else:
			break

	if tied.size() == 1:
		return tied[0]

	# Tiebreak 1: Prefer active pokemon over bench
	var active_only = tied.filter(func(p): return p["pokemon"] == opponent_active_pokemon)
	if active_only.size() == 1:
		return active_only[0]
	if active_only.size() > 1:
		tied = active_only

	# Tiebreak 2: Prefer pokemon closer to having a usable attack (lowest unmet)
	var best_unmet = 999
	for pair in tied:
		var key = pair["pokemon"].get_instance_id()
		var pokemon_data = cpu_eval["pokemon_data"].get(key, {})
		for attack in pokemon_data.get("attack_data", []):
			if attack["unmet"] > 0 and attack["unmet"] < best_unmet:
				best_unmet = attack["unmet"]

	var closest = tied.filter(func(p):
		var key = p["pokemon"].get_instance_id()
		var pd = cpu_eval["pokemon_data"].get(key, {})
		var lowest = 999
		for attack in pd.get("attack_data", []):
			if attack["unmet"] > 0 and attack["unmet"] < lowest:
				lowest = attack["unmet"]
		return lowest == best_unmet
	)
	if closest.size() == 1:
		return closest[0]
	if closest.size() > 1:
		tied = closest

	# Tiebreak 3: Prefer pokemon with higher remaining HP
	var best_hp = -1
	for pair in tied:
		if pair["pokemon"].current_hp > best_hp:
			best_hp = pair["pokemon"].current_hp

	for pair in tied:
		if pair["pokemon"].current_hp == best_hp:
			return pair

	return tied[0]

# Scores the value of parsed attack effects for CPU attack selection
func score_parsed_effects(effects: Array, defender: card_object) -> float:
	var score = 0.0

	for effect in effects:
		var flip_mult = 1.0
		if effect.get("flip", "none") != "none":
			flip_mult = 0.5

		if effect["type"] == "status" and effect["target"] == "defender":
			if defender.special_condition == effect["status"]:
				continue
			match effect["status"]:
				"Paralyzed":
					score += 80.0 * flip_mult
				"Asleep":
					score += 50.0 * flip_mult
				"Confused":
					score += 40.0 * flip_mult
				"Poisoned":
					if not defender.is_poisoned:
						score += 30.0 * flip_mult
				"Burned":
					if not defender.is_burned:
						score += 25.0 * flip_mult

		if effect["type"] == "status" and effect["target"] == "self":
			match effect["status"]:
				"Confused":
					score -= 30.0 * flip_mult
				"Asleep":
					score -= 40.0 * flip_mult
				"Poisoned":
					score -= 30.0 * flip_mult
				"Burned":
					score -= 25.0 * flip_mult

		if effect["type"] == "toxic":
			if not defender.is_poisoned or defender.poison_damage < 20:
				score += 50.0 * flip_mult

		if effect["type"] == "self_damage":
			score -= effect.get("damage", 0) * 0.5

		if effect["type"] == "energy_discard_self":
			var count = effect.get("count", 1)
			if count == -1:
				score -= 70.0
			else:
				score -= count * 10.0

		if effect["type"] == "energy_discard_defender":
			if defender.attached_energies.size() > 0:
				score += 25.0 * flip_mult

		if effect["type"] == "bench_damage":
			var target_bench_size = 0
			if effect["target"] == "opponent_bench":
				target_bench_size = player_bench.size()
			elif effect["target"] == "own_bench":
				target_bench_size = opponent_bench.size()
				score -= effect.get("damage", 0) * target_bench_size * 0.3
				continue
			elif effect["target"] == "all_benches":
				target_bench_size = player_bench.size()
				var own_penalty = effect.get("damage", 0) * opponent_bench.size() * 0.3
				score -= own_penalty
			score += effect.get("damage", 0) * target_bench_size * 0.3

		if effect["type"] == "blind":
			score += 30.0 * flip_mult

		if effect["type"] == "retreat_lock":
			score += 20.0 * flip_mult

		if effect["type"] == "draw":
			score += 15.0 * effect.get("count", 1)

		if effect["type"] == "self_heal":
			var max_hp = int(effects[0].get("damage", 0)) if false else 0
			var damage_on_attacker = 0
			if opponent_active_pokemon != null:
				var max_hp_real = int(opponent_active_pokemon.metadata.get("hp", "0"))
				damage_on_attacker = max_hp_real - opponent_active_pokemon.current_hp
			if damage_on_attacker > 0:
				score += 20.0 * flip_mult

		if effect["type"] == "invincible":
			score += 60.0 * flip_mult

		if effect["type"] == "no_damage":
			score += 40.0 * flip_mult

		if effect["type"] == "destiny_bond":
			var attacker_hp_pct = 0.0
			if opponent_active_pokemon != null:
				var max_hp = int(opponent_active_pokemon.metadata.get("hp", "0"))
				attacker_hp_pct = float(opponent_active_pokemon.current_hp) / max(max_hp, 1)
			if attacker_hp_pct <= 0.3:
				score += 50.0
			else:
				score += 10.0

		if effect["type"] == "shielded_damage":
			# Harden is more valuable when we expect low damage attacks next turn
			score += 25.0 * flip_mult

		if effect["type"] == "force_switch":
			# Forcing a switch is useful if the defender has built up energy/status
			if defender.attached_energies.size() >= 2:
				score += 25.0 * flip_mult
			else:
				score += 10.0 * flip_mult

	if defender.is_invincible:
		var defender_bonus = 0.0
		for effect in effects:
			if effect.get("target") == "defender":
				defender_bonus = 0.0
				break
		score = min(score, score - defender_bonus)

	return score
	
################################################### END OPPONENT PRIORITISE FUNCTIONALITY FUNCTIONS ##################################################
######################################################################################################################################################
 
# #######  ######   ##   ##        ######   #######    ####### #######
# ##       ##   ##  ##   ##        ##      ##     ##  ##       ##
# ##       ######   ##   ##  ##### ##      ##     ##  ##       #######
# ##       ##       ##   ##        ##      ##     ##  ##       ##
# #######  ##       #######        #######  #######   ##       #######

######################################################################################################################################################
###################################################### OPPONENT GENERAL FUNCTIONALITY FUNCTIONS ######################################################

# Load all the opponent's data 
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
func opponent_setup_pokemon_from_hand() -> void:
	var selected_pokemon = select_opponent_pokemon_for_setup(opponent_hand)
	var active_pokemon = selected_pokemon.get("active")
	var bench_pokemon_list = selected_pokemon.get("bench", [])
	
	# Remove active pokemon from hand and set it as active
	opponent_hand.erase(active_pokemon)
	opponent_active_pokemon = active_pokemon
	opponent_active_pokemon.current_location = "active"
	opponent_active_pokemon.placed_on_field_this_turn = true
	
	# Remove bench pokemon from hand and add to bench
	for bench_pokemon in bench_pokemon_list:
		opponent_hand.erase(bench_pokemon)
		bench_pokemon.current_location = "bench"
		bench_pokemon.placed_on_field_this_turn = true
		opponent_bench.append(bench_pokemon)
	
	# Update displays
	display_pokemon(true)  # true = opponent
	refresh_hand_display(true)

# Handles start-of-turn duties then hands off to the CPU decision orchestrator
func opponent_start_turn_checks() -> void:
	if _should_bail():
		return
	turn_number += 1
	print("OPPONENT'S TURN START. TURN NUMBER IS ", turn_number)
	await get_tree().create_timer(0.5).timeout
	opponents_turn_active = true
	reset_field_pokemon_turn_flags(true)

	await show_message("Your opponent draws a card")
	var drawn_card = await draw_card_from_deck(true)

	if drawn_card == null:
		return

	refresh_hand_display(true)
	update_deck_icon(true)

	# Future: resolve any start-of-turn triggered effects here

	await cpu_turn_orchestrator()

# Orchestrates all CPU decision phases in the correct order
func cpu_turn_orchestrator() -> void:
	if _should_bail():
		return
	# Phase 0: Activate beneficial Pokemon Powers (Rain Dance, Energy Trans, Damage Swap)
	await cpu_phase_activate_powers()
	
	if _should_bail():
		return
	# Phase 1a: Play Bill first (always highest priority)
	await cpu_phase_play_trainer_cards_priority()

	if _should_bail():
		return
	# Phase 2: Evolution plays
	await cpu_phase_evolution()

	if _should_bail():
		return
	# Phase 3: Bench pokemon plays (uses existing priority scoring)
	await cpu_phase_bench_play()

	if _should_bail():
		return
	# Phase 4: Build evaluation AFTER all board-altering plays have resolved
	var cpu_eval = build_cpu_evaluation()

	# Phase 4b: Play remaining trainer cards after evolutions/bench plays
	await cpu_phase_play_trainer_cards_remaining()

	if _should_bail():
		return
	# Phase 5: First retreat evaluation (before energy attachment)
	var retreat_deferred = await cpu_phase_retreat_first_pass(cpu_eval)

	# Phase 6: Energy attachment
	await cpu_phase_energy_attachment(cpu_eval)

	if _should_bail():
		return
	# Phase 7: Second retreat pass (only if Phase 5 deferred pending energy)
	if retreat_deferred:
		cpu_eval = build_cpu_evaluation()
		await cpu_phase_retreat_second_pass(cpu_eval)

	if _should_bail():
		return
	# Phase 7b: Final trainer card check (re-evaluate after energy/retreat)
	await cpu_phase_play_trainer_cards_remaining()

	if _should_bail():
		return
	# Phase 8: Attack decision (must always be last)
	await cpu_phase_attack(cpu_eval)

	if _should_bail():
		return
	await get_tree().create_timer(0.5).timeout
	await show_message("Your opponent ends their turn")
	await inbetween_turn_checks(false)

# CPU plays any valid evolutions from hand onto field pokemon using pair scoring
func cpu_phase_evolution() -> void:
	if turn_number <= 2:
		return

	while true:
		# Build list of all valid (evo_card, target) pairs and score them
		var scored_pairs = []
		for card in opponent_hand:
			var valid_targets = get_valid_evolution_targets(card, true)
			for target in valid_targets:
				var result = evaluate_evolution_pair(card, target)
				scored_pairs.append(result)

		if scored_pairs.is_empty():
			break

		# Sort by score descending and pick the best pair
		scored_pairs.sort_custom(func(a, b): return a["score"] > b["score"])
		var best = scored_pairs[0]

		print("CPU evolving " + best["target"].metadata["name"] + " into " + best["evo_card"].metadata["name"] + " (Score: " + str(int(best["score"])) + ")")
		for reason in best["reasons"]:
			print("  - " + reason)

		# Set the globals that perform_evolution reads from
		evolution_card_awaiting_target = best["evo_card"]
		selected_card_for_action = best["target"]
		perform_evolution(true)

		await show_message("Opponent evolved " + best["target"].metadata["name"].to_upper() + " into " + best["evo_card"].metadata["name"].to_upper() + "!")
	
		var evo_target_node = opponent_active_container if best["evo_card"].current_location == "active" else opponent_bench_container
		var evo_scale = card_scales[8] if best["evo_card"].current_location == "active" else card_scales[11]
		var evo_texture = get_card_texture(best["evo_card"])
		await animate_card_a_to_b(opponent_hand_container, evo_target_node, 0.3, evo_texture, evo_scale)

		display_pokemon(true)
		display_active_pokemon_energies(true)
		refresh_hand_display(true)

		await get_tree().process_frame
	
		await play_evolution_effect(best["evo_card"])

		# Clean up globals
		evolution_card_awaiting_target = null
		selected_card_for_action = null

# R.1: Determines if there is a reason for the active to consider retreating
func evaluate_retreat_reasons(cpu_eval: Dictionary) -> bool:
	var active_key = opponent_active_pokemon.get_instance_id()
	var active_data = cpu_eval["pokemon_data"].get(active_key, {})
	var can_attack = active_data.get("can_attack", false)

	# Reason 1: Mutual guaranteed KO situation
	# Only ignore the guaranteed KO threat if WE can also guarantee a KO back
	if cpu_eval.get("cpu_active_guaranteed_ko", false) and can_attack:
		# Check if our attack is guaranteed to KO the player's active
		var player_hp = player_active_pokemon.current_hp
		var guaranteed_ko_player = false
		
		for attack in active_data.get("attack_data", []):
			if attack["unmet"] == 0:  # Can use this attack
				if attack["damage_min"] >= player_hp:  # Guaranteed to KO
					guaranteed_ko_player = true
					break
					
		if guaranteed_ko_player:
			print("CPU NOT retreating: mutual KO - will attack and trade")
			return false  # Don't retreat, attack instead
		else:
			# Before retreating, check if any bench pokemon would actually survive
			# If all bench options would ALSO be guaranteed KO'd, retreating is pointless
			var any_bench_survives = false
			var player_types = player_active_pokemon.metadata.get("types", ["Colorless"])
			for bench_pokemon in opponent_bench:
				var bench_hp = bench_pokemon.current_hp
				var bench_would_die = false
				for p_attack in player_active_pokemon.metadata.get("attacks", []):
					if get_unmet_energy_count(p_attack, player_active_pokemon) > 0:
						continue
					var p_range = get_attack_damage_range(p_attack, player_active_pokemon, bench_pokemon)
					var p_result = calculate_final_damage(p_range["min"], player_types, bench_pokemon)
					if p_result["damage"] >= bench_hp:
						bench_would_die = true
						break
				if not bench_would_die:
					any_bench_survives = true
					break
			
			if not any_bench_survives:
				print("CPU NOT retreating: all bench pokemon also face guaranteed KO")
				return false
			
			print("CPU considering retreat: guaranteed KO threat and cannot KO back")
			return true  # Do retreat, we'd lose the trade

	# Reason 2: Active is at risk of KO (potential or bench threat)
	if cpu_eval.get("cpu_active_potential_ko", false) or cpu_eval.get("player_bench_ko_threat", false):
		# Before retreating, check if any bench pokemon would survive
		if not _any_bench_survives_player_attack():
			print("CPU NOT retreating: all bench pokemon also face KO from potential threat")
			return false
		print("CPU considering retreat: potential KO threat")
		return true

	# Reason 3: Active cannot attack and has no path to attacking within 1-2 turns
	if not can_attack:
		var nearest_attack = 999
		for attack in active_data.get("attack_data", []):
			if attack["unmet"] < nearest_attack:
				nearest_attack = attack["unmet"]

		# Count matching energy cards in hand
		var matching_energy_in_hand = 0
		for card in opponent_hand:
			if card.metadata.get("supertype", "").to_lower() != "energy":
				continue
			var energy_types = get_energy_provided_by_card(card)
			for attack in active_data.get("attack_data", []):
				for req in attack.get("cost", []):
					if req == "Colorless" or req in energy_types:
						matching_energy_in_hand += 1
						break

		if nearest_attack > matching_energy_in_hand + 1:
			print("CPU considering retreat: active has no viable attack path")
			return true

	return false

# Helper: checks if any bench pokemon survives the player's best usable attack
func _any_bench_survives_player_attack() -> bool:
	if player_active_pokemon == null:
		return true
	var player_types = player_active_pokemon.metadata.get("types", ["Colorless"])
	for bench_pokemon in opponent_bench:
		var bench_hp = bench_pokemon.current_hp
		var bench_would_die = false
		for p_attack in player_active_pokemon.metadata.get("attacks", []):
			if get_unmet_energy_count(p_attack, player_active_pokemon) > 0:
				continue
			var p_range = get_attack_damage_range(p_attack, player_active_pokemon, bench_pokemon)
			var p_result = calculate_final_damage(p_range["min"], player_types, bench_pokemon)
			if p_result["damage"] >= bench_hp:
				bench_would_die = true
				break
		if not bench_would_die:
			return true
	return false

# Scores all (pokemon, energy_card) pairs and attaches the best one (Phase 0, 2, 3)
func cpu_phase_energy_attachment(cpu_eval: Dictionary) -> void:
	# Phase 0.1: Skip if no energy cards in hand
	var energy_cards_in_hand = []
	for card in opponent_hand:
		if card.metadata.get("supertype", "").to_lower() == "energy":
			energy_cards_in_hand.append(card)

	if energy_cards_in_hand.is_empty() or opponent_energy_played_this_turn:
		return

	# Phase 0.2: Build candidate targets (active + bench)
	var candidates = get_all_cpu_field_pokemon()

	# Phase 2: Score every (pokemon, energy_card) pair
	var scored_pairs = []
	for pokemon in candidates:
		var key = pokemon.get_instance_id()
		var pokemon_data = cpu_eval["pokemon_data"].get(key, {})
		for energy_card in energy_cards_in_hand:
			var score = score_energy_pair(pokemon, energy_card, cpu_eval, pokemon_data)
			scored_pairs.append({
				"pokemon": pokemon,
				"energy_card": energy_card,
				"score": score
			})

	if scored_pairs.is_empty():
		return

	# Phase 3.1: Sort by score descending
	scored_pairs.sort_custom(func(a, b): return a["score"] > b["score"])
	var best = scored_pairs[0]

	# Phase 3.3: Tiebreaking
	best = resolve_energy_tiebreak(scored_pairs, cpu_eval)

	# Phase 3.4: Always attach even if score is negative
	var target = best["pokemon"]
	var energy = best["energy_card"]

	print("CPU attaching " + energy.metadata["name"] + " to " + target.metadata["name"] + " (Score: " + str(int(best["score"])) + ")")

	# Perform the attachment
	opponent_hand.erase(energy)
	target.attached_energies.append(energy)
	opponent_energy_played_this_turn = true

	await show_message("Opponent attached " + energy.metadata["name"].to_upper() + " to " + target.metadata["name"].to_upper() + "!")

	var energy_target_node = opponent_energy_container if target == opponent_active_pokemon else opponent_bench_container
	var energy_texture = get_card_texture(energy)
	await animate_card_a_to_b(opponent_hand_container, energy_target_node, 0.2, energy_texture, card_scales[12])

	refresh_hand_display(true)
	display_pokemon(true)
	display_active_pokemon_energies(true)
	await get_tree().process_frame
	await play_energy_attached_effect(target, energy)
	
# Chooses and executes an attack to end the CPU turn (Phase 8)
func cpu_phase_attack(cpu_eval: Dictionary) -> void:
	if opponent_active_pokemon == null or player_active_pokemon == null:
		return
	
	if turn_number <= 1:
		return
	
	if opponent_active_pokemon.special_condition == "Paralyzed":
		print("CPU cannot attack: active is Paralyzed")
		return
	if opponent_active_pokemon.special_condition == "Asleep":
		print("CPU cannot attack: active is Asleep")
		return
	
	# Check attack readiness from live board state, not stale cpu_eval
	var has_usable_attack = false
	for attack in opponent_active_pokemon.metadata.get("attacks", []):
		if get_unmet_energy_count(attack, opponent_active_pokemon) == 0 and not is_attack_disabled(opponent_active_pokemon, attack.get("name", "")):
			has_usable_attack = true
			break

	if not has_usable_attack:
		print("CPU cannot attack: no usable attacks")
		return

	var cpu_types = opponent_active_pokemon.metadata.get("types", ["Colorless"])
	var player_hp = player_active_pokemon.current_hp
	var attacks = opponent_active_pokemon.metadata.get("attacks", [])
	var pokemon_name = opponent_active_pokemon.metadata.get("name", "")
	
	# Check if CPU is guaranteed to be KO'd next turn
	var ko_threats = evaluate_ko_threats()
	var cpu_will_be_koed = ko_threats["cpu_active_guaranteed_ko"]
	
	# Score each usable attack
	var best_attack_index = -1
	var best_attack_score = -999.0

	for i in range(attacks.size()):
		var attack = attacks[i]
		var attack_name_lower = attack.get("name", "").to_lower()
		var attack_text = attack.get("text", "").to_lower()
		
		if get_unmet_energy_count(attack, opponent_active_pokemon) > 0:
			continue
		if is_attack_disabled(opponent_active_pokemon, attack.get("name", "")):
			continue

		var score = 0.0
		var damage_range = get_attack_damage_range(attack, opponent_active_pokemon, player_active_pokemon)
		var min_result = calculate_final_damage(damage_range["min"], cpu_types, player_active_pokemon)
		var max_result = calculate_final_damage(damage_range["max"], cpu_types, player_active_pokemon)
		var parsed_effects = parse_card_text_effects(attack.get("text", ""), pokemon_name)

		# ---- GUARANTEED KO: Strongly prefer ----
		if min_result["damage"] >= player_hp:
			score += 500.0
			score -= (min_result["damage"] - player_hp) * 0.5
		# ---- POTENTIAL KO: Variable damage might KO ----
		elif max_result["damage"] >= player_hp:
			score += 200.0
		
		# ---- BASE DAMAGE CONTRIBUTION ----
		score += min_result["damage"] * 2.0

		# ---- STATUS CONDITION SCORING (items 6-7) ----
		var has_status_effect_only = false
		for effect in parsed_effects:
			if effect["type"] == "status" and effect["target"] == "defender":
				var status = effect["status"]
				var already_has = false
				if status in ["Paralyzed", "Asleep", "Confused"]:
					already_has = (player_active_pokemon.special_condition == status)
				elif status == "Poisoned":
					already_has = player_active_pokemon.is_poisoned
				elif status == "Burned":
					already_has = player_active_pokemon.is_burned
				
				if already_has:
					# Defender already has this status - strongly deprioritise this attack
					# if there's another attack available, use that instead
					score -= 100.0
					has_status_effect_only = true
				# If not already applied, the existing score_parsed_effects handles the bonus

		# ---- SELF DAMAGE VS GUARANTEED KO (items 8-9) ----
		var has_self_damage = false
		var self_damage_amount = 0
		var has_energy_discard = false
		var discard_count = 0
		for effect in parsed_effects:
			if effect["type"] == "self_damage":
				has_self_damage = true
				self_damage_amount = effect.get("damage", 0)
			if effect["type"] == "energy_discard_self":
				has_energy_discard = true
				discard_count = effect.get("count", 1)
		
		# If this attack guarantees KO but has drawbacks, and another attack ALSO guarantees KO without drawbacks
		# prefer the one without drawbacks (item 8, 9)
		if min_result["damage"] >= player_hp:
			if has_energy_discard:
				score -= 50.0  # Penalise discard on guaranteed KO (prefer no-drawback KO)
			if has_self_damage:
				score -= 20.0  # Penalise self-damage on guaranteed KO (less penalty than discard)
		
		# ---- ZAPDOS-STYLE: Both attacks have drawbacks (item 10) ----
		# Self-damage is less bad than energy discard
		if has_self_damage and not has_energy_discard:
			# Check if self-damage would KO us
			if opponent_active_pokemon.current_hp - self_damage_amount <= 0:
				score -= 300.0  # Strongly avoid suicide
			else:
				score -= self_damage_amount * 0.3  # Light penalty
		
		if has_energy_discard:
			if discard_count == -1:
				score -= 70.0  # Heavy penalty for discard all
			else:
				score -= discard_count * 15.0
			
			# But if we're going to be KO'd next turn anyway, discard matters less
			if cpu_will_be_koed:
				if discard_count == -1:
					score += 40.0  # Reduce penalty
				else:
					score += discard_count * 8.0
		
		# ---- HEAL ATTACKS (item 11: Starmie/Kadabra Recover) ----
		if "remove all damage counters" in attack_text and damage_range["min"] == 0:
			var current_damage = opponent_active_pokemon.get_max_hp() - opponent_active_pokemon.current_hp
			if current_damage == 0:
				score -= 200.0  # No damage to heal - waste of attack
			elif cpu_will_be_koed:
				# Check if healing would prevent the KO
				var would_survive = false
				for player_attack in player_active_pokemon.metadata.get("attacks", []):
					if get_unmet_energy_count(player_attack, player_active_pokemon) == 0:
						var p_range = get_attack_damage_range(player_attack, player_active_pokemon, opponent_active_pokemon)
						var p_types = player_active_pokemon.metadata.get("types", ["Colorless"])
						var p_result = calculate_final_damage(p_range["max"], p_types, opponent_active_pokemon)
						if p_result["damage"] < opponent_active_pokemon.get_max_hp():
							would_survive = true
				if would_survive:
					score += 150.0  # Healing saves us from KO
				else:
					score -= 50.0  # Healing won't save us, better to attack
			else:
				score -= 100.0  # Not in danger, prefer attacking
		
		# ---- BARRIER/INVINCIBLE ATTACKS (item 11.6: Mewtwo Barrier) ----
		if "prevent all effects of attacks, including damage" in attack_text and damage_range["min"] == 0:
			if cpu_will_be_koed:
				# Check if other attacks can KO the player
				var other_can_ko = false
				for j in range(attacks.size()):
					if j == i:
						continue
					var other_attack = attacks[j]
					if get_unmet_energy_count(other_attack, opponent_active_pokemon) > 0:
						continue
					var other_range = get_attack_damage_range(other_attack, opponent_active_pokemon, player_active_pokemon)
					var other_result = calculate_final_damage(other_range["min"], cpu_types, player_active_pokemon)
					if other_result["damage"] >= player_hp:
						other_can_ko = true
						break
				if other_can_ko:
					score -= 100.0  # Can KO with other attack, do that instead
				else:
					score += 100.0  # Can't KO, protect ourselves
			else:
				score -= 80.0  # Not in danger, prefer attacking
		
		# ---- GENERAL EFFECT SCORING ----
		var effect_score = score_parsed_effects(parsed_effects, player_active_pokemon)
		score += effect_score

		if score > best_attack_score:
			best_attack_score = score
			best_attack_index = i

	if best_attack_index == -1:
		print("CPU found no suitable attack")
		return

	# Execute the chosen attack
	var chosen_attack = attacks[best_attack_index]
	var chosen_name = chosen_attack.get("name", "")
	var chosen_text = chosen_attack.get("text", "").to_lower()

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_attack_sound)
	await show_message("Opponent's " + opponent_active_pokemon.metadata["name"].to_upper() + " used " + chosen_name.to_upper() + "!")
	
	# Handle special CPU attacks
	if "choose 1 of the defending" in chosen_text and "copies that attack" in chosen_text:
		await execute_metronome(opponent_active_pokemon, player_active_pokemon, true)
		await check_all_knockouts()
		display_active_pokemon_energies(true)
		return
	
	if "mirror move" in chosen_name.to_lower() or ("was attacked last turn" in chosen_text and "final result" in chosen_text):
		await execute_mirror_move(opponent_active_pokemon, player_active_pokemon, true)
		await check_all_knockouts()
		display_active_pokemon_energies(true)
		return
	
	if "choose 1 of the defending" in chosen_text and "can't use that attack" in chosen_text:
		await execute_amnesia(opponent_active_pokemon, player_active_pokemon, true)
		display_active_pokemon_energies(true)
		return
	
	if "conversion 1" in chosen_name.to_lower():
		await execute_conversion(opponent_active_pokemon, player_active_pokemon, true, true)
		display_active_pokemon_energies(true)
		return
	if "conversion 2" in chosen_name.to_lower():
		await execute_conversion(opponent_active_pokemon, player_active_pokemon, true, false)
		display_active_pokemon_energies(true)
		return
	
	if await handle_attack_confusion(opponent_active_pokemon, true):
		display_active_pokemon_energies(true)
		return
	
	if await handle_attack_blind(opponent_active_pokemon, true):
		display_active_pokemon_energies(true)
		return
	
	# Resolve variable damage with coin flips
	var variable_result = await resolve_attack_variable_damage(chosen_attack, opponent_active_pokemon, player_active_pokemon, true)
	var resolved_base = variable_result["damage"]
	var flip_result = variable_result["flip_result"]
	
	if variable_result["attack_failed"]:
		for msg in variable_result["messages"]:
			await show_message(msg)
		await process_attack_effects(chosen_attack, opponent_active_pokemon, player_active_pokemon, true, flip_result)
		display_active_pokemon_energies(true)
		return
	
	for msg in variable_result["messages"]:
		await show_message(msg)
	
	var result = calculate_final_damage(resolved_base, cpu_types, player_active_pokemon, opponent_active_pokemon)
	var final_damage = result["damage"]
	
	if check_defender_invincible(player_active_pokemon, false):
		display_active_pokemon_energies(true)
		return

	final_damage = apply_defender_no_damage_shield(player_active_pokemon, final_damage, false)

	await display_and_apply_attack_damage(opponent_active_pokemon, player_active_pokemon, final_damage, result["modifiers"], true, resolved_base)
	
	# Store last attack for Mirror Move tracking
	last_attack_on_player = {"damage": final_damage, "attack": chosen_attack, "attacker_types": cpu_types}
	opponent_attacked_this_turn = true
	
	await process_attack_effects(chosen_attack, opponent_active_pokemon, player_active_pokemon, true, flip_result)

	await check_all_knockouts()
	display_active_pokemon_energies(true)

# CPU evaluates and plays basic pokemon from hand onto bench using threshold scoring
func cpu_phase_bench_play() -> void:
	var bench_thresholds = {0: -999, 1: 100, 2: 200, 3: 350, 4: 500}

	while opponent_bench.size() < 5:
		var current_bench_count = opponent_bench.size()
		var score_threshold = bench_thresholds.get(current_bench_count, 9999)

		# Score all basic pokemon in hand using existing priority criteria
		var best_card: card_object = null
		var best_score: float = -999.0
		for card in opponent_hand:
			if not is_basic_pokemon(card):
				continue
			var result = evaluate_opponents_start_setup_pokemon_choices(card, opponent_hand)
			var score = result.get("total_score", 0)
			if score > best_score:
				best_score = score
				best_card = card

		# Stop if no basic pokemon in hand or best doesn't meet threshold
		if best_card == null or best_score <= score_threshold:
			break

		# Play the pokemon onto the bench
		opponent_hand.erase(best_card)
		best_card.current_location = "bench"
		best_card.placed_on_field_this_turn = true
		opponent_bench.append(best_card)

		print("CPU played " + best_card.metadata["name"] + " to bench (Score: " + str(int(best_score)) + ", Threshold: " + str(score_threshold) + ")")

		await show_message("Opponent placed " + best_card.metadata["name"].to_upper() + " on the bench!")
		var card_texture = get_card_texture(best_card)
		await animate_card_a_to_b(opponent_hand_container, opponent_bench_container, 0.3, card_texture, card_scales[11])
		display_pokemon(true)
		refresh_hand_display(true)

# R.5: Selects the best bench replacement and performs the retreat
func execute_cpu_retreat(cpu_eval: Dictionary) -> void:
	var best_replacement = pick_best_bench_replacement(opponent_bench, player_active_pokemon, cpu_eval)

	if best_replacement == null:
		print("CPU retreat failed: no valid bench replacement")
		return
		
	var pre_check = await check_confused_retreat(opponent_active_pokemon, true, "pre_energy")
	if not pre_check:
		display_hp_circles_above_align(opponent_active_pokemon, true)
		await check_all_knockouts()
		display_pokemon(true)
		return
		
	# Discard energy for retreat cost
	var retreat_cost = get_retreat_cost(opponent_active_pokemon)
	var discarded_energies = []
	for i in range(retreat_cost):
		if opponent_active_pokemon.attached_energies.size() > 0:
			var energy = opponent_active_pokemon.attached_energies.pop_back()
			send_card_to_discard(energy, true)
			discarded_energies.append(energy)

	var post_check = await check_confused_retreat(opponent_active_pokemon, true, "post_energy")
	if not post_check:
		display_pokemon(true)
		display_active_pokemon_energies(true)
		return

	# Swap positions
	var old_active = opponent_active_pokemon
	opponent_bench.erase(best_replacement)
	opponent_bench.append(old_active)
	old_active.current_location = "bench"
	best_replacement.current_location = "active"
	opponent_active_pokemon = best_replacement
	opponent_retreated_this_turn = true

	print("CPU retreated " + old_active.metadata["name"] + " for " + best_replacement.metadata["name"])
	await animate_retreat(old_active, best_replacement, discarded_energies, true)
	clear_all_statuses(old_active, true)
	display_pokemon(true)
	display_active_pokemon_energies(true)

# CPU automatically picks a random prize card and moves it to hand
func opponent_take_prize_card() -> void:
	if opponent_prize_cards.size() == 0:
		return
	
	var random_index = randi() % opponent_prize_cards.size()
	var chosen_card = opponent_prize_cards[random_index]
	
	await show_message("OPPONENT TAKES A PRIZE CARD!")
	await take_prize_card(chosen_card, true)

################################################## END OPPONENT PRIORITISE FUNCTIONALITY FUNCTIONS ###################################################
######################################################################################################################################################

######################################################################################################################################################
#  ########  ######     ##     ########  ##    ##  ########  ######          &&&&&&&          #######    #######  ##      ##  ########  ######    #######
#     ##     ##   ##   ####       ##     ###   ##  ##        ##   ##        &&      &         ##    ##  ##     ## ##      ##  ##        ##   ##  ##
#     ##     ######   ##  ##      ##     ## ## ##  ########  ######    ###  &&&&&&      ###   #######   ##     ## ##  ##  ##  ########  ######    #######
#     ##     ##  ##  ########     ##     ##  ####  ##        ##  ##        &&     &&&         ##        ##     ## ## #### ##  ##        ##  ##         ##
#     ##     ##   ## ##      ## #######  ##   ###  ########  ##   ##        &&&&&& &          ##         #######   ###  ###   ########  ##   ##  #######
######################################################################################################################################################
##################################################### TRAINER CARD & POKEMON POWER FUNCTIONS ########################################################

############################################### Section A: HELPER FUNCTIONS #########################################################################

# Returns true if the Pokemon has any status condition that blocks Pokemon Powers
func is_power_blocked_by_status(pokemon: card_object) -> bool:
	if pokemon == null:
		return true
	if pokemon.special_condition in ["Paralyzed", "Asleep", "Confused"]:
		return true
	if pokemon.is_poisoned:
		return true
	return false

# Returns true if a card is a trainer card
func is_trainer_card(card: card_object) -> bool:
	return card.metadata.get("supertype", "").to_lower() == "trainer"

# Returns true if a card is a bench token trainer (Clefairy Doll, Mysterious Fossil)
func is_bench_token_trainer(card: card_object) -> bool:
	if not is_trainer_card(card):
		return false
	# Bench tokens have an HP field in their metadata
	if card.metadata.has("hp") and int(card.metadata.get("hp", "0")) > 0:
		var rules = card.metadata.get("rules", [])
		for rule in rules:
			if "as if it were a basic" in rule.to_lower():
				return true
	return false

# Returns true if a card is an attached trainer (PlusPower, Defender)
func is_attached_trainer(card: card_object) -> bool:
	if not is_trainer_card(card):
		return false
	var card_name = card.metadata.get("name", "").to_lower()
	return card_name in ["pluspower", "defender"]

# Returns true if a card is a stadium trainer (future-proofing)
func is_stadium_trainer(card: card_object) -> bool:
	if not is_trainer_card(card):
		return false
	var subtypes = card.metadata.get("subtypes", [])
	for st in subtypes:
		if st.to_lower() == "stadium":
			return true
	return false

# Checks if Charizard's Energy Burn power is active on a pokemon
func is_energy_burn_active(pokemon: card_object) -> bool:
	if pokemon == null:
		return false
	var name = pokemon.metadata.get("name", "")
	if name != "Charizard":
		return false
	# Check if it has the Energy Burn ability
	var abilities = pokemon.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") == "Energy Burn":
			# Blocked by status
			if is_power_blocked_by_status(pokemon):
				return false
			return true
	return false

# Resets power_used_this_turn for all pokemon on one side
func reset_power_used_flags(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	if active != null:
		active.power_used_this_turn = false
	for bp in bench:
		bp.power_used_this_turn = false

# Discards PlusPower from a pokemon at end of turn
func discard_pluspower_from_pokemon(pokemon: card_object, is_opponent: bool) -> void:
	if pokemon == null or pokemon.pluspower_count <= 0:
		return
	# Remove PlusPower attached_cards
	var to_remove = []
	for card in pokemon.attached_cards:
		if card.metadata.get("name", "").to_lower() == "pluspower":
			to_remove.append(card)
	var attached_node = opponent_attached_cards_container if is_opponent else player_attached_cards_container
	var discard_node = opponent_discard_icon if is_opponent else player_discard_icon
	for card in to_remove:
		pokemon.attached_cards.erase(card)
		card.current_location = "discard"
		var discard = opponent_discard_pile if is_opponent else player_discard_pile
		discard.append(card)
		# Animate PlusPower from attached cards container to discard pile
		var card_texture = get_card_texture(card)
		await animate_card_a_to_b(attached_node, discard_node, 0.2, card_texture, card_scales[10])
	pokemon.pluspower_count = 0
	update_discard_pile_display(is_opponent)
	display_attached_trainer_cards(is_opponent)
	if to_remove.size() > 0:
		print("END OF TURN: Discarded ", to_remove.size(), " PlusPower(s) from ", pokemon.metadata.get("name", ""))

# Ticks down Defender turn counters and discards expired Defenders
func tick_defender_counters(is_opponent: bool) -> void:
	var all_pokemon = []
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	if active != null:
		all_pokemon.append(active)
	all_pokemon.append_array(bench)
	
	for pokemon in all_pokemon:
		if pokemon.defender_turns_remaining < 0:
			continue
		pokemon.defender_turns_remaining -= 1
		if pokemon.defender_turns_remaining < 0:
			# Discard the Defender card
			var to_remove = []
			for card in pokemon.attached_cards:
				if card.metadata.get("name", "").to_lower() == "defender":
					to_remove.append(card)
			var attached_node = opponent_attached_cards_container if is_opponent else player_attached_cards_container
			var discard_node = opponent_discard_icon if is_opponent else player_discard_icon
			for card in to_remove:
				pokemon.attached_cards.erase(card)
				card.current_location = "discard"
				var discard = opponent_discard_pile if is_opponent else player_discard_pile
				discard.append(card)
				# Animate Defender from attached cards container to discard pile
				var card_texture = get_card_texture(card)
				await animate_card_a_to_b(attached_node, discard_node, 0.2, card_texture, card_scales[10])
			update_discard_pile_display(is_opponent)
			display_attached_trainer_cards(is_opponent)
			print("DEFENDER EXPIRED on ", pokemon.metadata.get("name", ""))

# Displays attached trainer cards (PlusPower, Defender) next to active pokemon
func display_attached_trainer_cards(is_opponent: bool) -> void:
	var container = opponent_attached_cards_container if is_opponent else player_attached_cards_container
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	
	for child in container.get_children():
		child.queue_free()
	
	if active == null:
		return
	
	var card_size = card_scales[11]  # Same size as energy cards
	var overlap_offset = 80
	for i in range(active.attached_cards.size()):
		var attached = active.attached_cards[i]
		var display = TextureRect.new()
		display.set_script(card_display_script)
		container.add_child(display)
		display.load_card_image(attached.uid, card_size, attached)
		display.position.x = overlap_offset * i if is_opponent else -(i * overlap_offset)
		display.mouse_filter = MOUSE_FILTER_IGNORE

############################################### Section B: SHARED CPU DISCARD PRIORITY #############################################################

# Plays a healing animation: restores red HP circles to green with delay, shows floating +HP label
func play_heal_animation(pokemon: card_object, heal_amount: int, is_opponent: bool) -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
	if heal_amount <= 0:
		return
	var loc = get_pokemon_screen_location(pokemon)
	if not loc.is_empty():
		show_floating_label("+" + str(heal_amount) + " HP", loc["position"] + Vector2(0, -20), true)
	
	# Animate HP circles restoring one by one with delay
	var circles_to_restore = heal_amount / 10
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var display_pokemon_ref = pokemon if pokemon == active else active
	for i in range(circles_to_restore):
		# Temporarily set HP partway through the heal for incremental circle display
		var partial_hp = (pokemon.current_hp - heal_amount) + ((i + 1) * 10)
		var saved_hp = pokemon.current_hp
		pokemon.current_hp = min(partial_hp, saved_hp)
		display_hp_circles_above_align(display_pokemon_ref if display_pokemon_ref != null else pokemon, is_opponent)
		pokemon.current_hp = saved_hp
		await get_tree().create_timer(0.2).timeout
	display_hp_circles_above_align(display_pokemon_ref if display_pokemon_ref != null else pokemon, is_opponent)
	display_pokemon(is_opponent)

# Builds a combined array of bench + active pokemon with active last (for enlarged display with spacer)
func build_field_pokemon_array(is_opponent: bool) -> Array:
	var bench = opponent_bench if is_opponent else player_bench
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var combined = bench.duplicate()
	if active != null:
		combined.append(active)
	return combined

# Returns the lowest-priority cards from the CPU's hand for discarding
# exclude_card: the trainer card being played (must not be discarded)
func cpu_get_discard_priority(hand: Array, count: int, exclude_card: card_object = null) -> Array:
	var candidates = []
	for card in hand:
		if card == exclude_card:
			continue
		var priority = _score_card_for_discard(card)
		candidates.append({"card": card, "priority": priority})
	
	# Sort by priority ascending (lowest priority = discard first)
	candidates.sort_custom(func(a, b): return a["priority"] < b["priority"])
	
	var result = []
	for i in range(min(count, candidates.size())):
		result.append(candidates[i]["card"])
	return result

# Scores a card for discard priority (lower = more likely to be discarded)
func _score_card_for_discard(card: card_object) -> float:
	var score = 50.0 # default middle
	var supertype = card.metadata.get("supertype", "").to_lower()
	var subtypes = card.metadata.get("subtypes", [])
	
	# Priority 1: Duplicate Basic Pokemon already in play
	if supertype == "pokémon" and is_basic_pokemon(card):
		var card_name = card.metadata.get("name", "")
		var already_in_play = false
		if opponent_active_pokemon != null and opponent_active_pokemon.metadata.get("name", "") == card_name:
			already_in_play = true
		for bp in opponent_bench:
			if bp.metadata.get("name", "") == card_name:
				already_in_play = true
		if already_in_play and opponent_bench.size() >= 2:
			return 10.0
	
	# Priority 2: Excess energy (if hand has 3+ energy cards)
	if supertype == "energy":
		var energy_count = 0
		for c in opponent_hand:
			if c.metadata.get("supertype", "").to_lower() == "energy":
				energy_count += 1
		if energy_count >= 4:
			return 15.0
		elif energy_count >= 3:
			return 25.0
		# Never discard last energy
		if energy_count <= 1:
			return 90.0
		return 40.0
	
	# Priority 3: Unplayable evolution cards
	if supertype == "pokémon" and not is_basic_pokemon(card):
		var evolves_from = card.metadata.get("evolvesFrom", "")
		var has_base_in_play = false
		var has_base_in_hand = false
		if opponent_active_pokemon != null and opponent_active_pokemon.metadata.get("name", "") == evolves_from:
			has_base_in_play = true
		for bp in opponent_bench:
			if bp.metadata.get("name", "") == evolves_from:
				has_base_in_play = true
		for c in opponent_hand:
			if c.metadata.get("name", "") == evolves_from:
				has_base_in_hand = true
		
		if not has_base_in_play and not has_base_in_hand:
			# Check if it's Stage 2 (never discard if possible)
			if "Stage 2" in subtypes:
				return 30.0
			return 20.0
		# Has matching base: high value, don't discard
		if "Stage 2" in subtypes:
			return 95.0
		return 80.0
	
	# Priority 4: Low-priority trainer cards
	if supertype == "trainer":
		var trainer_score = cpu_score_trainer_card(card)
		if trainer_score <= 0:
			return 18.0
		if trainer_score <= 30:
			return 35.0
		return 70.0
	
	# Priority 5: Basic pokemon with full bench
	if supertype == "pokémon" and is_basic_pokemon(card):
		if opponent_bench.size() >= 4:
			return 22.0
		return 55.0
	
	return score

############################################### Section C: TRAINER CARD PLAY ANIMATION ##############################################################

# Validates whether a trainer card can be played based on current game state
# Returns empty string if playable, or an error message if conditions aren't met
func validate_trainer_can_be_played(card: card_object, is_opponent: bool) -> String:
	var card_id = card.uid.to_lower()
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var hand = opponent_hand if is_opponent else player_hand
	var deck = opponent_deck if is_opponent else player_deck
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	var opp_active = player_active_pokemon if is_opponent else opponent_active_pokemon
	var opp_bench = player_bench if is_opponent else opponent_bench
	
	match card_id:
		"base1-76": # Pokemon Breeder
			# Check for Stage 2 in hand AND a matching Basic in play
			var stage2_cards = []
			for c in hand:
				if c == card:
					continue
				var subtypes = c.metadata.get("subtypes", [])
				if "Stage 2" in subtypes:
					stage2_cards.append(c)
			if stage2_cards.size() == 0:
				return "No Stage 2 Pokemon in hand to play!"
			# Check if any Stage 2 has a matching Basic on field
			var has_valid_target = false
			var all_in_play = []
			if active != null:
				all_in_play.append(active)
			all_in_play.append_array(bench)
			for s2 in stage2_cards:
				for pokemon in all_in_play:
					if pokemon.placed_on_field_this_turn:
						continue
					if not is_basic_pokemon(pokemon):
						continue
					if _basic_matches_stage2(pokemon, s2):
						has_valid_target = true
						break
				if has_valid_target:
					break
			if not has_valid_target:
				return "No valid Basic Pokemon to evolve with Breeder!"
		
		"base1-72": # Devolution Spray
			var has_evolved = false
			if active != null and active.attached_pre_evolutions.size() > 0:
				has_evolved = true
			for bp in bench:
				if bp.attached_pre_evolutions.size() > 0:
					has_evolved = true
					break
			if not has_evolved:
				return "No evolved Pokemon to devolve!"
		
		"base1-94": # Potion
			var damaged = build_field_pokemon_array(is_opponent).filter(func(p): return p.current_hp < int(p.metadata.get("hp", "0")))
			if damaged.size() == 0:
				return "No Pokemon with damage to heal!"
		
		"base1-90": # Super Potion
			var valid_targets = []
			var all_pokemon = build_field_pokemon_array(is_opponent)
			for p in all_pokemon:
				if p.current_hp < int(p.metadata.get("hp", "0")) and p.attached_energies.size() > 0:
					valid_targets.append(p)
			if valid_targets.size() == 0:
				return "No Pokemon with both damage and energy for Super Potion!"
		
		"base1-92": # Energy Removal
			var opp_all = build_field_pokemon_array(not is_opponent)
			var has_energy = false
			for p in opp_all:
				if p.attached_energies.size() > 0:
					has_energy = true
					break
			if not has_energy:
				return "Opponent has no energy to remove!"
		
		"base1-79": # Super Energy Removal
			# Check own pokemon have energy
			var own_all = build_field_pokemon_array(is_opponent)
			var own_has_energy = false
			for p in own_all:
				if p.attached_energies.size() > 0:
					own_has_energy = true
					break
			if not own_has_energy:
				return "You have no energy to discard for Super Energy Removal!"
			# Check opponent pokemon have energy
			var target_all = build_field_pokemon_array(not is_opponent)
			var target_has_energy = false
			for p in target_all:
				if p.attached_energies.size() > 0:
					target_has_energy = true
					break
			if not target_has_energy:
				return "Opponent has no energy to remove!"
		
		"base1-70": # Clefairy Doll
			if bench.size() >= 5:
				return "Bench is full! Cannot place Clefairy Doll!"
		
		"base1-71": # Computer Search
			if hand.size() < 3: # Need at least 2 cards to discard + the computer search itself is already removed
				# hand still contains the card at this point for player validation
				var cards_available = 0
				for c in hand:
					if c != card:
						cards_available += 1
				if cards_available < 2:
					return "Need at least 2 other cards in hand to discard!"
		
		"base1-74": # Item Finder
			var cards_available = 0
			for c in hand:
				if c != card:
					cards_available += 1
			if cards_available < 2:
				return "Need at least 2 other cards in hand to discard!"
			var trainers_in_discard = []
			for c in discard:
				if is_trainer_card(c):
					trainers_in_discard.append(c)
			if trainers_in_discard.size() == 0:
				return "No Trainer cards in the discard pile!"
		
		"base1-81": # Energy Retrieval
			var basic_energies_in_discard = []
			for c in discard:
				if is_basic_energy_card(c):
					basic_energies_in_discard.append(c)
			if basic_energies_in_discard.size() == 0:
				return "No Basic Energy in discard pile!"
			var cards_available_er = 0
			for c in hand:
				if c != card:
					cards_available_er += 1
			if cards_available_er < 1:
				return "Need at least 1 other card in hand to discard!"
		
		"base1-83": # Maintenance
			var cards_available_m = 0
			for c in hand:
				if c != card:
					cards_available_m += 1
			if cards_available_m < 2:
				return "Need at least 2 other cards in hand!"
		
		"base1-89": # Revive
			if bench.size() >= 5:
				return "Bench is full!"
			var basics_in_discard = []
			for c in discard:
				if is_basic_pokemon(c):
					basics_in_discard.append(c)
			if basics_in_discard.size() == 0:
				return "No Basic Pokemon in discard pile!"
		
		"base1-93": # Gust of Wind
			var opp_bench_gust = player_bench if is_opponent else opponent_bench
			if opp_bench_gust.size() == 0:
				return "Opponent has no bench Pokemon!"
		
		"base1-95": # Switch
			if bench.size() == 0:
				return "No bench Pokemon to switch with!"
		
		"base1-86": # Pokemon Flute
			var target_bench_flute = player_bench if is_opponent else opponent_bench
			if target_bench_flute.size() >= 5:
				return "Opponent's bench is full!"
			var target_discard_flute = player_discard_pile if is_opponent else opponent_discard_pile
			var has_basic = false
			for c in target_discard_flute:
				if is_basic_pokemon(c):
					has_basic = true
					break
			if not has_basic:
				return "No Basic Pokemon in opponent's discard pile!"
		
		"base1-82": # Full Heal
			if active == null:
				return "No active Pokemon!"
			if active.special_condition == "" and not active.is_poisoned and not active.is_burned:
				return "Active Pokemon has no conditions to heal!"
		
		"base1-77": # Pokemon Trader
			var pokemon_in_hand = []
			for c in hand:
				if c != card and c.metadata.get("supertype", "").to_lower() == "pokémon":
					pokemon_in_hand.append(c)
			if pokemon_in_hand.size() == 0:
				return "No Pokemon in hand to trade!"
			var pokemon_in_deck = []
			for c in deck:
				if c.metadata.get("supertype", "").to_lower() == "pokémon":
					pokemon_in_deck.append(c)
			if pokemon_in_deck.size() == 0:
				return "No Pokemon in deck to trade for!"
	
	return ""

# Main entry point for playing a trainer card (handles animation, routing, and discard)
func play_trainer_card(card: card_object, is_opponent: bool) -> void:
	var hand = opponent_hand if is_opponent else player_hand
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	var who = "Opponent" if is_opponent else "You"
	var card_name = card.metadata.get("name", "Unknown")
	
	# Remove from hand first
	hand.erase(card)
	refresh_hand_display(is_opponent)
	
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_trainer_sound)
	
	# Step 1: Show trainer card animation
	await show_trainer_card_played_animation(card, is_opponent)
	
	# Step 2: Route to the correct handler based on card type
	if is_bench_token_trainer(card):
		await resolve_bench_token_trainer(card, is_opponent)
	elif is_attached_trainer(card):
		await resolve_attached_trainer(card, is_opponent)
	elif is_stadium_trainer(card):
		# Future-proofing: route to stadium handler
		print("Stadium cards not yet implemented")
		card.current_location = "discard"
		discard.append(card)
	else:
		# Standard trainer: send to discard and update display BEFORE resolving effect
		card.current_location = "discard"
		discard.append(card)
		update_discard_pile_display(is_opponent)
		await resolve_standard_trainer(card, is_opponent)
	
	update_discard_pile_display(is_opponent)
	refresh_hand_display(is_opponent)
	display_pokemon(is_opponent)
	display_pokemon(not is_opponent)

# Displays the trainer card animation overlay
func show_trainer_card_played_animation(card: card_object, is_opponent: bool) -> void:
	var who = "Opponent" if is_opponent else "You"
	var card_name = card.metadata.get("name", "Unknown")
	
	# Hide hand, decks, discards while trainer card is shown
	player_hand_container.visible = false
	player_deck_icon.visible = false
	opponent_deck_icon.visible = false
	player_discard_icon.visible = false
	opponent_discard_icon.visible = false
	
	# Show the overlay
	trainer_block_container.visible = true
	
	# Display the card in the container
	var card_display = TextureRect.new()
	card_display.set_script(card_display_script)
	played_trainer_container.add_child(card_display)
	card_display.load_card_image(card.uid, card_scales[1], card)
	
	# Show message
	await show_message(who + " played " + card_name + "!")
	
	# Clean up overlay and restore hidden elements
	trainer_block_container.visible = false
	for child in played_trainer_container.get_children():
		child.queue_free()
	player_hand_container.visible = true
	player_deck_icon.visible = true
	opponent_deck_icon.visible = true
	player_discard_icon.visible = true
	opponent_discard_icon.visible = true
	
	# Animate card to appropriate destination
	var hand_container_node = opponent_hand_container if is_opponent else player_hand_container
	var card_texture = get_card_texture(card)
	
	if is_bench_token_trainer(card):
		var bench_container_node = opponent_bench_container if is_opponent else player_bench_container
		await animate_card_a_to_b(hand_container_node, bench_container_node, 0.3, card_texture, card_scales[10])
	elif is_attached_trainer(card):
		# Don't animate here - attached trainers animate to their target in resolve_attached_trainer
		pass
	else:
		# Standard trainers animate to the discard pile
		var discard_node = opponent_discard_icon if is_opponent else player_discard_icon
		await animate_card_a_to_b(hand_container_node, discard_node, 0.3, card_texture, card_scales[10])

############################################### Section D: STANDARD TRAINER CARD EFFECTS ############################################################

# Routes a standard trainer card to its specific effect function
func resolve_standard_trainer(card: card_object, is_opponent: bool) -> void:
	var card_id = card.uid.to_lower()
	var card_name = card.metadata.get("name", "").to_lower()
	
	match card_id:
		"base1-91": await effect_bill(is_opponent)
		"base1-88": await effect_professor_oak(card, is_opponent)
		"base1-71": await effect_computer_search(card, is_opponent)
		"base1-72": await effect_devolution_spray(is_opponent)
		"base1-73": await effect_impostor_professor_oak(is_opponent)
		"base1-74": await effect_item_finder(card, is_opponent)
		"base1-75": await effect_lass(is_opponent)
		"base1-76": await effect_pokemon_breeder(is_opponent)
		"base1-77": await effect_pokemon_trader(card, is_opponent)
		"base1-78": await effect_scoop_up(is_opponent)
		"base1-79": await effect_super_energy_removal(is_opponent)
		"base1-81": await effect_energy_retrieval(card, is_opponent)
		"base1-82": await effect_full_heal(is_opponent)
		"base1-83": await effect_maintenance(card, is_opponent)
		"base1-85": await effect_pokemon_center(is_opponent)
		"base1-86": await effect_pokemon_flute(is_opponent)
		"base1-87": await effect_pokedex(is_opponent)
		"base1-89": await effect_revive(is_opponent)
		"base1-90": await effect_super_potion(is_opponent)
		"base1-92": await effect_energy_removal(is_opponent)
		"base1-93": await effect_gust_of_wind(is_opponent)
		"base1-94": await effect_potion(is_opponent)
		"base1-95": await effect_switch(is_opponent)
		_:
			print("Unknown trainer card: ", card_id, " (", card_name, ")")

# Resolves bench token trainer placement (Clefairy Doll, Mysterious Fossil)
func resolve_bench_token_trainer(card: card_object, is_opponent: bool) -> void:
	var bench = opponent_bench if is_opponent else player_bench
	if bench.size() >= 5:
		await show_message("Bench is full! Cannot place " + card.metadata.get("name", "") + "!")
		var discard = opponent_discard_pile if is_opponent else player_discard_pile
		card.current_location = "discard"
		discard.append(card)
		return
	
	# Place on bench with proper flags
	card.current_location = "bench"
	card.placed_on_field_this_turn = true
	card.no_prize_on_ko = true
	card.is_bench_token = true
	# Read HP from card metadata, fallback to 10
	var hp_str = card.metadata.get("hp", "10")
	card.current_hp = int(hp_str) if hp_str != "" else 10
	bench.append(card)
	
	display_pokemon(is_opponent)
	var name = card.metadata.get("name", "")
	await show_message(name + " was placed on the bench!")
	print("BENCH TOKEN: ", name, " placed on bench with ", card.current_hp, " HP")

# Resolves attached trainer card placement (PlusPower, Defender)
func resolve_attached_trainer(card: card_object, is_opponent: bool) -> void:
	var card_name = card.metadata.get("name", "").to_lower()
	
	if card_name == "pluspower":
		# Attach to active pokemon
		var active = opponent_active_pokemon if is_opponent else player_active_pokemon
		if active == null:
			await show_message("No active Pokemon to attach PlusPower to!")
			var discard = opponent_discard_pile if is_opponent else player_discard_pile
			card.current_location = "discard"
			discard.append(card)
			return
		active.attached_cards.append(card)
		active.pluspower_count += 1
		# Animate PlusPower to attached cards container
		var hand_node = opponent_hand_container if is_opponent else player_hand_container
		var attached_node = opponent_attached_cards_container if is_opponent else player_attached_cards_container
		var card_texture = get_card_texture(card)
		await animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, card_scales[10])
		display_attached_trainer_cards(is_opponent)
		await show_message("PlusPower attached to " + active.metadata.get("name", "").to_upper() + "!")
		print("PLUSPOWER: Attached to ", active.metadata.get("name", ""), " (total: ", active.pluspower_count, ")")
	
	elif card_name == "defender":
		if is_opponent:
			# CPU always attaches to its own active
			var active = opponent_active_pokemon
			if active == null:
				return
			active.attached_cards.append(card)
			active.defender_turns_remaining = 0
			# Animate to active
			var hand_node = opponent_hand_container
			var attached_node = opponent_attached_cards_container
			var card_texture = get_card_texture(card)
			await animate_card_a_to_b(hand_node, attached_node, 0.3, card_texture, card_scales[10])
			display_attached_trainer_cards(true)
			await show_message("Defender attached to " + active.metadata.get("name", "") + "! (-20 damage)")
		else:
			# Player chooses target
			var targets = build_field_pokemon_array(false)
			if targets.size() == 0:
				return
			
			trainer_pokemon_selection_active = true
			show_enlarged_array_selection_mode(targets)
			header_label.text = "ATTACH DEFENDER"
			hint_label.text = "Choose a Pokemon to attach Defender to"
			action_button.text = "ATTACH"
			action_button.disabled = true
			action_button.theme = theme_disabled
			cancel_button.visible = false
			await trainer_target_selected
			var target = selected_card_for_action
			trainer_pokemon_selection_active = false
			hide_selection_mode_display_main()
			
			if target != null:
				target.attached_cards.append(card)
				target.defender_turns_remaining = 0
				# Animate to the target pokemon's location
				var hand_node = player_hand_container
				var target_node = player_active_container if target == player_active_pokemon else player_bench_container
				var card_texture = get_card_texture(card)
				await animate_card_a_to_b(hand_node, target_node, 0.3, card_texture, card_scales[10])
				display_attached_trainer_cards(false)
				await show_message("Defender attached to " + target.metadata.get("name", "") + "!")

# --- INDIVIDUAL TRAINER EFFECTS ---

# base1-91 — Bill: Draw 2 cards
func effect_bill(is_opponent: bool) -> void:
	for i in range(2):
		await draw_card_from_deck(is_opponent)
		refresh_hand_display(is_opponent)
	update_deck_icon(is_opponent)

# base1-88 — Professor Oak: Discard hand, draw 7
func effect_professor_oak(played_card: card_object, is_opponent: bool) -> void:
	var hand = opponent_hand if is_opponent else player_hand
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	var hand_container_node = opponent_hand_container if is_opponent else player_hand_container
	var discard_node = opponent_discard_icon if is_opponent else player_discard_icon
	
	# Animate each hand card going to discard
	var hand_copy = hand.duplicate()
	for card in hand_copy:
		card.current_location = "discard"
		discard.append(card)
		var card_texture = get_card_texture(card)
		animate_card_a_to_b(hand_container_node, discard_node, 0.15, card_texture, card_scales[12])
		await get_tree().create_timer(0.1).timeout
	hand.clear()
	refresh_hand_display(is_opponent)
	update_discard_pile_display(is_opponent)
	
	await get_tree().create_timer(0.3).timeout
	
	# Draw 7 new cards with animation per card
	for i in range(7):
		await draw_card_from_deck(is_opponent)
		refresh_hand_display(is_opponent)
	update_deck_icon(is_opponent)

# base1-71 — Computer Search: Discard 2, search deck for any 1 card
func effect_computer_search(played_card: card_object, is_opponent: bool) -> void:
	var hand = opponent_hand if is_opponent else player_hand
	var deck = opponent_deck if is_opponent else player_deck
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	
	if is_opponent:
		# CPU: use discard priority and search priority
		var to_discard = cpu_get_discard_priority(hand, 2, played_card)
		for card in to_discard:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		refresh_hand_display(true)
		
		# CPU search logic
		var search_card = cpu_search_deck_for_best_card(deck)
		if search_card != null:
			deck.erase(search_card)
			search_card.current_location = "hand"
			hand.append(search_card)
			await show_message("Opponent searched their deck for a card!")
		deck.shuffle()
		refresh_hand_display(true)
		update_deck_icon(true)
	else:
		# Player: select 2 cards to discard
		if hand.size() < 2:
			await show_message("Not enough cards in hand to discard!")
			return
		
		await player_select_cards_to_discard(hand, 2, "COMPUTER SEARCH", "Select 2 cards to discard")
		for card in trainer_discard_selected:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		trainer_discard_selected.clear()
		refresh_hand_display(false)
		update_discard_pile_display(false)
		
		# Player searches deck
		if deck.size() > 0:
			trainer_deck_search_active = true
			show_enlarged_array_selection_mode(deck)
			header_label.text = "SEARCH YOUR DECK"
			hint_label.text = "Select any card to add to your hand"
			action_button.text = "TAKE CARD"
			action_button.disabled = true
			action_button.theme = theme_disabled
			cancel_button.visible = false
			await trainer_target_selected
			var chosen = selected_card_for_action
			trainer_deck_search_active = false
			hide_selection_mode_display_main()
			
			if chosen != null:
				deck.erase(chosen)
				chosen.current_location = "hand"
				hand.append(chosen)
				# Animate card from deck to hand
				var card_texture = get_card_texture(chosen)
				await animate_card_a_to_b(player_deck_icon, player_hand_container, 0.3, card_texture, card_scales[10])
		
		deck.shuffle()
		refresh_hand_display(false)
		update_deck_icon(false)

# base1-72 — Devolution Spray: Devolve a pokemon
func effect_devolution_spray(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	
	# Find all evolved pokemon on the field
	var evolved_pokemon = []
	if active != null and active.attached_pre_evolutions.size() > 0:
		evolved_pokemon.append(active)
	for bp in bench:
		if bp.attached_pre_evolutions.size() > 0:
			evolved_pokemon.append(bp)
	
	if evolved_pokemon.size() == 0:
		await show_message("No evolved Pokemon to devolve!")
		return
	
	if is_opponent:
		return
	else:
		# Step 1: Player selects which pokemon to devolve
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(evolved_pokemon)
		header_label.text = "DEVOLUTION SPRAY"
		hint_label.text = "Choose an evolved Pokemon to devolve"
		action_button.text = "SELECT"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var target = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if target == null:
			return
		
		# Step 2: If multiple pre-evolutions exist (Stage 2), let player choose which to devolve to
		var devolve_to: card_object = null
		if target.attached_pre_evolutions.size() == 1:
			# Only one option (Stage 1 → Basic)
			devolve_to = target.attached_pre_evolutions[0]
		else:
			# Multiple options (Stage 2 → show Basic and Stage 1)
			trainer_pokemon_selection_active = true
			show_enlarged_array_selection_mode(target.attached_pre_evolutions)
			header_label.text = "DEVOLVE TO WHICH STAGE?"
			hint_label.text = "Select which card to devolve " + target.metadata.get("name", "") + " into"
			action_button.text = "DEVOLVE"
			action_button.disabled = true
			action_button.theme = theme_disabled
			cancel_button.visible = false
			await trainer_target_selected
			devolve_to = selected_card_for_action
			trainer_pokemon_selection_active = false
			hide_selection_mode_display_main()
		
		if devolve_to == null:
			return
		
		# Save the field position BEFORE discarding
		var field_location = target.current_location
		
		# Find the index of the chosen card in the pre-evolution chain
		var devolve_index = target.attached_pre_evolutions.find(devolve_to)
		
		# Discard the current top card (the evolved form) to the discard pile
		var evo_card = target
		evo_card.current_location = "discard"
		discard.append(evo_card)
		
		# Discard all pre-evolutions ABOVE the chosen devolve target
		# Pre-evolutions are stored [Basic, Stage1] - discard everything after devolve_index
		var cards_to_discard_from_chain = []
		for i in range(devolve_index + 1, target.attached_pre_evolutions.size()):
			cards_to_discard_from_chain.append(target.attached_pre_evolutions[i])
		for card in cards_to_discard_from_chain:
			card.current_location = "discard"
			discard.append(card)
			target.attached_pre_evolutions.erase(card)
		
		# Remove the devolve_to card from the chain (it becomes the new pokemon)
		target.attached_pre_evolutions.erase(devolve_to)
		
		# Transfer attachments from the old top card to the new form
		devolve_to.attached_energies = evo_card.attached_energies.duplicate()
		evo_card.attached_energies.clear()
		# Keep only pre-evolutions below the devolve target
		devolve_to.attached_pre_evolutions = target.attached_pre_evolutions.duplicate()
		target.attached_pre_evolutions.clear()
		devolve_to.attached_cards = evo_card.attached_cards.duplicate()
		evo_card.attached_cards.clear()
		
		# Transfer damage, clamping so it has at least 10 HP
		var max_hp_old = int(evo_card.metadata.get("hp", "0"))
		var damage_taken = max_hp_old - evo_card.current_hp
		var new_max_hp = int(devolve_to.metadata.get("hp", "0"))
		devolve_to.current_hp = max(10, new_max_hp - damage_taken)
		devolve_to.current_location = field_location
		
		# Clear statuses
		clear_all_statuses(devolve_to, is_opponent)
		
		# Replace in the appropriate slot
		if evo_card == (opponent_active_pokemon if is_opponent else player_active_pokemon):
			if is_opponent:
				opponent_active_pokemon = devolve_to
			else:
				player_active_pokemon = devolve_to
		else:
			var b = opponent_bench if is_opponent else player_bench
			var idx = b.find(evo_card)
			if idx != -1:
				b[idx] = devolve_to
		
		display_pokemon(is_opponent)
		display_active_pokemon_energies(is_opponent)
		update_discard_pile_display(is_opponent)
		await show_message(evo_card.metadata.get("name", "") + " devolved into " + devolve_to.metadata.get("name", "") + "!")

# base1-73 — Impostor Professor Oak: Opponent shuffles hand into deck, draws 7
func effect_impostor_professor_oak(is_opponent: bool) -> void:
	# Target is the OTHER player
	var target_hand = player_hand if is_opponent else opponent_hand
	var target_deck = player_deck if is_opponent else opponent_deck
	var target_is_opponent = not is_opponent
	var target_hand_container = player_hand_container if is_opponent else opponent_hand_container
	var target_deck_node = player_deck_icon if is_opponent else opponent_deck_icon
	
	# Animate each card from hand to deck
	var hand_copy = target_hand.duplicate()
	for card in hand_copy:
		card.current_location = "deck"
		target_deck.append(card)
		var card_texture = get_card_texture(card)
		animate_card_a_to_b(target_hand_container, target_deck_node, 0.15, card_texture, card_scales[12])
		await get_tree().create_timer(0.1).timeout
	target_hand.clear()
	target_deck.shuffle()
	refresh_hand_display(target_is_opponent)
	update_deck_icon(target_is_opponent)
	
	await get_tree().create_timer(0.3).timeout
	
	# Draw 7 cards with per-card animation
	for i in range(7):
		await draw_card_from_deck(target_is_opponent)
		refresh_hand_display(target_is_opponent)
	update_deck_icon(target_is_opponent)
	await show_message("Hand was shuffled into deck and drew 7 cards!")

# base1-74 — Item Finder: Discard 2, retrieve 1 Trainer from discard
func effect_item_finder(played_card: card_object, is_opponent: bool) -> void:
	var hand = opponent_hand if is_opponent else player_hand
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	
	# Find trainer cards in discard pile (exclude the Item Finder just played)
	var trainers_in_discard = []
	for card in discard:
		if is_trainer_card(card) and card != played_card:
			trainers_in_discard.append(card)
	
	if trainers_in_discard.size() == 0:
		await show_message("No Trainer cards in the discard pile!")
		return
	
	if is_opponent:
		var to_discard = cpu_get_discard_priority(hand, 2, played_card)
		for card in to_discard:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		
		# CPU picks highest priority trainer from discard
		var best_trainer: card_object = null
		var best_score = -999.0
		for t in trainers_in_discard:
			var score = cpu_score_trainer_card(t)
			if score > best_score:
				best_score = score
				best_trainer = t
		if best_trainer != null:
			discard.erase(best_trainer)
			best_trainer.current_location = "hand"
			hand.append(best_trainer)
			await show_message("Opponent retrieved " + best_trainer.metadata.get("name", "") + " from discard pile!")
		refresh_hand_display(true)
	else:
		if hand.size() < 2:
			await show_message("Not enough cards in hand to discard!")
			return
		await player_select_cards_to_discard(hand, 2, "ITEM FINDER", "Select 2 cards to discard")
		for card in trainer_discard_selected:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		trainer_discard_selected.clear()
		refresh_hand_display(false)
		
		# Player picks from discard trainers
		trainer_deck_search_active = true
		show_enlarged_array_selection_mode(trainers_in_discard)
		header_label.text = "ITEM FINDER"
		hint_label.text = "Select a Trainer card from your discard pile"
		action_button.text = "RETRIEVE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var chosen = selected_card_for_action
		trainer_deck_search_active = false
		hide_selection_mode_display_main()
		
		if chosen != null:
			discard.erase(chosen)
			chosen.current_location = "hand"
			hand.append(chosen)
			# Animate trainer from discard to hand
			var trainer_texture = get_card_texture(chosen)
			await animate_card_a_to_b(player_discard_icon, player_hand_container, 0.3, trainer_texture, card_scales[10])
			await show_message("Retrieved " + chosen.metadata.get("name", "") + " from discard pile!")
		refresh_hand_display(false)

# base1-75 — Lass: Both players shuffle Trainer cards from hand into deck
func effect_lass(is_opponent: bool) -> void:
	# Identify trainer cards in both hands
	var p_trainers = []
	for card in player_hand:
		if is_trainer_card(card):
			p_trainers.append(card)
	var o_trainers = []
	for card in opponent_hand:
		if is_trainer_card(card):
			o_trainers.append(card)
	
	# Show opponent's hand face-up to the player
	if opponent_hand.size() > 0:
		# Use trainer_pokemon_selection mode so the cancel/Done button triggers trainer_target_selected
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(opponent_hand)
		# Force face-up display by redrawing without hiding
		var display_container = large_selection_container if opponent_hand.size() > 7 else small_selection_container
		var display_size = card_scales[5] if opponent_hand.size() > 7 else card_scales[opponent_hand.size()]
		display_hand_cards_array(opponent_hand, display_container, display_size, false)
		header_label.text = "OPPONENT'S HAND REVEALED"
		hint_label.text = str(o_trainers.size()) + " Trainer card(s) will be shuffled into deck"
		action_button.visible = false
		cancel_button.visible = true
		cancel_button.text = "DONE"
		cancel_button.theme = theme_green
		cancel_button.offset_left = -219.0
		cancel_button.offset_right = 219.0
		await trainer_target_selected
		trainer_pokemon_selection_active = false
		cancel_button.text = "Cancel"
		cancel_button.theme = theme_red
		hide_selection_mode_display_main()
	
	# Animate player trainers going to deck
	for card in p_trainers:
		player_hand.erase(card)
		card.current_location = "deck"
		player_deck.append(card)
		var card_texture = get_card_texture(card)
		animate_card_a_to_b(player_hand_container, player_deck_icon, 0.15, card_texture, card_scales[12])
		await get_tree().create_timer(0.1).timeout
		update_deck_icon(false)
	
	# Animate opponent trainers going to deck
	for card in o_trainers:
		opponent_hand.erase(card)
		card.current_location = "deck"
		opponent_deck.append(card)
		var card_texture = get_card_texture(card)
		animate_card_a_to_b(opponent_hand_container, opponent_deck_icon, 0.15, card_texture, card_scales[12])
		await get_tree().create_timer(0.1).timeout
		update_deck_icon(true)
	
	player_deck.shuffle()
	opponent_deck.shuffle()
	refresh_hand_display(false)
	refresh_hand_display(true)
	update_deck_icon(false)
	update_deck_icon(true)
	await show_message("All Trainer cards shuffled back into decks!")

# base1-76 — Pokemon Breeder: Place Stage 2 directly on matching Basic
func effect_pokemon_breeder(is_opponent: bool) -> void:
	var hand = opponent_hand if is_opponent else player_hand
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	
	# Find Stage 2 cards in hand
	var stage2_cards = []
	for card in hand:
		var subtypes = card.metadata.get("subtypes", [])
		if "Stage 2" in subtypes:
			stage2_cards.append(card)
	
	if stage2_cards.size() == 0:
		await show_message("No Stage 2 Pokemon in hand!")
		return
	
	if is_opponent:
		# CPU: find best Stage 2 + Basic match
		for s2 in stage2_cards:
			var evolves_from_s1 = s2.metadata.get("evolvesFrom", "")
			# Find the Stage 1 this evolves from, then find that Stage 1's basic
			# For Breeder, we need the Basic that the Stage 2 ultimately comes from
			# Check all pokemon in play to see if any Basic matches
			var all_in_play = []
			if active != null:
				all_in_play.append(active)
			all_in_play.append_array(bench)
			
			for pokemon in all_in_play:
				if pokemon.placed_on_field_this_turn:
					continue
				if not is_basic_pokemon(pokemon):
					continue
				# Check if this Basic eventually leads to the Stage 2
				if _basic_matches_stage2(pokemon, s2):
					evolution_card_awaiting_target = s2
					selected_card_for_action = pokemon
					perform_evolution(true)
					await show_message("Opponent used Pokemon Breeder to evolve " + pokemon.metadata.get("name", "") + " into " + s2.metadata.get("name", "") + "!")
					display_pokemon(true)
					display_active_pokemon_energies(true)
					refresh_hand_display(true)
					evolution_card_awaiting_target = null
					selected_card_for_action = null
					return
	else:
		# Player: select Stage 2 card, then select matching Basic
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(stage2_cards)
		header_label.text = "POKEMON BREEDER"
		hint_label.text = "Select a Stage 2 Pokemon to play"
		action_button.text = "SELECT"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var s2_card = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if s2_card == null:
			return
		
		# Find valid basic targets - bench first, active last (for spacer display)
		var targets = []
		for bp in bench:
			if not bp.placed_on_field_this_turn and is_basic_pokemon(bp) and _basic_matches_stage2(bp, s2_card):
				targets.append(bp)
		if active != null and not active.placed_on_field_this_turn and is_basic_pokemon(active) and _basic_matches_stage2(active, s2_card):
			targets.append(active)
		
		if targets.size() == 0:
			await show_message("No valid Basic Pokemon to evolve!")
			# Put the Stage 2 back (it wasn't removed from hand yet by this function)
			return
		
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(targets)
		header_label.text = "POKEMON BREEDER"
		hint_label.text = "Select a Basic Pokemon to evolve into " + s2_card.metadata.get("name", "")
		action_button.text = "EVOLVE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var target = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if target != null:
			evolution_card_awaiting_target = s2_card
			selected_card_for_action = target
			perform_evolution(false)
			display_pokemon(false)
			display_active_pokemon_energies(false)
			refresh_hand_display(false)
			await play_evolution_effect(s2_card)
			evolution_card_awaiting_target = null
			selected_card_for_action = null

# Helper: checks if a Basic pokemon is the correct base for a Stage 2 (via intermediate Stage 1)
func _basic_matches_stage2(basic: card_object, stage2: card_object) -> bool:
	var s2_evolves_from = stage2.metadata.get("evolvesFrom", "")
	if s2_evolves_from == "":
		return false
	# The Stage 2 evolves from a Stage 1 name. Check if any Stage 1 with that name evolves from this Basic.
	# We check the JSON metadata for Stage 1 cards
	var basic_name = basic.metadata.get("name", "")
	# Simple check: look through all card sets for a Stage 1 named s2_evolves_from that evolves from basic_name
	# For efficiency, check the card's set
	var set_prefix = stage2.uid.split("-")[0]
	var metadata_path = "res://Card_Set_Data/" + set_prefix + ".json"
	var file = FileAccess.open(metadata_path, FileAccess.READ)
	if file == null:
		return false
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return false
	file.close()
	for card_data in json.data:
		if card_data.get("name", "") == s2_evolves_from:
			if card_data.get("evolvesFrom", "") == basic_name:
				return true
	return false

# base1-77 — Pokemon Trader: Trade 1 Pokemon from hand for 1 from deck
func effect_pokemon_trader(played_card: card_object, is_opponent: bool) -> void:
	var hand = opponent_hand if is_opponent else player_hand
	var deck = opponent_deck if is_opponent else player_deck
	
	# Find Pokemon in hand
	var pokemon_in_hand = []
	for card in hand:
		if card.metadata.get("supertype", "").to_lower() == "pokémon":
			pokemon_in_hand.append(card)
	
	var pokemon_in_deck = []
	for card in deck:
		if card.metadata.get("supertype", "").to_lower() == "pokémon":
			pokemon_in_deck.append(card)
	
	if pokemon_in_hand.size() == 0 or pokemon_in_deck.size() == 0:
		await show_message("Cannot trade - need Pokemon in both hand and deck!")
		return
	
	if is_opponent:
		# CPU: trade a duplicate or unneeded pokemon for a needed one
		var trade_away = cpu_get_discard_priority(pokemon_in_hand, 1, played_card)
		if trade_away.size() == 0:
			return
		var card_to_trade = trade_away[0]
		var search_card = cpu_search_deck_for_best_pokemon(pokemon_in_deck)
		if search_card != null:
			hand.erase(card_to_trade)
			card_to_trade.current_location = "deck"
			deck.append(card_to_trade)
			deck.erase(search_card)
			search_card.current_location = "hand"
			hand.append(search_card)
			deck.shuffle()
			await show_message("Opponent traded " + card_to_trade.metadata.get("name", "") + " for " + search_card.metadata.get("name", "") + "!")
			refresh_hand_display(true)
	else:
		# Player picks card to trade from hand
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(pokemon_in_hand)
		header_label.text = "POKEMON TRADER"
		hint_label.text = "Select a Pokemon from your hand to trade"
		action_button.text = "TRADE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var card_to_trade = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if card_to_trade == null:
			return
		
		# Player picks card from deck
		trainer_deck_search_active = true
		show_enlarged_array_selection_mode(pokemon_in_deck)
		header_label.text = "POKEMON TRADER"
		hint_label.text = "Select a Pokemon from your deck"
		action_button.text = "TAKE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var search_card = selected_card_for_action
		trainer_deck_search_active = false
		hide_selection_mode_display_main()
		
		if search_card != null:
			hand.erase(card_to_trade)
			card_to_trade.current_location = "deck"
			deck.append(card_to_trade)
			deck.erase(search_card)
			search_card.current_location = "hand"
			hand.append(search_card)
			deck.shuffle()
			# Animate traded card to deck and searched card to hand
			var trade_texture = get_card_texture(card_to_trade)
			animate_card_a_to_b(player_hand_container, player_deck_icon, 0.2, trade_texture, card_scales[10])
			await get_tree().create_timer(0.2).timeout
			var search_texture = get_card_texture(search_card)
			await animate_card_a_to_b(player_deck_icon, player_hand_container, 0.3, search_texture, card_scales[10])
			refresh_hand_display(false)
			update_deck_icon(false)

# base1-78 — Scoop Up: Return Basic card to hand, discard attachments
func effect_scoop_up(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var hand = opponent_hand if is_opponent else player_hand
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	
	# Get all pokemon in play (bench first, active last for spacer display)
	var all_in_play = build_field_pokemon_array(is_opponent)
	
	if all_in_play.size() == 0:
		return
	
	var target: card_object = null
	
	if is_opponent:
		# CPU: pick the pokemon at lowest HP that is guaranteed KO'd
		for pokemon in all_in_play:
			if pokemon.current_hp <= int(pokemon.metadata.get("hp", "0")) / 2:
				target = pokemon
				break
		if target == null:
			return
	else:
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(all_in_play)
		header_label.text = "SCOOP UP"
		hint_label.text = "Select a Pokemon to return its Basic card to your hand"
		action_button.text = "SCOOP UP"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		target = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
	
	if target == null:
		return
	
	# Find the original Basic card (at the bottom of the pre-evolution chain)
	var basic_card = target
	if target.attached_pre_evolutions.size() > 0:
		basic_card = target.attached_pre_evolutions[0]
		target.attached_pre_evolutions.erase(basic_card)
	
	# Discard all attachments (energies, evolutions, attached cards)
	for energy in target.attached_energies:
		energy.current_location = "discard"
		discard.append(energy)
	target.attached_energies.clear()
	for evo in target.attached_pre_evolutions:
		evo.current_location = "discard"
		discard.append(evo)
	target.attached_pre_evolutions.clear()
	for att in target.attached_cards:
		att.current_location = "discard"
		discard.append(att)
	target.attached_cards.clear()
	
	# If the target itself is NOT the basic (it's an evolution), discard it too
	if target != basic_card:
		target.current_location = "discard"
		discard.append(target)
	
	# Remove from play
	if target == (opponent_active_pokemon if is_opponent else player_active_pokemon):
		if is_opponent:
			opponent_active_pokemon = null
		else:
			player_active_pokemon = null
	elif target in bench:
		bench.erase(target)
	
	# Return basic card to hand with fresh state
	basic_card.current_location = "hand"
	basic_card.current_hp = int(basic_card.metadata.get("hp", "0"))
	basic_card.pluspower_count = 0
	basic_card.defender_turns_remaining = -1
	clear_all_statuses(basic_card, is_opponent)
	hand.append(basic_card)
	
	update_discard_pile_display(is_opponent)
	refresh_hand_display(is_opponent)
	display_pokemon(is_opponent)
	display_active_pokemon_energies(is_opponent)
	
	await show_message(basic_card.metadata.get("name", "") + " was scooped up and returned to hand!")
	
	# If the active was scooped, need bench replacement (no prize)
	var current_active = opponent_active_pokemon if is_opponent else player_active_pokemon
	if current_active == null:
		if bench.size() == 0:
			await show_message("No Pokemon remaining!")
			game_end_logic(not is_opponent)
			return
		if is_opponent:
			var cpu_eval = build_cpu_evaluation()
			var replacement = pick_best_bench_replacement(bench, player_active_pokemon, cpu_eval)
			if replacement == null:
				replacement = bench[0]
			bench.erase(replacement)
			replacement.current_location = "active"
			opponent_active_pokemon = replacement
			display_pokemon(true)
			display_active_pokemon_energies(true)
			await show_message("Opponent sent " + replacement.metadata.get("name", "") + " to the active spot!")
		else:
			knockout_bench_selection_active = true
			show_enlarged_array_selection_mode(player_bench)
			cancel_button.visible = false
			header_label.text = "CHOOSE NEW ACTIVE POKEMON"
			hint_label.text = "Your active was scooped up - select a replacement"
			action_button.text = "SET ACTIVE"
			action_button.disabled = true
			action_button.theme = theme_disabled
			await knockout_replacement_chosen
			display_active_pokemon_energies(false)

# base1-79 — Super Energy Removal: Discard 1 own energy, remove up to 2 from opponent
func effect_super_energy_removal(is_opponent: bool) -> void:
	var own_discard = opponent_discard_pile if is_opponent else player_discard_pile
	var target_discard = player_discard_pile if is_opponent else opponent_discard_pile
	
	# Find own pokemon with energy (using combined array with active last)
	var own_all = build_field_pokemon_array(is_opponent)
	var own_with_energy = own_all.filter(func(p): return p.attached_energies.size() > 0)
	
	# Find opponent pokemon with energy (using combined array with active last)
	var target_all = build_field_pokemon_array(not is_opponent)
	var target_with_energy = target_all.filter(func(p): return p.attached_energies.size() > 0)
	
	if own_with_energy.size() == 0:
		await show_message("No energy to discard from your own Pokemon!")
		return
	if target_with_energy.size() == 0:
		await show_message("Opponent has no energy to remove!")
		return
	
	if is_opponent:
		# CPU logic
		var source = own_with_energy[0]
		for p in own_with_energy:
			if p.attached_energies.size() > source.attached_energies.size():
				source = p
		var energy = source.attached_energies.pop_back()
		energy.current_location = "discard"
		own_discard.append(energy)
		
		var target_active = player_active_pokemon
		var target = target_active if target_active != null and target_active.attached_energies.size() > 0 else (target_with_energy[0] if target_with_energy.size() > 0 else null)
		if target != null:
			var removed = 0
			while removed < 2 and target.attached_energies.size() > 0:
				var e = target.attached_energies.pop_back()
				e.current_location = "discard"
				target_discard.append(e)
				removed += 1
			await show_message("Opponent removed " + str(removed) + " energy from " + target.metadata.get("name", "") + "!")
		display_active_pokemon_energies(true)
		display_active_pokemon_energies(false)
		update_discard_pile_display(false)
		update_discard_pile_display(true)
	else:
		# Step 1: Player selects which of their own pokemon to discard energy from
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(own_with_energy)
		header_label.text = "SUPER ENERGY REMOVAL - YOUR POKEMON"
		hint_label.text = "Select your Pokemon to discard 1 energy from"
		action_button.text = "SELECT"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var source = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if source == null or source.attached_energies.size() == 0:
			return
		
		# Step 2: Player selects which energy to discard from their own pokemon
		defender_energy_discard_active = true
		show_enlarged_array_selection_mode(source.attached_energies)
		cancel_button.visible = false
		header_label.text = "DISCARD YOUR ENERGY"
		hint_label.text = "Select 1 energy to discard"
		action_button.text = "DISCARD"
		action_button.disabled = true
		action_button.theme = theme_disabled
		await defender_energy_chosen
		var own_energy = selected_card_for_action
		defender_energy_discard_active = false
		hide_selection_mode_display_main()
		
		if own_energy == null:
			return
		source.attached_energies.erase(own_energy)
		own_energy.current_location = "discard"
		own_discard.append(own_energy)
		display_active_pokemon_energies(false)
		update_discard_pile_display(false)
		
		# Step 3: Player selects opponent pokemon to remove energy from
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(target_with_energy)
		header_label.text = "SUPER ENERGY REMOVAL - OPPONENT"
		hint_label.text = "Select opponent's Pokemon to remove up to 2 energy"
		action_button.text = "SELECT"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var target = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if target == null:
			return
		
		# Step 4: Remove up to 2 energy using multi-select
		var max_remove = min(2, target.attached_energies.size())
		var removed = 0
		if max_remove <= 2 and target.attached_energies.size() <= 2:
			# 2 or fewer - just take them all
			while target.attached_energies.size() > 0 and removed < 2:
				var e = target.attached_energies.pop_back()
				e.current_location = "discard"
				target_discard.append(e)
				var from_node = find_card_ui_for_object(target)
				if from_node == null:
					from_node = opponent_active_container if target == opponent_active_pokemon else opponent_bench_container
				var e_tex = get_card_texture(e)
				await animate_card_a_to_b(from_node, opponent_discard_icon, 0.2, e_tex, card_scales[10])
				removed += 1
		else:
			# Player selects which 2 energies using multi-select mode
			trainer_discard_selected.clear()
			trainer_discard_cards_needed = 2
			trainer_discard_selection_active = true
			
			show_enlarged_array_selection_mode(target.attached_energies)
			cancel_button.visible = false
			header_label.text = "REMOVE ENERGY (SELECT 2)"
			hint_label.text = "Select 2 energies to remove (0/2 selected)"
			action_button.text = "2 MORE"
			action_button.disabled = true
			action_button.theme = theme_disabled
			
			await trainer_discard_selection_done
			trainer_discard_selection_active = false
			hide_selection_mode_display_main()
			
			for e in trainer_discard_selected:
				target.attached_energies.erase(e)
				e.current_location = "discard"
				target_discard.append(e)
				var from_node = find_card_ui_for_object(target)
				if from_node == null:
					from_node = opponent_active_container if target == opponent_active_pokemon else opponent_bench_container
				var e_tex = get_card_texture(e)
				await animate_card_a_to_b(from_node, opponent_discard_icon, 0.2, e_tex, card_scales[10])
			removed = trainer_discard_selected.size()
			trainer_discard_selected.clear()
		
		display_active_pokemon_energies(true)
		update_discard_pile_display(true)
		if removed > 0:
			await show_message("Removed " + str(removed) + " energy from " + target.metadata.get("name", "") + "!")

# base1-81 — Energy Retrieval: Discard 1, get up to 2 Basic Energy from discard
func effect_energy_retrieval(played_card: card_object, is_opponent: bool) -> void:
	var hand = opponent_hand if is_opponent else player_hand
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	
	# Find basic energy in discard
	var basic_energies = []
	for card in discard:
		if is_basic_energy_card(card):
			basic_energies.append(card)
	
	if basic_energies.size() == 0:
		await show_message("No Basic Energy cards in discard pile!")
		return
	
	if is_opponent:
		var to_discard = cpu_get_discard_priority(hand, 1, played_card)
		if to_discard.size() == 0:
			return
		hand.erase(to_discard[0])
		to_discard[0].current_location = "discard"
		discard.append(to_discard[0])
		
		var retrieved = 0
		for energy in basic_energies.duplicate():
			if retrieved >= 2:
				break
			discard.erase(energy)
			energy.current_location = "hand"
			hand.append(energy)
			retrieved += 1
		await show_message("Opponent retrieved " + str(retrieved) + " Basic Energy from discard!")
		refresh_hand_display(true)
	else:
		if hand.size() < 1:
			await show_message("Not enough cards to discard!")
			return
		await player_select_cards_to_discard(hand, 1, "ENERGY RETRIEVAL", "Select 1 card to discard")
		for card in trainer_discard_selected:
			hand.erase(card)
			card.current_location = "discard"
			discard.append(card)
		trainer_discard_selected.clear()
		refresh_hand_display(false)
		
		# Player picks up to 2 basic energy from discard using multi-select
		# Recalculate basic energies after discard
		basic_energies.clear()
		for card in discard:
			if is_basic_energy_card(card):
				basic_energies.append(card)
		
		if basic_energies.size() > 0:
			var max_retrieve = min(2, basic_energies.size())
			trainer_discard_selected.clear()
			trainer_discard_cards_needed = max_retrieve
			trainer_discard_selection_active = true
			
			show_enlarged_array_selection_mode(basic_energies)
			header_label.text = "ENERGY RETRIEVAL"
			hint_label.text = "Select up to " + str(max_retrieve) + " Basic Energy to retrieve (0/" + str(max_retrieve) + " selected)"
			action_button.text = str(max_retrieve) + " MORE"
			action_button.disabled = true
			action_button.theme = theme_disabled
			cancel_button.visible = false
			
			await trainer_discard_selection_done
			trainer_discard_selection_active = false
			hide_selection_mode_display_main()
			
			for card in trainer_discard_selected:
				discard.erase(card)
				card.current_location = "hand"
				hand.append(card)
				# Animate each retrieved energy from discard to hand
				var discard_node = player_discard_icon
				var energy_texture = get_card_texture(card)
				await animate_card_a_to_b(discard_node, player_hand_container, 0.3, energy_texture, card_scales[10])
			trainer_discard_selected.clear()
		
		refresh_hand_display(false)
		update_discard_pile_display(false)

# base1-82 — Full Heal: Remove all status conditions from active
func effect_full_heal(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	if active == null:
		return
	var had_status = active.special_condition != "" or active.is_poisoned
	clear_all_statuses(active, is_opponent)
	if had_status:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
		await show_message(active.metadata.get("name", "") + " was fully healed of all conditions!")
	else:
		await show_message(active.metadata.get("name", "") + " had no conditions to heal.")

# base1-83 — Maintenance: Shuffle 2 cards back, draw 1
func effect_maintenance(played_card: card_object, is_opponent: bool) -> void:
	var hand = opponent_hand if is_opponent else player_hand
	var deck = opponent_deck if is_opponent else player_deck
	
	if hand.size() < 2:
		await show_message("Not enough cards in hand!")
		return
	
	if is_opponent:
		var to_shuffle = cpu_get_discard_priority(hand, 2, played_card)
		for card in to_shuffle:
			hand.erase(card)
			card.current_location = "deck"
			deck.append(card)
		deck.shuffle()
		await draw_card_from_deck(true)
		refresh_hand_display(true)
		update_deck_icon(true)
		await show_message("Opponent shuffled 2 cards into deck and drew 1!")
	else:
		await player_select_cards_to_discard(hand, 2, "MAINTENANCE", "Select 2 cards to shuffle into your deck")
		for card in trainer_discard_selected:
			hand.erase(card)
			card.current_location = "deck"
			deck.append(card)
		trainer_discard_selected.clear()
		deck.shuffle()
		await draw_card_from_deck(false)
		refresh_hand_display(false)
		update_deck_icon(false)

# base1-85 — Pokemon Center: Heal all damage, discard energy from healed pokemon
func effect_pokemon_center(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	var discard_node = opponent_discard_icon if is_opponent else player_discard_icon
	
	var all_pokemon = build_field_pokemon_array(is_opponent)
	
	var healed_any = false
	for pokemon in all_pokemon:
		var max_hp = int(pokemon.metadata.get("hp", "0"))
		var damage = max_hp - pokemon.current_hp
		if damage <= 0:
			continue
		
		healed_any = true
		pokemon.current_hp = max_hp
		
		# Show floating heal label at pokemon location
		var loc = get_pokemon_screen_location(pokemon)
		if not loc.is_empty():
			SoundManagerScript.play_sfx(SoundManagerScript.SFX_heal_sound)
			show_floating_label("+" + str(damage) + " HP", loc["position"] + Vector2(0, -20), true)
		
		# Animate energy cards going to discard
		for energy in pokemon.attached_energies:
			energy.current_location = "discard"
			discard.append(energy)
			var from_node = find_card_ui_for_object(pokemon)
			if from_node == null:
				from_node = (opponent_active_container if is_opponent else player_active_container) if pokemon == active else (opponent_bench_container if is_opponent else player_bench_container)
			var energy_texture = get_card_texture(energy)
			animate_card_a_to_b(from_node, discard_node, 0.15, energy_texture, card_scales[12])
		pokemon.attached_energies.clear()
		
		await get_tree().create_timer(0.3).timeout
	
	if not healed_any:
		await show_message("No Pokemon with damage to heal!")
	
	display_pokemon(is_opponent)
	display_active_pokemon_energies(is_opponent)
	display_hp_circles_above_align(active, is_opponent)
	update_discard_pile_display(is_opponent)

# base1-86 — Pokemon Flute: Put Basic from opponent's discard onto their bench
func effect_pokemon_flute(is_opponent: bool) -> void:
	var target_bench = player_bench if is_opponent else opponent_bench
	var target_discard = player_discard_pile if is_opponent else opponent_discard_pile
	var target_is_opponent = not is_opponent
	
	if target_bench.size() >= 5:
		await show_message("Opponent's bench is full!")
		return
	
	var basics_in_discard = []
	for card in target_discard:
		if is_basic_pokemon(card):
			basics_in_discard.append(card)
	
	if basics_in_discard.size() == 0:
		await show_message("No Basic Pokemon in opponent's discard pile!")
		return
	
	if is_opponent:
		# CPU never plays this (scored -100)
		return
	else:
		trainer_deck_search_active = true
		show_enlarged_array_selection_mode(basics_in_discard)
		header_label.text = "POKEMON FLUTE"
		hint_label.text = "Choose a Basic Pokemon to place on opponent's bench"
		action_button.text = "PLACE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var chosen = selected_card_for_action
		trainer_deck_search_active = false
		hide_selection_mode_display_main()
		
		if chosen != null:
			target_discard.erase(chosen)
			chosen.current_location = "bench"
			chosen.current_hp = int(chosen.metadata.get("hp", "0"))
			chosen.placed_on_field_this_turn = true
			target_bench.append(chosen)
			# Animate from discard to bench
			var discard_node = opponent_discard_icon if target_is_opponent else player_discard_icon
			var bench_node = opponent_bench_container if target_is_opponent else player_bench_container
			var card_texture = get_card_texture(chosen)
			await animate_card_a_to_b(discard_node, bench_node, 0.3, card_texture, card_scales[10])
			update_discard_pile_display(target_is_opponent)
			display_pokemon(target_is_opponent)
			await show_message(chosen.metadata.get("name", "") + " was placed on opponent's bench!")

# base1-87 — Pokedex: Look at top 5 cards and rearrange
func effect_pokedex(is_opponent: bool) -> void:
	var deck = opponent_deck if is_opponent else player_deck
	
	var count = min(5, deck.size())
	if count == 0:
		await show_message("Deck is empty!")
		return
	
	var top_cards = []
	for i in range(count):
		top_cards.append(deck[i])
	
	if is_opponent:
		# CPU reorder using priority
		top_cards.sort_custom(func(a, b): return _cpu_pokedex_priority(a) > _cpu_pokedex_priority(b))
		for i in range(count):
			deck[i] = top_cards[i]
		await show_message("Opponent rearranged the top " + str(count) + " cards of their deck!")
	else:
		# Player: show all cards at once, click in order to assign position numbers
		pokedex_cards = top_cards.duplicate()
		pokedex_reorder_result.clear()
		trainer_reorder_active = true
		
		show_enlarged_array_selection_mode(pokedex_cards)
		header_label.text = "POKEDEX - CLICK CARDS IN ORDER"
		hint_label.text = "Click cards in the order you want them (top of deck first)"
		action_button.text = "0/" + str(count) + " SELECTED"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		
		await trainer_reorder_done
		trainer_reorder_active = false
		hide_selection_mode_display_main()
		
		# Apply the new order
		for i in range(pokedex_reorder_result.size()):
			deck[i] = pokedex_reorder_result[i]
		pokedex_cards.clear()
		pokedex_reorder_result.clear()

# CPU Pokedex priority helper
func _cpu_pokedex_priority(card: card_object) -> float:
	var score = 0.0
	var name = card.metadata.get("name", "").to_lower()
	var supertype = card.metadata.get("supertype", "").to_lower()
	
	if name == "bill" or name == "professor oak":
		score += 100.0
	elif supertype == "energy":
		var energy_in_hand = 0
		for c in opponent_hand:
			if c.metadata.get("supertype", "").to_lower() == "energy":
				energy_in_hand += 1
		if energy_in_hand <= 1:
			score += 80.0
		else:
			score += 40.0
	elif supertype == "pokémon" and not is_basic_pokemon(card):
		# Evolution that can be played
		var evolves_from = card.metadata.get("evolvesFrom", "")
		var has_base = false
		if opponent_active_pokemon != null and opponent_active_pokemon.metadata.get("name", "") == evolves_from:
			has_base = true
		for bp in opponent_bench:
			if bp.metadata.get("name", "") == evolves_from:
				has_base = true
		score += 70.0 if has_base else 20.0
	elif supertype == "trainer":
		score += 50.0
	elif supertype == "pokémon" and is_basic_pokemon(card):
		score += 30.0 if opponent_bench.size() < 5 else 10.0
	
	return score

# base1-89 — Revive: Put Basic from discard to bench at half HP
func effect_revive(is_opponent: bool) -> void:
	var bench = opponent_bench if is_opponent else player_bench
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	
	if bench.size() >= 5:
		await show_message("Bench is full!")
		return
	
	var basics_in_discard = []
	for card in discard:
		if is_basic_pokemon(card):
			basics_in_discard.append(card)
	
	if basics_in_discard.size() == 0:
		await show_message("No Basic Pokemon in discard pile!")
		return
	
	if is_opponent:
		# CPU: pick highest scoring basic
		var best: card_object = null
		var best_score = -999.0
		for card in basics_in_discard:
			var result = evaluate_opponents_start_setup_pokemon_choices(card, opponent_hand)
			var score = result.get("total_score", 0)
			if score > best_score:
				best_score = score
				best = card
		if best != null:
			discard.erase(best)
			best.current_location = "bench"
			var max_hp = int(best.metadata.get("hp", "0"))
			best.current_hp = max(10, max_hp / 2)
			best.placed_on_field_this_turn = true
			bench.append(best)
			display_pokemon(true)
			await show_message("Opponent revived " + best.metadata.get("name", "") + " at half HP!")
	else:
		trainer_deck_search_active = true
		show_enlarged_array_selection_mode(basics_in_discard)
		header_label.text = "REVIVE"
		hint_label.text = "Select a Basic Pokemon to revive at half HP"
		action_button.text = "REVIVE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var chosen = selected_card_for_action
		trainer_deck_search_active = false
		hide_selection_mode_display_main()
		
		if chosen != null:
			discard.erase(chosen)
			chosen.current_location = "bench"
			var max_hp = int(chosen.metadata.get("hp", "0"))
			chosen.current_hp = max(10, (max_hp / 20) * 10) # Half HP rounded down to nearest 10
			chosen.placed_on_field_this_turn = true
			bench.append(chosen)
			display_pokemon(false)
			await show_message(chosen.metadata.get("name", "") + " revived at " + str(chosen.current_hp) + " HP!")

# base1-90 — Super Potion: Discard 1 energy from pokemon, remove up to 4 damage counters
func effect_super_potion(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	var discard = opponent_discard_pile if is_opponent else player_discard_pile
	
	# Find pokemon with both damage and energy
	var valid_targets = []
	var all_pokemon = build_field_pokemon_array(is_opponent)
	for p in all_pokemon:
		if p.current_hp < int(p.metadata.get("hp", "0")) and p.attached_energies.size() > 0:
			valid_targets.append(p)
	
	if valid_targets.size() == 0:
		await show_message("No Pokemon with both damage and energy!")
		return
	
	if is_opponent:
		var best_target: card_object = null
		var most_damage = 0
		for pokemon in valid_targets:
			var dmg = int(pokemon.metadata.get("hp", "0")) - pokemon.current_hp
			if dmg > most_damage:
				most_damage = dmg
				best_target = pokemon
		if best_target != null:
			var energy = best_target.attached_energies.pop_back()
			energy.current_location = "discard"
			discard.append(energy)
			var max_hp = int(best_target.metadata.get("hp", "0"))
			var heal = min(40, max_hp - best_target.current_hp)
			best_target.current_hp = min(max_hp, best_target.current_hp + heal)
			display_active_pokemon_energies(true)
			await play_heal_animation(best_target, heal, true)
			update_discard_pile_display(true)
	else:
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(valid_targets)
		header_label.text = "SUPER POTION"
		hint_label.text = "Select a Pokemon to heal (will discard 1 energy)"
		action_button.text = "HEAL"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var target = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if target != null:
			# Animate energy discard
			var energy = target.attached_energies.pop_back()
			energy.current_location = "discard"
			discard.append(energy)
			var from_node = find_card_ui_for_object(target)
			if from_node == null:
				from_node = player_active_container if target == player_active_pokemon else player_bench_container
			var energy_texture = get_card_texture(energy)
			await animate_card_a_to_b(from_node, player_discard_icon, 0.2, energy_texture, card_scales[10])
			display_active_pokemon_energies(false)
			update_discard_pile_display(false)
			var max_hp = int(target.metadata.get("hp", "0"))
			var heal = min(40, max_hp - target.current_hp)
			target.current_hp = min(max_hp, target.current_hp + heal)
			await play_heal_animation(target, heal, false)

# base1-92 — Energy Removal: Discard 1 energy from opponent's pokemon
func effect_energy_removal(is_opponent: bool) -> void:
	var target_is_opp = not is_opponent
	var target_discard = player_discard_pile if is_opponent else opponent_discard_pile
	
	# Build combined array with energy, active last
	var all_targets = build_field_pokemon_array(target_is_opp)
	var targets_with_energy = all_targets.filter(func(p): return p.attached_energies.size() > 0)
	
	if targets_with_energy.size() == 0:
		await show_message("Opponent has no energy to remove!")
		return
	
	if is_opponent:
		var target_active = player_active_pokemon
		var target = target_active if target_active != null and target_active.attached_energies.size() > 0 else targets_with_energy[0]
		var energy = target.attached_energies.pop_back()
		energy.current_location = "discard"
		target_discard.append(energy)
		var from_node = find_card_ui_for_object(target)
		if from_node == null:
			from_node = player_active_container
		var energy_texture = get_card_texture(energy)
		await animate_card_a_to_b(from_node, player_discard_icon, 0.2, energy_texture, card_scales[10])
		display_active_pokemon_energies(false)
		update_discard_pile_display(false)
		await show_message("Opponent removed energy from " + target.metadata.get("name", "") + "!")
	else:
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(targets_with_energy)
		header_label.text = "ENERGY REMOVAL"
		hint_label.text = "Select opponent's Pokemon to remove energy from"
		action_button.text = "SELECT"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var target = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if target != null and target.attached_energies.size() > 0:
			defender_energy_discard_active = true
			show_enlarged_array_selection_mode(target.attached_energies)
			cancel_button.visible = false
			header_label.text = "CHOOSE ENERGY TO REMOVE"
			hint_label.text = "Select an energy card to discard"
			action_button.text = "DISCARD"
			action_button.disabled = true
			action_button.theme = theme_disabled
			await defender_energy_chosen
			var energy = selected_card_for_action
			defender_energy_discard_active = false
			hide_selection_mode_display_main()
			
			if energy != null:
				target.attached_energies.erase(energy)
				energy.current_location = "discard"
				target_discard.append(energy)
				var from_node = find_card_ui_for_object(target)
				if from_node == null:
					from_node = opponent_active_container if target == opponent_active_pokemon else opponent_bench_container
				var energy_texture = get_card_texture(energy)
				await animate_card_a_to_b(from_node, opponent_discard_icon, 0.2, energy_texture, card_scales[10])
				display_active_pokemon_energies(true)
				update_discard_pile_display(true)

# base1-93 — Gust of Wind: Switch opponent's active with a bench pokemon
func effect_gust_of_wind(is_opponent: bool) -> void:
	var target_bench = player_bench if is_opponent else opponent_bench
	var target_is_opp = not is_opponent
	
	if target_bench.size() == 0:
		await show_message("Opponent has no bench Pokemon!")
		return
	
	var new_active: card_object = null
	
	if is_opponent:
		# CPU: pull in easiest to KO target
		var best: card_object = null
		var best_score = -999.0
		for bp in target_bench:
			var score = 0.0
			# Low HP = easy KO
			score += (200.0 - bp.current_hp)
			# No energy = can't fight back
			if bp.attached_energies.size() == 0:
				score += 100.0
			if score > best_score:
				best_score = score
				best = bp
		new_active = best
	else:
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(target_bench)
		header_label.text = "GUST OF WIND"
		hint_label.text = "Select opponent's bench Pokemon to pull forward"
		action_button.text = "SWITCH"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		new_active = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
	
	if new_active != null:
		var old_active = player_active_pokemon if is_opponent else opponent_active_pokemon
		var bench = target_bench
		
		bench.erase(new_active)
		bench.append(old_active)
		old_active.current_location = "bench"
		new_active.current_location = "active"
		
		if is_opponent:
			player_active_pokemon = new_active
		else:
			opponent_active_pokemon = new_active
		
		await animate_retreat(old_active, new_active, [], target_is_opp)
		clear_all_statuses(old_active, target_is_opp)
		display_pokemon(target_is_opp)
		display_active_pokemon_energies(target_is_opp)
		await show_message(new_active.metadata.get("name", "") + " was pulled to the active spot!")

# base1-94 — Potion: Remove up to 2 damage counters from 1 pokemon
func effect_potion(is_opponent: bool) -> void:
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	var bench = opponent_bench if is_opponent else player_bench
	
	var damaged = build_field_pokemon_array(is_opponent).filter(func(p): return p.current_hp < int(p.metadata.get("hp", "0")))
	
	if damaged.size() == 0:
		await show_message("No Pokemon with damage!")
		return
	
	if is_opponent:
		var target = damaged[0]
		var max_hp = int(target.metadata.get("hp", "0"))
		var heal = min(20, max_hp - target.current_hp)
		target.current_hp = min(max_hp, target.current_hp + heal)
		await play_heal_animation(target, heal, true)
	else:
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(damaged)
		header_label.text = "POTION"
		hint_label.text = "Select a Pokemon to heal (up to 20 HP)"
		action_button.text = "HEAL"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var target = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if target != null:
			var max_hp = int(target.metadata.get("hp", "0"))
			var heal = min(20, max_hp - target.current_hp)
			target.current_hp = min(max_hp, target.current_hp + heal)
			await play_heal_animation(target, heal, false)

# base1-95 — Switch: Free retreat (swap active with bench)
func effect_switch(is_opponent: bool) -> void:
	var bench = opponent_bench if is_opponent else player_bench
	var active = opponent_active_pokemon if is_opponent else player_active_pokemon
	
	if bench.size() == 0:
		await show_message("No bench Pokemon to switch with!")
		return
	
	if active == null:
		return
	
	if is_opponent:
		var cpu_eval = build_cpu_evaluation()
		var replacement = pick_best_bench_replacement(bench, player_active_pokemon, cpu_eval)
		if replacement == null:
			replacement = bench[0]
		
		bench.erase(replacement)
		bench.append(active)
		active.current_location = "bench"
		replacement.current_location = "active"
		opponent_active_pokemon = replacement
		await animate_retreat(active, replacement, [], true)
		clear_all_statuses(active, true)
		display_pokemon(true)
		display_active_pokemon_energies(true)
		await show_message("Opponent switched to " + replacement.metadata.get("name", "") + "!")
	else:
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(bench)
		header_label.text = "SWITCH"
		hint_label.text = "Select a bench Pokemon to switch with your active"
		action_button.text = "SWITCH"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = false
		await trainer_target_selected
		var replacement = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if replacement != null:
			bench.erase(replacement)
			bench.append(active)
			active.current_location = "bench"
			replacement.current_location = "active"
			player_active_pokemon = replacement
			await animate_retreat(active, replacement, [], false)
			clear_all_statuses(active, false)
			display_pokemon(false)
			display_active_pokemon_energies(false)

############################################### Section E: PLAYER TRAINER UI HELPERS ################################################################

# Shows hand cards for player to select N cards to discard
func player_select_cards_to_discard(hand: Array, count: int, title: String, hint: String) -> void:
	trainer_discard_selected.clear()
	trainer_discard_cards_needed = count
	trainer_discard_selection_active = true
	
	show_enlarged_array_selection_mode(hand)
	header_label.text = title
	hint_label.text = hint + " (0/" + str(count) + " selected)"
	action_button.text = str(count) + " MORE"
	action_button.disabled = true
	action_button.theme = theme_disabled
	cancel_button.visible = false
	
	await trainer_discard_selection_done
	trainer_discard_selection_active = false
	hide_selection_mode_display_main()

############################################### Section F: CPU TRAINER SCORING & PLAY PHASES ########################################################

# Master scoring function: returns the CPU priority score for a trainer card
func cpu_score_trainer_card(card: card_object) -> float:
	var card_id = card.uid.to_lower()
	
	match card_id:
		"base1-91": return 100.0 # Bill: always play
		"base1-88": return _cpu_score_professor_oak(card)
		"base1-71": return _cpu_score_computer_search(card)
		"base1-72": return _cpu_score_devolution_spray()
		"base1-73": return _cpu_score_impostor_prof_oak()
		"base1-74": return _cpu_score_item_finder()
		"base1-75": return _cpu_score_lass()
		"base1-76": return _cpu_score_pokemon_breeder()
		"base1-77": return _cpu_score_pokemon_trader()
		"base1-78": return _cpu_score_scoop_up()
		"base1-79": return _cpu_score_super_energy_removal()
		"base1-80": return _cpu_score_defender()
		"base1-81": return _cpu_score_energy_retrieval()
		"base1-82": return _cpu_score_full_heal()
		"base1-83": return _cpu_score_maintenance()
		"base1-84": return _cpu_score_pluspower()
		"base1-85": return _cpu_score_pokemon_center()
		"base1-86": return -100.0 # Pokemon Flute: CPU never plays
		"base1-87": return 60.0 # Pokedex
		"base1-89": return _cpu_score_revive()
		"base1-90": return _cpu_score_super_potion()
		"base1-92": return _cpu_score_energy_removal()
		"base1-93": return _cpu_score_gust_of_wind()
		"base1-94": return _cpu_score_potion()
		"base1-95": return _cpu_score_switch()
		"base1-70": return _cpu_score_clefairy_doll()
	return 0.0

func _cpu_score_professor_oak(card: card_object) -> float:
	var hand = opponent_hand
	if hand.size() > 5: return -50.0
	# Check for playable evolutions
	for c in hand:
		if c == card: continue
		var subtypes = c.metadata.get("subtypes", [])
		if "Stage 2" in subtypes: return -50.0
		if "Stage 1" in subtypes:
			var targets = get_valid_evolution_targets(c, true)
			if targets.size() > 0: return -50.0 + (-20.0)
	if hand.size() <= 1: return 90.0
	if hand.size() <= 3: return 70.0
	if hand.size() <= 4: return 40.0
	return -50.0

func _cpu_score_computer_search(card: card_object) -> float:
	if opponent_hand.size() < 3: return 0.0
	return 60.0

func _cpu_score_devolution_spray() -> float:
	return -100.0

func _cpu_score_impostor_prof_oak() -> float:
	if player_hand.size() >= 7:
		return 50.0 + (player_hand.size() - 7) * 10.0
	return 0.0

func _cpu_score_item_finder() -> float:
	if opponent_hand.size() < 3: return 0.0
	var trainers_in_discard = []
	for c in opponent_discard_pile:
		if is_trainer_card(c):
			trainers_in_discard.append(c)
	if trainers_in_discard.size() == 0: return 0.0
	var best = 0.0
	for t in trainers_in_discard:
		best = max(best, cpu_score_trainer_card(t))
	return best if best >= 50.0 else 0.0

func _cpu_score_lass() -> float:
	var score = 0.0
	# Add 30 if CPU has no playable trainers
	var has_playable = false
	for c in opponent_hand:
		if is_trainer_card(c) and cpu_score_trainer_card(c) > 30:
			has_playable = true
	if not has_playable: score += 30.0
	# Add based on player hand size
	if player_hand.size() > 4:
		score += 5.0 * (player_hand.size() - 4)
	# Subtract for own playable trainers lost
	for c in opponent_hand:
		if is_trainer_card(c) and cpu_score_trainer_card(c) > 30:
			score -= 15.0
	return score

func _cpu_score_pokemon_breeder() -> float:
	for card in opponent_hand:
		var subtypes = card.metadata.get("subtypes", [])
		if "Stage 2" in subtypes:
			var all_pokemon = []
			if opponent_active_pokemon != null: all_pokemon.append(opponent_active_pokemon)
			all_pokemon.append_array(opponent_bench)
			for p in all_pokemon:
				if not p.placed_on_field_this_turn and is_basic_pokemon(p) and _basic_matches_stage2(p, card):
					return 100.0
	return -100.0

func _cpu_score_pokemon_trader() -> float:
	for card in opponent_hand:
		if card.metadata.get("supertype", "").to_lower() != "pokémon": continue
		if is_basic_pokemon(card):
			var name = card.metadata.get("name", "")
			var already_in_play = false
			if opponent_active_pokemon != null and opponent_active_pokemon.metadata.get("name", "") == name:
				already_in_play = true
			for bp in opponent_bench:
				if bp.metadata.get("name", "") == name: already_in_play = true
			if already_in_play: return 70.0
	return 0.0

func _cpu_score_scoop_up() -> float:
	var all_pokemon = []
	if opponent_active_pokemon != null: all_pokemon.append(opponent_active_pokemon)
	all_pokemon.append_array(opponent_bench)
	for p in all_pokemon:
		var max_hp = int(p.metadata.get("hp", "0"))
		if p.current_hp <= max_hp / 2 and opponent_bench.size() > 0:
			return 80.0
	return 0.0

func _cpu_score_super_energy_removal() -> float:
	if player_active_pokemon == null: return 0.0
	var p_energy = player_active_pokemon.attached_energies.size()
	# Check own energy available
	var own_energy = false
	if opponent_active_pokemon != null and opponent_active_pokemon.attached_energies.size() > 0:
		own_energy = true
	for bp in opponent_bench:
		if bp.attached_energies.size() > 0: own_energy = true
	if not own_energy: return 0.0
	if p_energy >= 3: return 90.0
	if p_energy >= 2: return 60.0
	return 0.0

func _cpu_score_defender() -> float:
	if opponent_active_pokemon == null or player_active_pokemon == null: return 0.0
	var ko_threats = evaluate_ko_threats()
	if ko_threats.get("cpu_active_guaranteed_ko", false): return 60.0
	return 0.0

func _cpu_score_energy_retrieval() -> float:
	var energy_in_hand = 0
	for c in opponent_hand:
		if c.metadata.get("supertype", "").to_lower() == "energy":
			energy_in_hand += 1
	var basic_in_discard = 0
	for c in opponent_discard_pile:
		if is_basic_energy_card(c): basic_in_discard += 1
	if energy_in_hand <= 1 and basic_in_discard >= 2: return 70.0
	if energy_in_hand <= 1 and basic_in_discard >= 1: return 40.0
	return 0.0

func _cpu_score_full_heal() -> float:
	if opponent_active_pokemon == null: return 0.0
	match opponent_active_pokemon.special_condition:
		"Paralyzed": return 100.0
		"Confused": return 80.0
		"Asleep": return 60.0
	if opponent_active_pokemon.is_poisoned: return 40.0
	return 0.0

func _cpu_score_maintenance() -> float:
	if opponent_hand.size() < 4: return 0.0
	return 30.0

func _cpu_score_pluspower() -> float:
	if opponent_active_pokemon == null or player_active_pokemon == null: return 0.0
	var pp_bonus = (opponent_active_pokemon.pluspower_count + 1) * 10
	# Check if this KOs
	for attack in opponent_active_pokemon.metadata.get("attacks", []):
		if get_unmet_energy_count(attack, opponent_active_pokemon) > 0: continue
		var dmg_range = get_attack_damage_range(attack, opponent_active_pokemon, player_active_pokemon)
		var types = opponent_active_pokemon.metadata.get("types", ["Colorless"])
		var result_without = calculate_final_damage(dmg_range["min"], types, player_active_pokemon)
		if result_without["damage"] < player_active_pokemon.current_hp:
			var result_with = result_without["damage"] + pp_bonus
			if result_with >= player_active_pokemon.current_hp:
				return 90.0
	return 30.0

func _cpu_score_pokemon_center() -> float:
	var total_damage = 0
	var total_max_hp = 0
	var energy_lost = 0
	var all_pokemon = []
	if opponent_active_pokemon != null: all_pokemon.append(opponent_active_pokemon)
	all_pokemon.append_array(opponent_bench)
	for p in all_pokemon:
		var max_hp = int(p.metadata.get("hp", "0"))
		var dmg = max_hp - p.current_hp
		if dmg > 0:
			total_damage += dmg
			total_max_hp += max_hp
			energy_lost += p.attached_energies.size()
	if total_max_hp == 0: return 0.0
	if float(total_damage) / float(total_max_hp) > 0.5:
		return max(0.0, 80.0 - energy_lost * 10.0)
	return 0.0

func _cpu_score_revive() -> float:
	if opponent_bench.size() >= 5: return 0.0
	for c in opponent_discard_pile:
		if is_basic_pokemon(c):
			var result = evaluate_opponents_start_setup_pokemon_choices(c, opponent_hand)
			if result.get("total_score", 0) >= 250:
				return 70.0
	return 0.0

func _cpu_score_super_potion() -> float:
	if opponent_active_pokemon == null: return 0.0
	var max_hp = int(opponent_active_pokemon.metadata.get("hp", "0"))
	var dmg = max_hp - opponent_active_pokemon.current_hp
	var ko_threats = evaluate_ko_threats()
	if ko_threats.get("cpu_active_guaranteed_ko", false) and dmg >= 40 and opponent_active_pokemon.attached_energies.size() > 0:
		return 90.0
	return 0.0

func _cpu_score_energy_removal() -> float:
	if player_active_pokemon == null: return 0.0
	var e = player_active_pokemon.attached_energies.size()
	if e >= 2: return 60.0
	if e == 1: return 30.0
	return 0.0

func _cpu_score_gust_of_wind() -> float:
	if player_bench.size() == 0: return 0.0
	for bp in player_bench:
		if opponent_active_pokemon != null:
			var types = opponent_active_pokemon.metadata.get("types", ["Colorless"])
			for attack in opponent_active_pokemon.metadata.get("attacks", []):
				if get_unmet_energy_count(attack, opponent_active_pokemon) > 0: continue
				var dmg_range = get_attack_damage_range(attack, opponent_active_pokemon, bp)
				var result = calculate_final_damage(dmg_range["min"], types, bp)
				if result["damage"] >= bp.current_hp:
					return 85.0
	return 0.0

func _cpu_score_potion() -> float:
	if opponent_active_pokemon == null: return 0.0
	var ko_threats = evaluate_ko_threats()
	if ko_threats.get("cpu_active_guaranteed_ko", false):
		var max_hp = int(opponent_active_pokemon.metadata.get("hp", "0"))
		if opponent_active_pokemon.current_hp + 20 > max_hp * 0.5:
			return 60.0
	return 0.0

func _cpu_score_switch() -> float:
	if opponent_bench.size() == 0: return 0.0
	var cpu_eval = build_cpu_evaluation()
	if evaluate_retreat_reasons(cpu_eval):
		return 70.0
	return 0.0

func _cpu_score_clefairy_doll() -> float:
	if opponent_bench.size() < 3: return 20.0
	return -100.0

# CPU plays highest-priority trainer cards (Bill first)
func cpu_phase_play_trainer_cards_priority() -> void:
	var played = true
	while played:
		played = false
		var best_card: card_object = null
		var best_score = 29.9 # Threshold: play cards scoring >= 30
		
		for card in opponent_hand:
			if not is_trainer_card(card): continue
			var score = cpu_score_trainer_card(card)
			if score > best_score:
				best_score = score
				best_card = card
		
		if best_card != null:
			# Validate the card can actually be played before committing
			var validation_error = validate_trainer_can_be_played(best_card, true)
			if validation_error != "":
				# Skip this card and continue looking
				# Mark it so we don't try it again this loop
				opponent_hand.erase(best_card)
				opponent_hand.append(best_card)  # Move to end
				break
			await play_trainer_card(best_card, true)
			played = true

# CPU re-evaluates and plays remaining trainer cards
func cpu_phase_play_trainer_cards_remaining() -> void:
	var played = true
	while played:
		played = false
		var best_card: card_object = null
		var best_score = 29.9 # Threshold: play cards scoring >= 30
		
		for card in opponent_hand:
			if not is_trainer_card(card): continue
			var score = cpu_score_trainer_card(card)
			if score > best_score:
				best_score = score
				best_card = card
		
		if best_card != null:
			# Validate the card can actually be played before committing
			var validation_error = validate_trainer_can_be_played(best_card, true)
			if validation_error != "":
				break
			await play_trainer_card(best_card, true)
			played = true

# CPU search deck helpers
func cpu_search_deck_for_best_card(deck: Array) -> card_object:
	# Priority: draw trainers > evolution cards > energy > basic pokemon
	var best: card_object = null
	var best_score = -1.0
	for card in deck:
		var score = 0.0
		var name = card.metadata.get("name", "").to_lower()
		if name == "bill": score = 100.0
		elif name == "professor oak" and opponent_hand.size() <= 3: score = 90.0
		elif card.metadata.get("supertype", "").to_lower() == "pokémon" and not is_basic_pokemon(card):
			var targets = get_valid_evolution_targets(card, true)
			if targets.size() > 0: score = 80.0
		elif card.metadata.get("supertype", "").to_lower() == "energy": score = 50.0
		elif is_basic_pokemon(card) and opponent_bench.size() < 3: score = 40.0
		if score > best_score:
			best_score = score
			best = card
	return best

func cpu_search_deck_for_best_pokemon(pokemon_list: Array) -> card_object:
	var best: card_object = null
	var best_score = -1.0
	for card in pokemon_list:
		var score = 0.0
		if not is_basic_pokemon(card):
			var targets = get_valid_evolution_targets(card, true)
			if targets.size() > 0: score = 80.0
			else: score = 20.0
		else:
			var result = evaluate_opponents_start_setup_pokemon_choices(card, opponent_hand)
			score = result.get("total_score", 0) / 10.0
		if score > best_score:
			best_score = score
			best = card
	return best

############################################### Section G: POKEMON POWER SYSTEM ######################################################################

# Opens the Pokemon Power selection menu
func open_power_menu() -> void:
	if opponents_turn_active:
		return
	
	# Scan for available powers
	var available_powers = []
	var all_pokemon = []
	if player_active_pokemon != null:
		all_pokemon.append(player_active_pokemon)
	all_pokemon.append_array(player_bench)
	
	for pokemon in all_pokemon:
		var abilities = pokemon.metadata.get("abilities", [])
		for ability in abilities:
			var ability_type = ability.get("type", "")
			if ability_type != "Pokémon Power" and ability_type != "Pokemon Power":
				continue
			var ability_name = ability.get("name", "")
			# Skip passive powers (they don't go in menu)
			if ability_name in ["Strikes Back", "Energy Burn"]:
				continue
			# Check if usable
			if ability_name != "Buzzap" and is_power_blocked_by_status(pokemon):
				continue
			available_powers.append({"pokemon": pokemon, "ability": ability})
	
	if available_powers.size() == 0:
		# Also check for bench tokens with voluntary discard (their ability is in rules text, not abilities field)
		for bp in player_bench:
			if bp.is_bench_token:
				available_powers.append({"pokemon": bp, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card from your bench."}})
		# Check active pokemon too
		if player_active_pokemon != null and player_active_pokemon.is_bench_token:
			available_powers.append({"pokemon": player_active_pokemon, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card."}})
	else:
		# Add bench token discards if they weren't already found via abilities
		for bp in player_bench:
			if bp.is_bench_token:
				var already_added = false
				for p in available_powers:
					if p["pokemon"] == bp:
						already_added = true
						break
				if not already_added:
					available_powers.append({"pokemon": bp, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card from your bench."}})
		# Check active too
		if player_active_pokemon != null and player_active_pokemon.is_bench_token:
			var already_added = false
			for p in available_powers:
				if p["pokemon"] == player_active_pokemon:
					already_added = true
					break
			if not already_added:
				available_powers.append({"pokemon": player_active_pokemon, "ability": {"name": "Discard", "type": "Pokémon Power", "text": "Discard this card."}})
	
	if available_powers.size() == 0:
		await show_message("No Pokemon Powers available!")
		return
	
	# Create power buttons
	main_buttons_container.visible = false
	attack_buttons_container.visible = true
	
	for power_info in available_powers:
		var pokemon = power_info["pokemon"]
		var ability = power_info["ability"]
		var btn = Button.new()
		btn.text = pokemon.metadata.get("name", "") + " - " + ability.get("name", "")
		btn.custom_minimum_size = Vector2(450, 50)
		btn.theme = theme_blue
		attack_buttons_container.add_child(btn)
		btn.pressed.connect(activate_power.bind(pokemon, ability))

# Activates a specific Pokemon Power
func activate_power(pokemon: card_object, ability: Dictionary) -> void:
	hide_attack_buttons()
	var ability_name = ability.get("name", "")
	
	match ability_name:
		"Damage Swap": await power_damage_swap(pokemon)
		"Rain Dance": await power_rain_dance(pokemon)
		"Energy Trans": await power_energy_trans(pokemon)
		"Buzzap": await power_buzzap(pokemon)
		"Discard": await power_bench_token_discard(pokemon)
		_: await show_message("Power not implemented: " + ability_name)

# Damage Swap (Alakazam): Move 1 damage counter between your pokemon
func power_damage_swap(alakazam: card_object) -> void:
	var all_pokemon = []
	if player_active_pokemon != null:
		all_pokemon.append(player_active_pokemon)
	all_pokemon.append_array(player_bench)
	
	await show_message("DAMAGE SWAP: Move damage counters between your Pokemon")
	
	var keep_swapping = true
	while keep_swapping:
		# Select source (pokemon with damage)
		var sources = []
		for p in all_pokemon:
			if p.current_hp < int(p.metadata.get("hp", "0")):
				sources.append(p)
		if sources.size() == 0:
			await show_message("No Pokemon with damage!")
			break
		
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(sources)
		header_label.text = "DAMAGE SWAP - SOURCE"
		hint_label.text = "Select a Pokemon to take damage FROM (or cancel to stop)"
		action_button.text = "SELECT"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = true
		await trainer_target_selected
		var source = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if source == null:
			break
		
		# Select destination (pokemon that can take 1 more without KO)
		var destinations = []
		for p in all_pokemon:
			if p == source: continue
			if p.current_hp > 10: # Can take 10 damage without KO
				destinations.append(p)
		
		if destinations.size() == 0:
			await show_message("No Pokemon can receive the damage counter!")
			break
		
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(destinations)
		header_label.text = "DAMAGE SWAP - DESTINATION"
		hint_label.text = "Select a Pokemon to move damage TO"
		action_button.text = "MOVE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = true
		await trainer_target_selected
		var dest = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if dest == null:
			break
		
		# Move 1 damage counter
		source.current_hp += 10
		dest.current_hp -= 10
		display_hp_circles_above_align(player_active_pokemon, false)
		display_pokemon(false)
		await show_message("Moved 1 damage counter from " + source.metadata.get("name", "") + " to " + dest.metadata.get("name", "") + "!")

# Rain Dance (Blastoise): Attach Water Energy from hand to Water Pokemon
func power_rain_dance(blastoise: card_object) -> void:
	await show_message("RAIN DANCE: Attach Water Energy to Water Pokemon!")
	
	var keep_going = true
	while keep_going:
		# Find Water Energy in hand
		var water_energies = []
		for card in player_hand:
			if card.metadata.get("supertype", "").to_lower() == "energy":
				if "Water" in card.metadata.get("name", ""):
					water_energies.append(card)
		
		if water_energies.size() == 0:
			await show_message("No Water Energy in hand!")
			break
		
		# Find Water Pokemon
		var water_pokemon = []
		if player_active_pokemon != null and "Water" in player_active_pokemon.metadata.get("types", []):
			water_pokemon.append(player_active_pokemon)
		for bp in player_bench:
			if "Water" in bp.metadata.get("types", []):
				water_pokemon.append(bp)
		
		if water_pokemon.size() == 0:
			await show_message("No Water Pokemon in play!")
			break
		
		# Select target
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(water_pokemon)
		header_label.text = "RAIN DANCE"
		hint_label.text = "Select a Water Pokemon to attach energy to (cancel to stop)"
		action_button.text = "ATTACH"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = true
		await trainer_target_selected
		var target = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if target == null:
			break
		
		# Attach the first water energy
		var energy = water_energies[0]
		player_hand.erase(energy)
		target.attached_energies.append(energy)
		refresh_hand_display(false)
		display_active_pokemon_energies(false)
		await show_message("Attached Water Energy to " + target.metadata.get("name", "") + "!")

# Energy Trans (Venusaur): Move Grass Energy between your Pokemon
func power_energy_trans(venusaur: card_object) -> void:
	await show_message("ENERGY TRANS: Move Grass Energy between your Pokemon!")
	
	var keep_going = true
	while keep_going:
		# Find pokemon with Grass Energy attached
		var all_pokemon = []
		if player_active_pokemon != null: all_pokemon.append(player_active_pokemon)
		all_pokemon.append_array(player_bench)
		
		var sources = []
		for p in all_pokemon:
			for e in p.attached_energies:
				if "Grass" in get_energy_provided_by_card(e):
					if p not in sources:
						sources.append(p)
		
		if sources.size() == 0:
			await show_message("No Pokemon with Grass Energy!")
			break
		
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(sources)
		header_label.text = "ENERGY TRANS - SOURCE"
		hint_label.text = "Select Pokemon to take Grass Energy from (cancel to stop)"
		action_button.text = "SELECT"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = true
		await trainer_target_selected
		var source = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if source == null:
			break
		
		# Find the grass energy to move
		var grass_energy: card_object = null
		for e in source.attached_energies:
			if "Grass" in get_energy_provided_by_card(e):
				grass_energy = e
				break
		if grass_energy == null:
			break
		
		# Select destination
		var destinations = all_pokemon.filter(func(p): return p != source)
		if destinations.size() == 0:
			break
		
		trainer_pokemon_selection_active = true
		show_enlarged_array_selection_mode(destinations)
		header_label.text = "ENERGY TRANS - DESTINATION"
		hint_label.text = "Select Pokemon to move Grass Energy to"
		action_button.text = "MOVE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		cancel_button.visible = true
		await trainer_target_selected
		var dest = selected_card_for_action
		trainer_pokemon_selection_active = false
		hide_selection_mode_display_main()
		
		if dest == null:
			break
		
		source.attached_energies.erase(grass_energy)
		dest.attached_energies.append(grass_energy)
		display_active_pokemon_energies(false)
		await show_message("Moved Grass Energy from " + source.metadata.get("name", "") + " to " + dest.metadata.get("name", "") + "!")

# Buzzap (Electrode): KO Electrode, attach as energy to another pokemon
func power_buzzap(electrode: card_object) -> void:
	# Cannot use if Electrode is the last pokemon
	var total_pokemon = (1 if player_active_pokemon != null else 0) + player_bench.size()
	if total_pokemon <= 1:
		await show_message("Cannot use Buzzap - Electrode is your last Pokemon!")
		return
	
	await show_message("BUZZAP: Electrode will be Knocked Out and become Energy!")
	
	# Select energy type
	var energy_types = ["Fire", "Water", "Grass", "Lightning", "Psychic", "Fighting", "Colorless"]
	# Use simple message-based selection for type
	# For simplicity, create a selection of fake energy cards
	var type_options = []
	for etype in energy_types:
		# Create a temporary card_object to represent each type
		var temp = card_object.new("base1-96", {"name": etype + " Energy", "supertype": "Energy"})
		type_options.append(temp)
	
	energy_type_selection_active = true
	show_enlarged_array_selection_mode(type_options)
	header_label.text = "BUZZAP - CHOOSE ENERGY TYPE"
	hint_label.text = "Select what type of Energy Electrode will become"
	action_button.text = "SELECT TYPE"
	action_button.disabled = true
	action_button.theme = theme_disabled
	cancel_button.visible = true
	await energy_type_selected
	var chosen_type = ""
	if selected_card_for_action != null:
		chosen_type = selected_card_for_action.metadata.get("name", "").replace(" Energy", "")
	energy_type_selection_active = false
	hide_selection_mode_display_main()
	
	# Temp type_options are RefCounted and will be freed automatically when out of scope
	
	if chosen_type == "":
		return
	
	# Select target pokemon
	var targets = player_bench.duplicate()
	if player_active_pokemon != null and player_active_pokemon != electrode:
		targets.append(player_active_pokemon)
	targets.erase(electrode)
	
	if targets.size() == 0:
		return
	
	trainer_pokemon_selection_active = true
	show_enlarged_array_selection_mode(targets)
	header_label.text = "BUZZAP - ATTACH TO"
	hint_label.text = "Select a Pokemon to attach Electrode-Energy to"
	action_button.text = "ATTACH"
	action_button.disabled = true
	action_button.theme = theme_disabled
	cancel_button.visible = false
	await trainer_target_selected
	var target = selected_card_for_action
	trainer_pokemon_selection_active = false
	hide_selection_mode_display_main()
	
	if target == null:
		return
	
	# KO Electrode (prize will be awarded via normal knockout flow)
	electrode.current_hp = 0
	
	# Create the electrode-as-energy token
	var electrode_energy = card_object.new(electrode.uid, electrode.metadata)
	electrode_energy.is_electrode_energy = true
	electrode_energy.electrode_energy_type = chosen_type
	target.attached_energies.append(electrode_energy)
	
	display_active_pokemon_energies(false)
	await show_message("Electrode became " + chosen_type + " Energy!")
	
	# Process the knockout
	await check_all_knockouts()

# Discard bench token (Clefairy Doll voluntary discard)
func power_bench_token_discard(token: card_object) -> void:
	var was_active = (token == player_active_pokemon)
	
	if was_active:
		# Remove from active slot
		player_active_pokemon = null
	else:
		player_bench.erase(token)
	
	send_card_to_discard(token, false)
	display_pokemon(false)
	display_active_pokemon_energies(false)
	await show_message(token.metadata.get("name", "") + " was voluntarily discarded!")
	
	# If it was active, force a bench replacement (no prize awarded)
	if was_active:
		if player_bench.size() == 0:
			await show_message("No Pokemon remaining!")
			game_end_logic(true)  # true = player loses
			return
		knockout_bench_selection_active = true
		show_enlarged_array_selection_mode(player_bench)
		cancel_button.visible = false
		header_label.text = "CHOOSE NEW ACTIVE POKEMON"
		hint_label.text = "Your active was discarded - select a replacement"
		action_button.text = "SET ACTIVE"
		action_button.disabled = true
		action_button.theme = theme_disabled
		await knockout_replacement_chosen
		display_active_pokemon_energies(false)

############################################### Section H: CPU POWER ACTIVATION ######################################################################

# CPU activates beneficial powers at start of turn
func cpu_phase_activate_powers() -> void:
	# Rain Dance: attach all Water Energy to Water Pokemon
	var blastoise = _find_cpu_pokemon_with_power("Rain Dance")
	if blastoise != null and not is_power_blocked_by_status(blastoise):
		var keep_going = true
		while keep_going:
			keep_going = false
			var water_energy: card_object = null
			for card in opponent_hand:
				if card.metadata.get("supertype", "").to_lower() == "energy" and "Water" in card.metadata.get("name", ""):
					water_energy = card
					break
			if water_energy == null:
				break
			# Find best Water Pokemon target
			var best_target: card_object = null
			var best_unmet = 999
			var all_pokemon = get_all_cpu_field_pokemon()
			for p in all_pokemon:
				if "Water" not in p.metadata.get("types", []):
					continue
				for attack in p.metadata.get("attacks", []):
					var unmet = get_unmet_energy_count(attack, p)
					if unmet > 0 and unmet < best_unmet:
						best_unmet = unmet
						best_target = p
			if best_target == null:
				break
			opponent_hand.erase(water_energy)
			best_target.attached_energies.append(water_energy)
			await show_message("Rain Dance: Attached Water Energy to " + best_target.metadata.get("name", "") + "!")
			refresh_hand_display(true)
			display_active_pokemon_energies(true)
			keep_going = true
	
	# Energy Trans: consolidate Grass Energy to the pokemon that needs it most
	var venusaur = _find_cpu_pokemon_with_power("Energy Trans")
	if venusaur != null and not is_power_blocked_by_status(venusaur):
		# Find pokemon that needs Grass Energy most
		var all_pokemon = get_all_cpu_field_pokemon()
		var best_target: card_object = null
		var best_unmet = 999
		for p in all_pokemon:
			for attack in p.metadata.get("attacks", []):
				var unmet = get_unmet_energy_count(attack, p)
				if unmet > 0 and unmet < best_unmet:
					for req in attack.get("cost", []):
						if req == "Grass":
							best_unmet = unmet
							best_target = p
							break
		if best_target != null:
			# Find a source with spare Grass Energy
			for p in all_pokemon:
				if p == best_target:
					continue
				for e in p.attached_energies.duplicate():
					if "Grass" in get_energy_provided_by_card(e):
						p.attached_energies.erase(e)
						best_target.attached_energies.append(e)
						await show_message("Energy Trans: Moved Grass Energy to " + best_target.metadata.get("name", "") + "!")
						display_active_pokemon_energies(true)
						break
	
	# Damage Swap: move damage off active to bench with most buffer
	var alakazam = _find_cpu_pokemon_with_power("Damage Swap")
	if alakazam != null and not is_power_blocked_by_status(alakazam):
		var active = opponent_active_pokemon
		if active != null:
			var active_damage = int(active.metadata.get("hp", "0")) - active.current_hp
			while active_damage >= 10:
				# Find bench pokemon with most HP buffer
				var best_buffer: card_object = null
				var best_hp = 0
				for bp in opponent_bench:
					var buffer = bp.current_hp - 10
					if buffer > best_hp:
						best_hp = buffer
						best_buffer = bp
				if best_buffer == null or best_hp <= 0:
					break
				active.current_hp += 10
				best_buffer.current_hp -= 10
				active_damage -= 10
			display_hp_circles_above_align(opponent_active_pokemon, true)

# Helper to find a CPU pokemon with a specific power name
func _find_cpu_pokemon_with_power(power_name: String) -> card_object:
	var all_pokemon = get_all_cpu_field_pokemon()
	for p in all_pokemon:
		for ability in p.metadata.get("abilities", []):
			if ability.get("name", "") == power_name:
				return p
	return null

############################################### Section I: MACHAMP STRIKES BACK HOOK #################################################################

# Called after damage is applied to a pokemon - checks for Machamp's Strikes Back
func check_strikes_back(damaged_pokemon: card_object, attacker: card_object, is_damaged_opponent: bool) -> void:
	if damaged_pokemon == null or attacker == null:
		return
	var abilities = damaged_pokemon.metadata.get("abilities", [])
	for ability in abilities:
		if ability.get("name", "") != "Strikes Back":
			continue
		if is_power_blocked_by_status(damaged_pokemon):
			print("STRIKES BACK: Blocked by status on ", damaged_pokemon.metadata.get("name", ""))
			return
		# Deal 10 damage to the attacker, ignoring weakness/resistance
		attacker.current_hp = max(0, attacker.current_hp - 10)
		var attacker_is_opp = not is_damaged_opponent
		display_hp_circles_above_align(attacker, attacker_is_opp)
		# Show floating label for the -10HP on the attacker
		var attacker_label_pos = Vector2(1030, 300) if attacker_is_opp else Vector2(530, 300)
		show_floating_label("-10HP", attacker_label_pos, true)
		await show_message(damaged_pokemon.metadata.get("name", "") + "'s STRIKES BACK dealt 10 damage to " + attacker.metadata.get("name", "") + "!")
		print("STRIKES BACK: 10 damage to ", attacker.metadata.get("name", ""))

############################################### Section J: DOUBLE COLORLESS ENERGY HANDLING ##########################################################

# Check if a card is Double Colorless Energy (Special Energy)
func is_double_colorless_energy(card: card_object) -> bool:
	return card.metadata.get("name", "") == "Double Colorless Energy"

############################################# END TRAINER CARD & POKEMON POWER FUNCTIONS ############################################################
######################################################################################################################################################


#           ########  ####    ##  #######  ##   ##  ########
#              ##     ## ##   ##  ##    ## ##   ##     ##
#              ##     ##  ##  ##  #######  ##   ##     ##
#              ##     ##   ## ##  ##       ##   ##     ##
#           ########  ##    ####  ##       #######     ##
######################################################################################################################################################
########################################################### USER INPUT ON CLICK FUNCTIONS ############################################################

# Card action button is the physical button that appears when in card selection mode, allows attaching energies, playing pokemon and trainer cards
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
		display_active_pokemon_energies()
		return

	player_bench.erase(new_active)
	player_bench.append(player_active_pokemon)

	player_active_pokemon.current_location = "bench"
	new_active.current_location = "active"

	player_retreated_this_turn = true
	retreat_bench_selection_active = false
	selected_card_for_action = null

	hide_selection_mode_display_main()
	await animate_retreat(player_active_pokemon, new_active, retreat_energies_selected, false)

	clear_all_statuses(player_active_pokemon, false)
	player_active_pokemon = new_active
	retreat_energies_selected.clear()

	display_pokemon(false)
	display_active_pokemon_energies()

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
	display_active_pokemon_energies()
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
	display_active_pokemon_energies()

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
			var validation_error = validate_trainer_can_be_played(trainer_to_play, false)
			if validation_error != "":
				await show_message(validation_error)
				return
			hide_selection_mode_display_main()
			await play_trainer_card(trainer_to_play, false)
		
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
			opponent_start_turn_checks()
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
	
	main_buttons_container.get_node("button_main_power").pressed.connect(open_power_menu)
	
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
	
	opponent_setup_pokemon_from_hand()
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

######################################################################################################################################################
########################################### SECTION 10: FUTURE-PROOFING NOTES FOR BASE SET 2 & 3 ####################################################
######################################################################################################################################################
#
# BASE SET 2 CARDS REQUIRING ARCHITECTURAL CONSIDERATION:
#
# - base2-6/22 Mr. Mime (Invisible Wall): Already handled by shielded_damage_threshold system.
#   Just needs effect text to set threshold to 30 when Mr. Mime enters play (passive power).
#
# - base2-11/27 Snorlax (Thick Skinned): New power type — permanent status immunity.
#   Needs a "status_immune" flag on card_object checked in apply_status_effect().
#   Also needs a check that prevents retreat (Snorlax rule), adding a "cannot_retreat_override" flag.
#
# - base2-13/29 Venomoth (Shift): Once-per-turn type change. Needs a "temporary_type" field
#   on card_object (already have temporary_weakness/resistance, add temporary_types).
#   power_used_this_turn flag already supports once-per-turn restriction.
#
# - base2-15/31 Vileplume (Heal): Once-per-turn coin flip heal. Standard active power with
#   power_used_this_turn flag. No architectural changes needed.
#
# - base2-34 Dodrio (Retreat Aid): Passive bench power that reduces active's retreat cost.
#   Needs a hook in get_retreat_cost() to check bench for Retreat Aid powers.
#   Add a "retreat_cost_modifier" check scanning bench pokemon abilities.
#
# - base2-55 Mankey (Peek): Once-per-turn peek at hidden cards. Standard active power.
#   Needs UI to display a single card temporarily. No structural changes.
#
# - base2-64 Poke Ball: Standard trainer (flip coin, search deck if heads). No changes needed.
#
# BASE SET 3 CARDS REQUIRING ARCHITECTURAL CONSIDERATION:
#
# - base3-1/16 Aerodactyl (Prehistoric Power): GLOBAL power that prevents ALL evolution plays.
#   Needs a global check in get_valid_evolution_targets() and perform_evolution() that scans
#   ALL pokemon in play (both sides) for this power before allowing evolution.
#   This is a NEW power trigger type: "global continuous effect".
#
# - base3-3/18 Ditto (Transform): MAJOR architectural consideration. Ditto copies the defending
#   pokemon's entire card (type, HP, attacks, weakness, resistance). Needs a system to
#   dynamically override a card's metadata while it's active. Add a "transform_source" field
#   that, when set, redirects all metadata reads to the source pokemon's metadata.
#
# - base3-4/19 Dragonite (Step In): Once-per-turn bench-to-active swap. Standard active power
#   with bench location requirement. power_used_this_turn handles the once-per-turn limit.
#
# - base3-5/20 Gengar (Curse): Move 1 damage counter between OPPONENT'S pokemon. Similar to
#   Damage Swap but targets opponent. Uses same UI flow. No structural changes needed.
#
# - base3-6/21 Haunter (Transparency): Coin flip to prevent ALL attack effects. New trigger:
#   "before damage application". Needs a hook at the start of damage resolution that checks
#   for Transparency and potentially blocks the entire attack. Similar to is_invincible but
#   coin-flip based and fires before damage calc, not after.
#
# - base3-13/28 Muk (Toxic Gas): CRITICAL — disables ALL other Pokemon Powers globally.
#   Needs a global "powers_disabled" check at the start of EVERY power activation and every
#   passive power check. Scan all pokemon for Toxic Gas before allowing any power.
#   Must be checked in: is_power_blocked_by_status(), open_power_menu(), 
#   cpu_phase_activate_powers(), is_energy_burn_active(), check_strikes_back(), and
#   every other power-related function.
#
# - base3-43 Slowbro (Strange Behavior): Move damage TO Slowbro from your other pokemon.
#   Inverse of Damage Swap. Same UI flow, different direction restriction. No structural changes.
#
# - base3-50 Kabuto (Kabuto Armor): Halve incoming damage. New passive trigger in damage calc.
#   Add a hook in calculate_final_damage() for "halve_damage" powers.
#
# - base3-52 Omanyte (Clairvoyance): See opponent's hand. Needs to override hide_hidden_cards
#   for opponent's hand specifically while Omanyte is in play. Add a "can_see_opponent_hand"
#   check in display_hand_cards_array().
#
# - base3-56 Tentacool (Cowardice): Return to hand voluntarily (like Scoop Up but for self).
#   Standard active power. No structural changes needed.
#
# - base3-58 Mr. Fuji: Shuffle pokemon and attachments into deck. Similar to Scoop Up but
#   goes to deck. No structural changes needed.
#
# - base3-60 Gambler: Coin flip draw. Standard trainer. No changes needed.
# - base3-61 Recycle: Coin flip retrieve from discard to deck. Standard trainer.
# - base3-62 Mysterious Fossil: Bench token — ALREADY HANDLED by bench token system.
#   no_prize_on_ko and is_bench_token flags will be set automatically.
#
# SUMMARY OF REQUIRED ARCHITECTURAL ADDITIONS FOR FUTURE SETS:
# 1. Global power disable check (for Muk's Toxic Gas) - scan field for "disable_all_powers" ability
# 2. Global evolution block check (for Aerodactyl) - scan field for "block_evolution" ability  
# 3. Transform/copy system (for Ditto) - metadata redirection on card_object
# 4. Retreat cost modifier system (for Dodrio) - scan bench for retreat aid powers
# 5. Pre-damage-application hook (for Haunter) - coin flip before any damage resolves
# 6. Half-damage modifier (for Kabuto) - new damage calculation hook
# 7. Hand visibility override (for Omanyte) - conditional face-up display
######################################################################################################################################################
