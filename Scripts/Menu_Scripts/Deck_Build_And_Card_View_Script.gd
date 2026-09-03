extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

var PLAYER_DATA_PATH: String:
	get: return GameState.PLAYER_CURRENT_DATA_PATH
const SET_DICT_PATH        := "res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json"
var OWNED_CARDS_FOLDER: String:
	get: return GameState.OWNED_CARDS_FOLDER
var PLAYER_DECKS_FOLDER: String:
	get: return GameState.PLAYER_DECKS_FOLDER

# ── Chrome geometry (UI overhaul) ────────────────────────────────────────────
# TWEAKABLE. The sidebar keeps its authored x band (1690..1916); only the grid and
# the header furniture are placed from here.
const GRID_X          := 3.0
const GRID_W          := 1678.0
## Zero: the card grid runs edge to edge between the two bars, so the first and
## last rows line up with the header and footer instead of floating inside a
## dark band.
const GRID_INSET_Y    := 0.0
const DECK_NAME_W     := 330.0
const DECK_NAME_H     := 52.0
## 40% down from 54: the arrows were competing with the set name.
const STEPPER_ARROW_W := 32.0
## ISSUE #183: the glyph is doubled (10 -> 20) and set in the bold face — at 10px
## the '<' and '>' were barely visible against the header gradient.
const STEPPER_ARROW_FONT := 20
## ISSUE #183: the button is 10px taller than it is wide.
const STEPPER_ARROW_H := STEPPER_ARROW_W + 10.0
## Deck name, up from the 19px `name` role.
const DECK_NAME_FONT     := 26

# ── Deck viewer contents list ────────────────────────────────────────────────
# TWEAKABLE. Sits in the same right-hand band the sidebar uses.
const VIEWER_LIST_X   := 1690.0
const VIEWER_LIST_W   := 226.0
const VIEWER_LIST_PAD := 10.0
const VIEWER_ROW_H    := 34.0
const VIEWER_ROW_GAP  := 6
## ISSUE #190: horizontal inset inside each contents row, so the card name and its
## count both clear the panel border.
const VIEWER_ROW_PAD  := 8
const STEPPER_NAME_W  := 520.0
const SEARCH_BTN_W    := 300.0

# ── Right sidebar ────────────────────────────────────────────────────────────
# TWEAKABLE. The sidebar keeps the x band the scene authored (1690..1916).
# Top to bottom: energies, composition, then the three deck tools at the bottom.
const SIDE_X          := 1690.0
const SIDE_W          := 226.0
const SIDE_PAD        := 10.0

const ENERGY_PANEL_Y  := 100.0
const ENERGY_PANEL_H  := 252.0
const ENERGY_ICON     := Vector2(66.0, 90.0)
const ENERGY_COL_X    := [1699.0, 1772.0, 1845.0]
const ENERGY_ROW_Y    := [146.0, 246.0]
## Outline behind the per-energy count, so it reads on light card art.
const ENERGY_COUNT_OUTLINE := 7

const COMP_PANEL_Y    := 368.0
const COMP_PANEL_H    := 246.0

## ISSUE #187: the "XX / 60" pill sits UNDER the composition box now, matching its
## width, rather than beside the deck name in the header.
const COUNT_PILL_Y    := COMP_PANEL_Y + COMP_PANEL_H + 14.0
const COUNT_PILL_H    := 44.0
const COMP_ROW_H      := 40.0
const COMP_METER_H    := 10.0
## ISSUE #188: +20% on the sidebar headings and the composition category names
## (the 13.5px small_label role rounds to 14, so these are 17 and 16).
const SIDE_HEADING_FONT := 17
const COMP_ROW_FONT     := 16

## The three deck tools, bottom-aligned so they sit under the composition box.
const TOOL_BTN_H      := 66.0
const TOOL_BTN_GAP    := 10.0
const TOOL_STACK_BOT  := 972.0

## ISSUE #227: SEVEN columns, not nine, with the cards grown to take up the room.
## Sized so seven columns plus CARD_H_SEP still fit GRID_W:
## 7 * 231 + 6 * 10 = 1677, inside 1678. Raising the gap means shrinking this,
## and the height must keep the 177:246 card aspect (231 * 1.3898 = 321).
const CARD_SIZE     := Vector2(231, 321)
## Raised from 2: at 2px the cards read as one solid sheet rather than as a grid
## of separate items.
## Composition rows, in display order, with their headings.
const COMP_ORDER := ["basic", "stage1", "stage2", "trainer", "energy"]
const COMP_LABEL := {
	"basic":   "Basic",
	"stage1":  "Stage 1",
	"stage2":  "Stage 2",
	"trainer": "Trainer",
	"energy":  "Energy",
}

const CARD_H_SEP    := 10
const CARD_V_SEP    := 10

## The "n / N" strip across the bottom of every card cell.
const COUNT_STRIP_H    := 30
const COUNT_STRIP_FONT := 17
const COLUMNS       := 7          # ISSUE #227
const MAX_COPIES    := 4
const DECK_SIZE     := 60

# ─── DEBUG-ONLY DECK RULES ──────────────────────────────────────────────────
# While debug mode is on (DebugMode.is_enabled(), see Debug_Mode.gd) the deck
# builder drops the "exactly 60 cards" and "max 4 per name group" (and per-card
# ownership) save restrictions, so any deck can hold any number of any card —
# invaluable for building a one-card test deck to exercise a single attack.
# In a release build the normal rules always apply.
#
# This used to be a hardcoded `const TESTING_UNLIMITED_DECKS := true`, which
# meant a shipped build had no deck rules at all. The two places that read it
# now call DebugMode.is_enabled() directly: _get_max_for_card() and
# _deck_save_blocker().

# ─── Energy style data ──────────────────────────────────────────────────────
# Each style maps to 6 card IDs in a fixed order: grass, fire, water,
# lightning, psychic, fighting.  The order matters because each set has
# different numbering — we can't just loop through sequentially.

const ENERGY_TYPES := ["grass", "fire", "water", "lightning", "psychic", "fighting"]

# ISSUE #155: the style table lives in Game_State_Script now (GameState.ENERGY_STYLES) so the
# CHT.All_Energy_Styles cheat grants exactly the styles this screen offers. Referenced through the
# autoload rather than copied — two copies would drift the moment a style is added.


# ─── State ───────────────────────────────────────────────────────────────────

# Ordered array of dictionaries: [{set_id, set_name}, ...]
var set_list         : Array = []
# Indices into set_list that are unlocked — used for next/prev wrapping
var unlocked_indices : Array = []
# Current position in unlocked_indices (NOT set_list)
var current_unlock_pos : int = 0

# The player's current deck: card_id → count in deck
var deck_cards       : Dictionary = {}
var total_deck_count : int = 0

# The deck name currently loaded
var current_deck_name : String = ""

# ─── Card metadata cache ────────────────────────────────────────────────────
# Loaded from the set JSON files (e.g. res://Card_Set_Data/base1.json).
# Maps card_id → {name, supertype, subtypes} so we only parse each set once.
var _card_metadata_cache : Dictionary = {}

# Tracks how many copies of each "deck name group" are in the current deck.
# The grouping rules are:
#   - Pokémon: base name (stripping " δ" suffix) → shared 4-copy pool
#   - Pokémon ex: exact name → separate 4-copy pool
#   - Pokémon Star (★/*): ALL stars share a single 1-copy-total pool (key = "__star__")
#   - Trainers / Special Energy: exact name → 4-copy pool each
# Key = group name string, Value = count in deck
var deck_name_counts : Dictionary = {}

# Reference to the load-deck popup so we can free it later
var load_popup       : CanvasLayer = null
# ISSUE #154: ONE styled Yes/No confirm, shared by every destructive action on this screen —
# "Empty the entire deck?" and now "Delete <deck>?". It was a single-purpose popup for the empty
# button; a second hand-rolled copy for delete would have been the third in the codebase (the main
# menu's quit dialog is the same panel again), so it is a helper now. Layer 110 so it stacks ABOVE
# the load popup at 100 — the delete confirm is opened from inside that popup.
var confirm_popup   : CanvasLayer = null
var _confirm_action : Callable    = Callable()

# ISSUE #154 follow-up: the rename box. NOT the confirm popup above — that one is a Yes/No panel
# with no text field, and renaming needs typing. Also layer 110, opened from inside the load popup.
var rename_popup    : CanvasLayer = null
var _rename_edit    : LineEdit    = null

# Snapshot of deck_cards taken after a save or load — used to detect
# whether the player has made any changes.  If the current deck_cards
# matches this snapshot exactly, the save button stays disabled.
var _saved_deck_snapshot : Dictionary = {}
var _saved_deck_name     : String = ""

# The player's current energy style key (e.g. "ex13")
var current_energy_style : String = "Base1"

# Whether the energy style picker overlay is currently visible
var energy_picker_active : bool = false

# Reference to the energy picker Control so we can free it
var energy_picker_overlay : Control = null

# Whether the deck viewer overlay is currently open
var deck_viewer_active  : bool    = false
# The deck viewer overlay Control (always rebuilt on open; freed on close)
var deck_viewer_overlay : Control = null

# Holds references to the 6 energy icon TextureRects from the scene tree,
# keyed by type name: "grass", "fire", "water", "lightning", "psychic", "fighting"
var energy_icons   : Dictionary = {}
# Matching count labels for each energy type
var energy_labels  : Dictionary = {}
# Tweens for the energy icon glow animation, keyed by type name
var energy_tweens  : Dictionary = {}

# Tracks which set is currently being loaded — used to abort a progressive
# load if the player switches sets before the previous one finishes
var _loading_set_id  : String = ""

# ISSUE #32: input-blocking loading overlay shown while a set's card grid builds (every set load,
# including switching sets). show() auto-replaces any existing overlay, so rapid set switches never
# stack two overlays.
var _loading_overlay : MenuLoadingOverlay = MenuLoadingOverlay.new()

# ─── Zoom state ──────────────────────────────────────────────────────────────

# Reference to the zoom overlay (CanvasLayer) so we can remove it on release
var zoom_overlay : CanvasLayer = null
# Whether we're currently in zoom mode
var is_zoomed : bool = false
# ISSUE #13: the preview tracks the mouse live for as long as the zoom key is held. While zoom_held
# is true, _process re-reads the hovered card every frame and re-renders the overlay whenever it
# changes, so the player can hold the key and slide the mouse across the grid to flick through cards
# — and hovering empty space correctly shows nothing. The old design snapshotted the card on
# key-down and cached it in last_zoomed_card, which meant a later press over nothing re-showed a
# stale card (possibly from a different set or menu entirely).
# The key is Shift (UIInput.is_zoom_start / is_zoom_end), not Space — Space is the accept key, and
# the same hold now works in a match, where it has to coexist with Space advancing the message box.
var zoom_held : bool = false
# The card the overlay is currently showing, so _process only rebuilds it when the hover changes
var zoomed_card : TextureRect = null
# ISSUE #98: the CardDetailPanel inside the overlay. Kept so a hover change can re-point the live
# panel at the new card rather than freeing and rebuilding the whole CanvasLayer (which flashed the
# bright UI underneath). The panel draws the card art AND every box of its data — see
# Scripts/Global_Scripts/Card_Detail_Panel.gd.
var detail_panel : CardDetailPanel = null

# RichTextLabel showing the per-set deck breakdown (created in _ready).

# Sidebar panels built in _build_chrome. _comp_rows maps a COMP_ORDER key to its
# { count, meter, name } nodes.
var _comp_rows              : Dictionary = {}
var _comp_panel             : Control = null
var _comp_heading           : Label = null
var _energy_panel_nodes     : Array = []
var _deck_count_chip_holder : Control = null
var _deck_count_chip        : Control = null

# The two chrome bars, kept so the deck viewer can put its own header and footer
# content into them rather than drawing a title UNDER them.
var _header : UIKit.ChromeBar = null
var _footer : UIKit.ChromeBar = null
# Everything the viewer added to those bars, torn down when it closes.
var _viewer_chrome : Array = []

# ─── Card search state ───────────────────────────────────────────────────────

# The search / filter screen. Alive but HIDDEN while its results are on display, so reopening it
# restores the filters that produced them; freed when the search is cleared. Use
# _search_screen_open() rather than a null check to ask whether it is actually on screen.
var search_overlay : CardSearchOverlay = null

# RESET on the filter screen drops the active search immediately, but defers the grid redraw until
# the screen closes — rebuilding underneath it would flash the shared loading overlay over the top.
# This marks that debt. See _on_search_reset().
var _search_grid_stale : bool = false

# True once a search has been run and the grid is showing results instead of a single set.
# While true the set name and the < > set-switch buttons stay hidden.
var search_active : bool = false

# The matched cards, as the same {card_id, owned} dictionaries the per-set grid is built from
var search_results : Array = []

# Which set's cards are currently being progressively added to the grid in search mode — the
# same abort guard _display_current_set uses, so clearing a search mid-load stops the old build
var _search_load_token : int = 0

# How many result cards are added to the grid per frame. A full-collection search can return
# ~2,800 cards, and one-per-frame (what the single-set view uses) would take almost a minute;
# a whole row per frame keeps it progressive but finishes in a few seconds.
const SEARCH_LOAD_BATCH := 9

# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid             : GridContainer = $deck_grid_container
@onready var save_btn         : Button        = $deck_save_button
@onready var cancel_btn       : Button        = $deck_cancel_button
@onready var empty_btn        : Button        = $empty_deck_button
@onready var load_btn         : Button        = $load_deck_button
@onready var next_btn         : Button        = $next_set
@onready var prev_btn         : Button        = $previous_set
@onready var set_label        : Label         = $set_name_label
@onready var deck_name_edit   : LineEdit      = $deck_name
@onready var deck_count_label : Label         = $deck_count_label

# Energy icon TextureRects in the scene — these show the current style's images
@onready var grass_energy_icon     : TextureRect = $"ENERGY SECTION"/"ENERGY ICONS"/grass_energy_icon
@onready var fire_energy_icon      : TextureRect = $"ENERGY SECTION"/"ENERGY ICONS"/fire_energy_icon
@onready var water_energy_icon     : TextureRect = $"ENERGY SECTION"/"ENERGY ICONS"/water_energy_icon
@onready var lightning_energy_icon : TextureRect = $"ENERGY SECTION"/"ENERGY ICONS"/lightning_energy_icon
@onready var psychic_energy_icon   : TextureRect = $"ENERGY SECTION"/"ENERGY ICONS"/psychic_energy_icon
@onready var fighting_energy_icon  : TextureRect = $"ENERGY SECTION"/"ENERGY ICONS"/fighting_energy_icon

# Count labels overlaid on top of each energy icon
@onready var grass_energy_count     : Label = $"ENERGY SECTION"/"ENERGY LABELS"/grass_energy_count_label
@onready var fire_energy_count      : Label = $"ENERGY SECTION"/"ENERGY LABELS"/fire_energy_count_label
@onready var water_energy_count     : Label = $"ENERGY SECTION"/"ENERGY LABELS"/water_energy_count_label
@onready var lightning_energy_count : Label = $"ENERGY SECTION"/"ENERGY LABELS"/lightning_energy_count_label
@onready var psychic_energy_count   : Label = $"ENERGY SECTION"/"ENERGY LABELS"/psychic_energy_count_label
@onready var fighting_energy_count  : Label = $"ENERGY SECTION"/"ENERGY LABELS"/fighting_energy_count_label

# The button that opens the energy style picker overlay
@onready var change_energy_btn : Button = $"ENERGY SECTION"/change_energy_style_button
# The button that opens the deck viewer overlay
@onready var view_deck_btn     : Button = $view_deck_button
# Opens the card search screen — always reads "SEARCH", and reopens with the previous filters
# still set when pressed while results are on display
@onready var search_btn        : Button = $search_button

# ISSUE #148: what the set-name label reads while a search is on screen. The label used to be
# hidden outright alongside the < > set-switch buttons; it now stays up carrying this banner, so
# the player can see at a glance why the grid is not showing a single set. The BUTTONS stay hidden
# — there is no set to step through in results mode.
const SEARCH_MODE_LABEL := "SEARCH MODE ACTIVE"

# ISSUE #141: the deck screen and the search screen use DIFFERENT backdrops.
#   browsing  -> background_scroller + top_and_right_border   (the ~300px right-hand card banner)
#   filtering -> filter_background   + filter_border          (full width, no right banner)
# The filter pair is authored hidden in the scene; _set_filter_chrome() is the ONLY thing that
# swaps between them, so the two can never both be up. Losing the right banner is what frees the
# ~460px the filter rows now spread into — see CardSearchOverlay's geometry block (ISSUE #142).
@onready var background_scroller  : TextureRect = $BACKGROUND/background_scroller
@onready var top_and_right_border : TextureRect = $BACKGROUND/top_and_right_border
@onready var filter_background    : TextureRect = $BACKGROUND/filter_background
@onready var filter_border        : TextureRect = $BACKGROUND/filter_border

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# Start background music — loops until scene changes
	SoundManagerScript.play_bgm(SoundManagerScript.BGM_COIN_MODE, true)
	
	# Load data sources
	_load_set_dictionary()
	var last_set_id := _load_player_data()    # returns last_set_loaded string
	_build_unlocked_indices()
	_find_starting_set(last_set_id)

	# Wire up button signals
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	empty_btn.pressed.connect(_on_empty_deck_pressed)
	load_btn.pressed.connect(_on_load_deck_pressed)
	next_btn.pressed.connect(_on_next_set)
	prev_btn.pressed.connect(_on_prev_set)
	change_energy_btn.pressed.connect(_on_change_energy_style_pressed)
	view_deck_btn.pressed.connect(_on_view_deck_pressed)
	search_btn.pressed.connect(_on_search_pressed)

	# Limit deck name to 20 characters — LineEdit.max_length natively
	# blocks further typing once the limit is reached
	deck_name_edit.max_length = 25
	
	# Re-evaluate save button whenever the name is typed or cleared
	deck_name_edit.text_changed.connect(_on_deck_name_changed)

	# Wrap the grid in a scroll container so large sets can scroll
	# -- Energy icon setup --
	# Build the convenience dictionaries that map type name -> node.
	# This lets the rest of the code work with energy types by string
	# name ("grass", "fire", etc.) instead of individual variable names.
	energy_icons = {
		"grass": grass_energy_icon, "fire": fire_energy_icon,
		"water": water_energy_icon, "lightning": lightning_energy_icon,
		"psychic": psychic_energy_icon, "fighting": fighting_energy_icon,
	}
	energy_labels = {
		"grass": grass_energy_count, "fire": fire_energy_count,
		"water": water_energy_count, "lightning": lightning_energy_count,
		"psychic": psychic_energy_count, "fighting": fighting_energy_count,
	}

	_build_chrome()
	_wrap_grid_in_scroll_container()

	# Load the player's current deck
	_load_deck(current_deck_name)


	# Load the saved energy style from player_data.json and update the icons
	_load_energy_style()
	_update_energy_icons()

	# Wire up click handling on each energy icon.  gui_input is the signal
	# Godot fires on any Control when the mouse interacts with it.
	# We set mouse_filter to STOP so the icon consumes the click rather
	# than letting it pass through to nodes behind it.
	for energy_type in ENERGY_TYPES:
		var icon : TextureRect = energy_icons[energy_type]
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.gui_input.connect(_on_energy_icon_gui_input.bind(energy_type))

	# Refresh energy icon labels and animations from deck state
	_refresh_energy_icons_from_deck()

	# Initial UI state — snapshot the deck so dirty-tracking starts clean
	_snapshot_deck_state()
	_update_deck_count_label()
	_refresh_save_button()
	_update_composition_panel()

	# Display the starting set
	await get_tree().process_frame
	_display_current_set()


## Swaps the old bordered chrome for the Spectrum Night bars and rearranges this
## screen's furniture into them.
##
## The deck builder already had the layout the design asks for — card grid left,
## a tall sidebar right — so this is a chrome swap plus one move: Save and Cancel
## come OUT of the sidebar and onto the slim footer, which is what frees the
## sidebar's bottom for the deck tools.
func _build_chrome() -> void:
	var bars := UIKit.convert_legacy_screen(self, "")
	_header = bars["header"]
	_footer = bars["footer"]

	# -- Header left: deck name field, rename hint, then the count chip --
	var name_holder: Control = bars["header"].left

	# ISSUE #187: a "Name:" label to the LEFT of the field. The slot is an
	# HBoxContainer, so adding the label first is what shifts the field right.
	var name_tag := Label.new()
	UIKit.set_label(name_tag, "small_label", "Name:", "chrome_fg")
	name_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_holder.add_child(name_tag)

	deck_name_edit.get_parent().remove_child(deck_name_edit)
	deck_name_edit.set_anchors_preset(Control.PRESET_TOP_LEFT)
	deck_name_edit.offset_left = 0.0
	deck_name_edit.offset_top = 0.0
	deck_name_edit.offset_right = 0.0
	deck_name_edit.offset_bottom = 0.0
	deck_name_edit.custom_minimum_size = Vector2(DECK_NAME_W, DECK_NAME_H)
	deck_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	deck_name_edit.theme = null
	# White, not the inherited muted field colour - the deck name is the loudest
	# thing in the header after the set.
	deck_name_edit.add_theme_color_override("font_color", Color.WHITE)
	deck_name_edit.add_theme_font_override("font", UITheme.font("name"))
	deck_name_edit.add_theme_font_size_override("font_size", DECK_NAME_FONT)
	name_holder.add_child(deck_name_edit)

	# ISSUE #187: the count pill is a SIDEBAR element now — see _build_count_pill,
	# called from _build_composition_panel so it lands under that box.
	deck_count_label.visible = false

	# -- Header centre: the set stepper --
	UIKit.adopt_button(prev_btn, bars["header"].centre, "secondary", false)
	UIKit.adopt_label(set_label, bars["header"].centre)
	UIKit.adopt_button(next_btn, bars["header"].centre, "secondary", false)
	prev_btn.text = "<"
	next_btn.text = ">"
	for arrow in [prev_btn, next_btn]:
		# ISSUE #183: bigger, bolder glyph in a slightly taller button.
		arrow.custom_minimum_size = Vector2(STEPPER_ARROW_W, STEPPER_ARROW_H)
		arrow.add_theme_font_size_override("font_size", STEPPER_ARROW_FONT)
		arrow.add_theme_font_override("font", UITheme.font_at(UITheme.FONT_UI_BOLD))
	set_label.custom_minimum_size.x = STEPPER_NAME_W

	# -- Header right: search & filter --
	UIKit.adopt_button(search_btn, bars["header"].right, "primary", false)
	search_btn.custom_minimum_size.x = SEARCH_BTN_W
	# The scene bakes a literal newline into this label ("SEARCH &\nFILTER"), which
	# is what made the button two lines tall and burst the header. Set it fresh.
	search_btn.text = "Search & filter"
	UIKit.style_button(search_btn, "primary")

	# -- Footer: Cancel then Save --
	UIKit.adopt_button(cancel_btn, bars["footer"].centre, "secondary")
	UIKit.adopt_button(save_btn, bars["footer"].centre, "primary")

	# -- Sidebar --
	_build_energy_panel()
	_build_composition_panel()

	# The three deck tools, bottom-aligned under the composition box.
	var tools: Array = [view_deck_btn, load_btn, empty_btn]
	for i in tools.size():
		var b: Button = tools[i]
		b.theme = null
		# ISSUE #185: the scene left a font_size override on "View deck" only, so
		# it drew larger than Load and Empty sitting under it. Drop every override
		# here and let the button role decide.
		b.remove_theme_font_size_override("font_size")
		b.remove_theme_font_override("font")
		# Emptying the deck throws work away - the only destructive act here.
		UIKit.style_button(b, "danger" if b == empty_btn else "secondary")
		var bottom: float = TOOL_STACK_BOT - float(tools.size() - 1 - i) * (TOOL_BTN_H + TOOL_BTN_GAP)
		b.set_anchors_preset(Control.PRESET_TOP_LEFT)
		b.offset_left = SIDE_X
		b.offset_right = SIDE_X + SIDE_W
		b.offset_top = bottom - TOOL_BTN_H
		b.offset_bottom = bottom

	# Energy styles are not granted until phase 3 (ecard era), so this button has
	# nothing to offer yet. HIDDEN, not deleted - the picker behind it is finished
	# and works; only the entry point is withheld.
	# Deliberately NOT in _set_ui_visibility's toggle list — it used to be, so
	# closing the deck viewer showed the old Kenney button again.
	change_energy_btn.visible = false

	grid.position = Vector2(GRID_X, UIKit.CONTENT_TOP + GRID_INSET_Y)
	grid.size = Vector2(GRID_W, UIKit.CONTENT_H - GRID_INSET_Y * 2.0)


## The "energies in deck" box. Keeps the real energy card art the screen has
## always used - the mockup's flat colour tiles lose which STYLE of energy the
## deck is built from - and just puts it in a panel with a heading.
func _build_energy_panel() -> void:
	var panel := UIKit.make_panel()
	panel.position = Vector2(SIDE_X, ENERGY_PANEL_Y)
	panel.size = Vector2(SIDE_W, ENERGY_PANEL_H)
	panel.custom_minimum_size = panel.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var heading := Label.new()
	# ISSUE #188: +20% on the panel headings. ISSUE #189: headings are centred.
	UIKit.set_label(heading, "small_label", "Energies in deck", "field_mute",
		SIDE_HEADING_FONT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.position = Vector2(SIDE_X + SIDE_PAD, ENERGY_PANEL_Y + SIDE_PAD)
	heading.size = Vector2(SIDE_W - SIDE_PAD * 2.0, 22.0)
	add_child(heading)
	_energy_panel_nodes = [panel, heading]

	# The icons and their counts are scene nodes; only their geometry moves, and
	# they must stay ABOVE the panel, so the panel is added first.
	for i in ENERGY_TYPES.size():
		var t: String = ENERGY_TYPES[i]
		var icon: TextureRect = energy_icons[t]
		var lbl: Label = energy_labels[t]
		var x: float = ENERGY_COL_X[i % 3]
		var y: float = ENERGY_ROW_Y[i / 3]
		# REPARENT FIRST. Both nodes hang off "ENERGY SECTION", a Control the scene
		# parks at (-2, -232); an absolute position set on a child of that lands
		# 232px above the screen. Moving them to the root makes the sidebar
		# coordinates mean what they say.
		for n in [icon, lbl]:
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			add_child(n)
		icon.position = Vector2(x, y)
		icon.size = ENERGY_ICON
		icon.custom_minimum_size = ENERGY_ICON
		lbl.theme = null
		UIKit.style_label(lbl, "title", "field_fg")
		# The count sits ON the card art, which runs from near-white to bright
		# yellow, so plain white digits disappeared into it. An outline is the one
		# place on this screen that earns one back — style_label strips the
		# Kenney-era outlines precisely because they were decoration, and this is
		# not: without it the number is unreadable on three of the six energies.
		lbl.add_theme_constant_override("outline_size", ENERGY_COUNT_OUTLINE)
		lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		lbl.position = Vector2(x, y + ENERGY_ICON.y * 0.22)
		lbl.size = Vector2(ENERGY_ICON.x, ENERGY_ICON.y * 0.4)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## The composition box: how the sixty cards break down by kind.
##
## REPLACES the old per-SET colour breakdown ("Base 7 7 16 / Fossil 2"), which
## answered a question nobody asks while building - which sets the cards came
## from - and answered it in nine hard-to-read colours. What matters while
## building is whether the deck has enough Basics to open with.
func _build_composition_panel() -> void:
	var panel := UIKit.make_panel()
	panel.position = Vector2(SIDE_X, COMP_PANEL_Y)
	panel.size = Vector2(SIDE_W, COMP_PANEL_H)
	panel.custom_minimum_size = panel.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_comp_panel = panel

	var heading := Label.new()
	# ISSUE #188 / #189: +20% and centred, matching the energies panel above it.
	UIKit.set_label(heading, "small_label", "Composition", "field_mute",
		SIDE_HEADING_FONT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_comp_heading = heading
	heading.position = Vector2(SIDE_X + SIDE_PAD, COMP_PANEL_Y + SIDE_PAD)
	heading.size = Vector2(SIDE_W - SIDE_PAD * 2.0, 22.0)
	add_child(heading)

	_comp_rows.clear()
	var y: float = COMP_PANEL_Y + SIDE_PAD + 28.0
	for key in COMP_ORDER:
		var name_lbl := Label.new()
		# ISSUE #188: +20% on the category names too.
		UIKit.set_label(name_lbl, "small_label", String(COMP_LABEL[key]), "field_fg",
			COMP_ROW_FONT)
		name_lbl.position = Vector2(SIDE_X + SIDE_PAD, y)
		name_lbl.size = Vector2(SIDE_W - SIDE_PAD * 2.0 - 44.0, 18.0)
		add_child(name_lbl)

		var count_lbl := Label.new()
		UIKit.set_label(count_lbl, "hp", "0", "accent")
		count_lbl.position = Vector2(SIDE_X + SIDE_W - SIDE_PAD - 44.0, y - 3.0)
		count_lbl.size = Vector2(44.0, 20.0)
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(count_lbl)

		# The meter is rebuilt on every refresh rather than resized, because
		# UIKit.make_meter bakes its fill width at construction time.
		var meter_holder := Control.new()
		meter_holder.position = Vector2(SIDE_X + SIDE_PAD, y + 21.0)
		meter_holder.size = Vector2(SIDE_W - SIDE_PAD * 2.0, COMP_METER_H)
		meter_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(meter_holder)

		_comp_rows[key] = { "count": count_lbl, "meter": meter_holder, "name": name_lbl }
		y += COMP_ROW_H

	_build_count_pill()


## ISSUE #187: the deck-total pill, directly under the composition box and the
## same width as it. It used to be a chip in the header beside the deck name,
## where it competed with the set stepper for the eye.
##
## The holder is a plain Control the chip is centred in, so _refresh_deck_count_chip
## can free and rebuild the chip without disturbing the layout.
func _build_count_pill() -> void:
	var holder := Control.new()
	holder.position = Vector2(SIDE_X, COUNT_PILL_Y)
	holder.size = Vector2(SIDE_W, COUNT_PILL_H)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_deck_count_chip_holder = holder
	_refresh_deck_count_chip()


## Recomputes the composition box from the current deck.
func _update_composition_panel() -> void:
	if _comp_rows.is_empty():
		return
	var counts := _deck_composition()
	var meter_w: float = SIDE_W - SIDE_PAD * 2.0
	for key in COMP_ORDER:
		var row: Dictionary = _comp_rows[key]
		var n: int = int(counts.get(key, 0))
		(row["count"] as Label).text = str(n)
		var holder: Control = row["meter"]
		for c in holder.get_children():
			c.queue_free()
		# Measured against the DECK SIZE, not against the largest row: the player
		# is judging "how much of my sixty is this", not comparing bars.
		holder.add_child(UIKit.make_meter(float(n), float(DECK_SIZE), meter_w))


## Splits the deck into Basic / Stage 1 / Stage 2 / Trainer / Energy.
## Baby Pokemon fold into Basic - they are Basics for deck-building purposes.
func _deck_composition() -> Dictionary:
	var out := { "basic": 0, "stage1": 0, "stage2": 0, "trainer": 0, "energy": 0 }
	for card_id in deck_cards:
		var n: int = deck_cards[card_id]
		var meta = _get_card_meta(card_id)
		if meta == null:
			continue
		var supertype := String(meta.get("supertype", ""))
		if supertype == "Trainer":
			out["trainer"] += n
			continue
		if supertype == "Energy":
			out["energy"] += n
			continue
		var subs: Array = meta.get("subtypes", [])
		if "Stage 2" in subs:
			out["stage2"] += n
		elif "Stage 1" in subs:
			out["stage1"] += n
		else:
			out["basic"] += n
	return out


## Rebuilds the deck-count chip in the header.
func _refresh_deck_count_chip() -> void:
	if _deck_count_chip_holder == null or not is_instance_valid(_deck_count_chip_holder):
		return
	if _deck_count_chip != null and is_instance_valid(_deck_count_chip):
		_deck_count_chip.queue_free()
	_deck_count_chip = UIKit.make_chip(
		"%d / %d" % [total_deck_count, DECK_SIZE], "on_field")
	# ISSUE #187: the pill spans the sidebar so it lines up with the composition
	# box above it rather than shrinking to its digits.
	_deck_count_chip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deck_count_chip.offset_left = 0.0
	_deck_count_chip.offset_top = 0.0
	_deck_count_chip.offset_right = 0.0
	_deck_count_chip.offset_bottom = 0.0
	_deck_count_chip_holder.add_child(_deck_count_chip)



# ─── Data loading ────────────────────────────────────────────────────────────

## Reads set_dictionary.json into set_list.
## Each entry is {set_id: "base1", set_name: "Base"}.
func _load_set_dictionary() -> void:
	var file := FileAccess.open(SET_DICT_PATH, FileAccess.READ)
	if file == null:
		push_error("DeckBuild: cannot open " + SET_DICT_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data is Dictionary and data.has("set_list"):
		set_list = data["set_list"]


## Reads player_data.json — returns the last_set_loaded value.
## Also stores the current deck name.
func _load_player_data() -> String:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("DeckBuild: cannot open " + PLAYER_DATA_PATH)
		return "base1"
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if not data is Dictionary:
		return "base1"

	current_deck_name = data.get("deck", "")
	deck_name_edit.text = current_deck_name

	return data.get("last_set_loaded", "base1")


## Builds unlocked_indices — an array of indices into set_list whose
## set is unlocked.  Sets are always unlocked in order, so we scan
## until we hit the first locked set then stop.
func _build_unlocked_indices() -> void:
	unlocked_indices.clear()
	for i in range(set_list.size()):
		var set_id : String = set_list[i]["set_id"]
		var owned_path := OWNED_CARDS_FOLDER + set_id + "_player_owned_cards.json"
		var file := FileAccess.open(owned_path, FileAccess.READ)
		if file == null:
			continue
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data is Dictionary and data.get("set_unlocked", false):
			unlocked_indices.append(i)
	_update_set_nav_buttons()


func _update_set_nav_buttons() -> void:
	var enabled := unlocked_indices.size() > 1
	next_btn.disabled = !enabled
	prev_btn.disabled = !enabled
	var grey_sb := StyleBoxFlat.new()
	grey_sb.bg_color = Color(0.67, 0.67, 0.67, 1.0)
	grey_sb.set_corner_radius_all(UITheme.mi("btn_radius"))   # ISSUE #184
	grey_sb.anti_aliasing = true
	grey_sb.content_margin_left   = 8.0
	grey_sb.content_margin_right  = 8.0
	grey_sb.content_margin_top    = 6.0
	grey_sb.content_margin_bottom = 6.0
	for btn: Button in [next_btn, prev_btn]:
		btn.add_theme_stylebox_override("disabled", grey_sb)
		btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.35, 0.35, 1.0))


## Finds the position in unlocked_indices that matches the given set_id.
## Falls back to position 0 if not found.
func _find_starting_set(set_id: String) -> void:
	for i in range(unlocked_indices.size()):
		var idx = unlocked_indices[i]
		if set_list[idx]["set_id"] == set_id:
			current_unlock_pos = i
			return
	current_unlock_pos = 0


## Loads a deck file from the playerdecks folder.
## Populates deck_cards dictionary and total_deck_count.
func _load_deck(deck_name: String) -> void:
	deck_cards.clear()
	total_deck_count = 0

	if deck_name == "":
		return

	var path := PLAYER_DECKS_FOLDER + deck_name + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DeckBuild: cannot open deck " + path)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if not data is Array:
		return

	for entry in data:
		if entry is Dictionary and entry.has("id") and entry.has("count"):
			var card_id : String = entry["id"]
			var count   : int    = int(entry["count"])
			deck_cards[card_id] = count
			total_deck_count += count

	# Build the name-group tracking from the loaded deck
	_rebuild_deck_name_counts()


## Loads the player_owned_cards JSON for a given set_id.
## Returns the "owned_cards" array, or an empty array on failure.
func _load_owned_cards_for_set(set_id: String) -> Array:
	var path := OWNED_CARDS_FOLDER + set_id + "_player_owned_cards.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DeckBuild: cannot open " + path)
		return []
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data is Dictionary and data.has("owned_cards"):
		return data["owned_cards"]
	return []


# ─── Card metadata & name-based copy limits ─────────────────────────────────

const CARD_IMAGES_FOLDER := "res://Card_Set_Data/"

## Loads the set's JSON metadata file (e.g. res://Card_Set_Data/base1.json)
## and caches every card's name/supertype/subtypes.  Only loads each set once.
func _ensure_set_metadata_loaded(set_id: String) -> void:
	# If we've already loaded this set, skip
	if _card_metadata_cache.has(set_id + "-loaded"):
		return

	var path := CARD_IMAGES_FOLDER + set_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DeckBuild: cannot open card metadata " + path)
		_card_metadata_cache[set_id + "-loaded"] = true
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data is Array:
		for card in data:
			var cid : String = card.get("id", "")
			if cid != "":
				# ISSUE #140: the ability list is boiled down to two booleans here rather than
				# cached whole — the search only ever asks "does it have one", and keeping 3,340
				# full ability arrays in memory for that would be wasteful. Matched on a lowercased
				# SUBSTRING because the type strings carry an accent ("Poké-Body") and the older
				# Base-through-Neo wording is "Pokémon Power", which belongs with Power not Body.
				var has_power := false
				var has_body  := false
				for ability in card.get("abilities", []):
					var atype := str(ability.get("type", "")).to_lower()
					if "body" in atype:
						has_body = true
					elif "power" in atype:
						has_power = true
				_card_metadata_cache[cid] = {
					"name": card.get("name", ""),
					"supertype": card.get("supertype", ""),
					"subtypes": card.get("subtypes", []),
					"types": card.get("types", []),
					"evolvesFrom": card.get("evolvesFrom", ""),
					"rarity": card.get("rarity", ""),
					"artist": card.get("artist", ""),   # ISSUE #143
					"has_power": has_power,             # ISSUE #140
					"has_body": has_body,               # ISSUE #140
				}

	_card_metadata_cache[set_id + "-loaded"] = true


## Returns the cached metadata dict for a card_id, or null if not found.
## Automatically loads the set's metadata if it hasn't been loaded yet.
func _get_card_meta(card_id: String) -> Variant:
	if _card_metadata_cache.has(card_id):
		return _card_metadata_cache[card_id]

	# Try loading the set
	var card_set := card_id.split("-")[0]
	_ensure_set_metadata_loaded(card_set)

	if _card_metadata_cache.has(card_id):
		return _card_metadata_cache[card_id]
	return null


## Returns the "name group key" for a card — this is the string used to
## track how many copies of a name are in the deck.
##
## Rules:
##   - Pokémon with "ex" in subtypes → exact card name (separate pool)
##   - Pokémon with star/★ in name  → "__star__" (all stars share 1 slot)
##   - Pokémon with "Delta Species" in subtypes → base name without " δ"
##     (shares pool with the non-delta version)
##   - All other Pokémon → card name as-is
##   - Trainers / Special Energy → exact card name
func _get_name_group(card_id: String) -> String:
	var meta = _get_card_meta(card_id)
	if meta == null:
		return card_id   # fallback to card_id if no metadata

	var card_name : String = meta["name"]
	var supertype : String = meta["supertype"]
	var subtypes  : Array  = meta["subtypes"]

	# Trainers and Energy use exact name
	if supertype != "Pokémon":
		return card_name

	# Star cards: name contains "★" or ends with "Star"
	# All star cards share a single pool with 1 total allowed
	if "★" in card_name or card_name.ends_with(" Star"):
		return "__star__"

	# EX Pokémon: "ex" in subtypes → separate name pool
	# (the card name itself usually includes "ex" e.g. "Pikachu ex")
	for st in subtypes:
		if st.to_lower() == "ex":
			return card_name

	# Delta Species: strip the " δ" suffix so it shares the pool
	# with the regular version of that Pokémon
	var group_name := card_name
	if group_name.ends_with(" δ"):
		group_name = group_name.substr(0, group_name.length() - 2)

	return group_name


## Returns the maximum number of copies of this specific card that can
## be added to the deck, considering the name-based group limits.
## Returns -1 for unlimited (won't happen for non-energy cards).
func _get_max_for_card(card_id: String, owned: int) -> int:
	# DEBUG ONLY: ignore group/ownership limits so any number of any card is allowed.
	if DebugMode.is_enabled():
		return DECK_SIZE
	var meta = _get_card_meta(card_id)
	if meta == null:
		return mini(owned, MAX_COPIES)

	var card_name : String = meta["name"]
	var group_key := _get_name_group(card_id)

	# Star cards: 1 total across ALL star cards in the deck
	if group_key == "__star__":
		var star_total : int = deck_name_counts.get("__star__", 0)
		var this_card_in_deck : int = deck_cards.get(card_id, 0)
		# How many more star cards can be added total?
		var star_remaining := 1 - star_total
		# This specific card can add up to star_remaining more copies
		# (but also limited by ownership and can't exceed 1 of this specific card)
		return mini(owned, this_card_in_deck + maxi(star_remaining, 0))

	# Everything else: 4 copies per name group
	var group_total : int = deck_name_counts.get(group_key, 0)
	var this_card_in_deck : int = deck_cards.get(card_id, 0)
	# How many more of this name group can be added?
	var group_remaining := MAX_COPIES - group_total
	# This specific card can add up to group_remaining more
	return mini(owned, this_card_in_deck + maxi(group_remaining, 0))


## Rebuilds deck_name_counts from scratch based on the current deck_cards.
## Call this after loading a deck or making bulk changes (empty, load, etc.).
func _rebuild_deck_name_counts() -> void:
	deck_name_counts.clear()
	for card_id in deck_cards:
		var count : int = deck_cards[card_id]
		var group_key := _get_name_group(card_id)
		deck_name_counts[group_key] = deck_name_counts.get(group_key, 0) + count


## Detects which energy style the current deck uses by checking if any
## of the deck's card IDs match a known energy style's card IDs.
## Returns the style name (e.g. "Base1", "ex13") or "" if none found.
func _detect_energy_style_from_deck() -> String:
	for style_name in GameState.ENERGY_STYLES.keys():
		var card_ids : Array = GameState.ENERGY_STYLES[style_name]
		for cid in card_ids:
			if deck_cards.has(cid):
				return style_name
	return ""


## Takes a snapshot of the current deck state.  Call after saving or
## loading a deck.  _is_deck_dirty() compares the live state against
## this snapshot to decide whether the save button should be enabled.
func _snapshot_deck_state() -> void:
	_saved_deck_snapshot = deck_cards.duplicate()
	_saved_deck_name = deck_name_edit.text.strip_edges()


## Returns true if the deck has changed since the last snapshot.
## Checks both the card contents and the deck name field.
func _is_deck_dirty() -> bool:
	# Name changed?
	if deck_name_edit.text.strip_edges() != _saved_deck_name:
		return true
	# Different number of unique cards?
	if deck_cards.size() != _saved_deck_snapshot.size():
		return true
	# Any card count changed or new card added?
	for card_id in deck_cards:
		if not _saved_deck_snapshot.has(card_id):
			return true
		if deck_cards[card_id] != _saved_deck_snapshot[card_id]:
			return true
	return false


# ─── Energy style management ────────────────────────────────────────────────

## Reads the energy_style field from player_data.json and stores it.
## Falls back to "Base1" if the field is missing.
func _load_energy_style() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary:
		current_energy_style = data.get("energy_style", "Base1")


## ISSUE #274: Large first, Small as a failsafe. Every card should have a large
## image; a missing one degrades to the shrunken copy rather than to a blank cell.
## Mirrors MapManager._load_card_image_with_fallback.
func _load_card_texture_with_fallback(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex != null:
			return tex
	if "/Large/" in path:
		var fallback: String = path.replace("/Large/", "/Small/")
		if ResourceLoader.exists(fallback):
			return load(fallback)
	return null


## Updates the 6 energy icon TextureRects to show images from the
## currently selected energy style.  Each icon loads the "Small" version
## of its card image from the Image_Assets/Card_Image_Library folder.
func _update_energy_icons() -> void:
	if not GameState.ENERGY_STYLES.has(current_energy_style):
		current_energy_style = "Base1"

	var card_ids : Array = GameState.ENERGY_STYLES[current_energy_style]
	# card_ids is ordered: grass, fire, water, lightning, psychic, fighting
	# ENERGY_TYPES is in the same order, so index i lines up
	for i in range(ENERGY_TYPES.size()):
		var energy_type : String = ENERGY_TYPES[i]
		var card_id     : String = card_ids[i]
		var card_set := card_id.split("-")[0]
		# ISSUE #274: Large here too - these six icons are the same card images the
		# grid draws, and a mixed-resolution screen reads as an inconsistency.
		var image_path := "res://Image_Assets/Card_Image_Library/" + card_set + "/Large/" + card_id + ".png"
		var tex = _load_card_texture_with_fallback(image_path)
		if tex != null:
			energy_icons[energy_type].texture = tex


## Refreshes the count labels and glow animations on all 6 energy icons
## based on the current deck contents.  Called at startup and whenever the
## deck changes (load, empty, etc.).
func _refresh_energy_icons_from_deck() -> void:
	if not GameState.ENERGY_STYLES.has(current_energy_style):
		return

	var card_ids : Array = GameState.ENERGY_STYLES[current_energy_style]
	for i in range(ENERGY_TYPES.size()):
		var energy_type : String = ENERGY_TYPES[i]
		var card_id     : String = card_ids[i]
		var in_deck     : int    = deck_cards.get(card_id, 0)
		var label       : Label  = energy_labels[energy_type]
		label.text = str(in_deck)

		var icon : TextureRect = energy_icons[energy_type]
		if in_deck > 0:
			_apply_energy_icon_animation(energy_type, icon)
		else:
			_remove_energy_icon_animation(energy_type, icon)


## Starts the glow + grow loop on an energy icon (same visual feel as
## the main grid cards).  The icon's pivot_offset must be set to its
## centre so it scales from the middle rather than the top-left corner.
func _apply_energy_icon_animation(energy_type: String, icon: TextureRect) -> void:
	# Kill any existing tween first to avoid stacking animations
	if energy_tweens.has(energy_type) and energy_tweens[energy_type] != null:
		energy_tweens[energy_type].kill()

	icon.pivot_offset = icon.size / 2.0
	icon.modulate = Color.WHITE

	var tw := create_tween()
	tw.set_loops()
	energy_tweens[energy_type] = tw

	tw.tween_property(icon, "modulate", Color.WHITE * 1.4, 0.5)
	tw.parallel().tween_property(icon, "scale", Vector2(1.06, 1.06), 0.5)
	tw.tween_property(icon, "modulate", Color.WHITE * 1.0, 0.5)
	tw.parallel().tween_property(icon, "scale", Vector2(1.0, 1.0), 0.5)


## Stops the glow animation and resets an energy icon to normal.
func _remove_energy_icon_animation(energy_type: String, icon: TextureRect) -> void:
	if energy_tweens.has(energy_type) and energy_tweens[energy_type] != null:
		energy_tweens[energy_type].kill()
		energy_tweens[energy_type] = null
	icon.modulate = Color.WHITE
	icon.scale = Vector2(1.0, 1.0)


## Handles left/right click on an energy icon.
## Left click  = add one of that energy to the deck
## Right click = remove one of that energy from the deck
## The card_id used comes from the current energy style, so switching
## styles later will use different set-specific IDs.
func _on_energy_icon_gui_input(event: InputEvent, energy_type: String) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	# Look up which card_id this energy type maps to in the current style
	var type_index := ENERGY_TYPES.find(energy_type)
	if type_index == -1:
		return
	var card_id : String = GameState.ENERGY_STYLES[current_energy_style][type_index]
	var in_deck : int    = deck_cards.get(card_id, 0)
	var icon    : TextureRect = energy_icons[energy_type]
	var label   : Label  = energy_labels[energy_type]

	if event.button_index == MOUSE_BUTTON_LEFT:
		# Energies have no copy cap — add freely
		in_deck += 1
		total_deck_count += 1
		deck_cards[card_id] = in_deck
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)

		if in_deck == 1:
			_apply_energy_icon_animation(energy_type, icon)

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if in_deck <= 0:
			return
		in_deck -= 1
		total_deck_count -= 1

		if in_deck == 0:
			deck_cards.erase(card_id)
			_remove_energy_icon_animation(energy_type, icon)
		else:
			deck_cards[card_id] = in_deck

		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	else:
		return

	label.text = str(in_deck)
	_update_deck_count_label()
	_refresh_save_button()


# ─── Energy style picker overlay ────────────────────────────────────────────
# When the player clicks "Change Energy Style", we hide all normal UI and
# show a grid of 6 rows × 6 columns of energy cards.  Each row represents
# one set's energy style.  Clicking any card in a row selects that entire
# row (i.e. that style).  Save/Cancel buttons appear on the right.

## Called when the "Change Energy Style" button is pressed.
## Hides all normal deck-builder UI and shows the energy picker overlay.
func _on_change_energy_style_pressed() -> void:
	if energy_picker_active:
		return

	energy_picker_active = true
	_set_ui_visibility(false)

	# If the picker was previously built and just hidden, re-show it
	# instantly — no need to reload all 36 card images again.
	if energy_picker_overlay != null:
		energy_picker_overlay.visible = true
		return

	# Build the overlay as a regular Control (NOT a CanvasLayer).
	# CanvasLayer creates a separate rendering layer that ignores the
	# normal scene tree's z_index entirely — meaning the top_and_right_border
	# could never render on top of it.  By using a plain Control with a
	# z_index between the background and the border, the energy cards
	# scroll behind the border naturally.
	energy_picker_overlay = Control.new()
	energy_picker_overlay.z_index = 10   # above background (-10), below border (50)
	energy_picker_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(energy_picker_overlay)

	# ── Click blocker ──
	# Was a 55%-black ColorRect at z 55 — ABOVE the card grid at z 0 — so it dimmed the energy
	# cards themselves rather than the screen behind them, exactly the same bug the deck viewer had.
	# Fully transparent now and dropped below the grid; it keeps the default MOUSE_FILTER_STOP, so
	# it still swallows clicks on everything that isn't a card or one of the two buttons.
	# NOTE: the row dimming you SHOULD still see is dimmed_modulate further down (0.8 grey on
	# unlocked-but-unselected rows) and locked_modulate (near-black on styles you don't own yet).
	# Those are the picker telling you what is selected and what is locked — leave them alone.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.0)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.z_index = 0
	energy_picker_overlay.add_child(backdrop)

	# ── Title label ──
	var title := Label.new()
	var kenney_theme = load("res://UI_Themes/ui/ui_secondary.tres")
	if kenney_theme:
		title.theme = kenney_theme
	title.text = "Select Energy Card Style"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(200, 20)
	title.size = Vector2(1200, 50)
	title.z_index = 55
	energy_picker_overlay.add_child(title)

	# Track which style is currently selected in the picker.
	var picker_selection := {"style": current_energy_style}

	# ── Card size for the picker grid ──
	# 20% larger than the standard deck build card size (183×254)
	var picker_card_size := CARD_SIZE * 1.2   # → ~220 × 305

	# We'll store references to each row's card nodes so we can animate
	# the selected row.  Key = style name, value = array of TextureRects.
	var row_cards : Dictionary = {}
	var row_tweens : Dictionary = {}

	# Get the list of styles the player has unlocked from player_progress.json
	var available_styles := _get_unlocked_energy_styles()

	# ── Build a ScrollContainer + GridContainer for the card grid ──
	var picker_scroll := ScrollContainer.new()
	picker_scroll.position = Vector2(70, 140)
	picker_scroll.size = Vector2(1605, 905)
	picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	picker_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	picker_scroll.z_index = 5   # above the transparent click blocker
	picker_scroll.clip_contents = true
	energy_picker_overlay.add_child(picker_scroll)

	var picker_grid := GridContainer.new()
	picker_grid.columns = 6
	picker_grid.add_theme_constant_override("h_separation", 28)
	picker_grid.add_theme_constant_override("v_separation", 14)
	picker_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin_container := MarginContainer.new()
	margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_container.add_theme_constant_override("margin_left", 15)
	margin_container.add_theme_constant_override("margin_right", 15)
	margin_container.add_theme_constant_override("margin_top", 10)
	margin_container.add_theme_constant_override("margin_bottom", 10)
	picker_scroll.add_child(margin_container)
	margin_container.add_child(picker_grid)

	# ── Save and Cancel buttons on the right side ──
	# These appear immediately along with the backdrop and title.
	var picker_save_btn := Button.new()
	picker_save_btn.text = "save style"
	picker_save_btn.custom_minimum_size = Vector2(226, 63)
	picker_save_btn.position = Vector2(1689, 902)
	picker_save_btn.z_index = 55
	UIKit.style_button(picker_save_btn, "primary")
	picker_save_btn.add_theme_font_size_override("font_size", 23)
	picker_save_btn.pressed.connect(
		func():
			_on_energy_picker_save(picker_selection["style"])
	)
	energy_picker_overlay.add_child(picker_save_btn)

	var picker_cancel_btn := Button.new()
	picker_cancel_btn.text = "cancel"
	picker_cancel_btn.custom_minimum_size = Vector2(224, 63)
	picker_cancel_btn.position = Vector2(1690, 986)
	picker_cancel_btn.z_index = 55
	UIKit.style_button(picker_cancel_btn, "secondary")
	picker_cancel_btn.add_theme_font_size_override("font_size", 23)
	picker_cancel_btn.pressed.connect(_on_energy_picker_cancel)
	energy_picker_overlay.add_child(picker_cancel_btn)

	# ── Let the UI shell render before loading card images ──
	# Everything above (backdrop, title, scroll container, buttons) appears
	# on screen instantly.  The await gives Godot a frame to paint it all
	# before we start the heavier image-loading loop below.
	await get_tree().process_frame

	# Dimmed colour for non-selected but unlocked rows — 20% darker than white
	var dimmed_modulate := Color(0.8, 0.8, 0.8, 1.0)
	# Blacked-out colour for locked styles — matches the unowned card look
	var locked_modulate := Color(0.08, 0.08, 0.08, 1.0)

	# ── Progressive card loading — one card per frame ──
	# Each card image is loaded and added to the grid one at a time, with
	# an await between each so the player sees them appear rather than
	# experiencing a freeze while all 36 images load at once.
	for style_name in GameState.ENERGY_STYLES.keys():
		var is_unlocked : bool = style_name in available_styles
		var card_ids : Array = GameState.ENERGY_STYLES[style_name]

		var cards_in_row : Array = []
		for col in range(6):
			# If the picker was closed mid-load (save/cancel), abort
			if not energy_picker_active:
				return

			var card_id : String = card_ids[col]
			var card_set := card_id.split("-")[0]
			var image_path := "res://Image_Assets/Card_Image_Library/" + card_set + "/Large/" + card_id + ".png"
			var tex = load(image_path)

			var card_rect := TextureRect.new()
			if tex:
				card_rect.texture = tex
			card_rect.custom_minimum_size = picker_card_size
			card_rect.size = picker_card_size
			card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			card_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			card_rect.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
			card_rect.pivot_offset = picker_card_size / 2.0

			if not is_unlocked:
				card_rect.modulate = locked_modulate
				card_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				card_rect.modulate = dimmed_modulate
				card_rect.mouse_filter = Control.MOUSE_FILTER_STOP
				card_rect.gui_input.connect(
					_on_picker_card_clicked.bind(style_name, picker_selection, row_cards, row_tweens)
				)

			picker_grid.add_child(card_rect)
			cards_in_row.append(card_rect)

			# Yield one frame so the card appears on screen before the next loads
			if not is_inside_tree():   # ISSUE #32 FIX: bail if freed mid-load
				return
			await get_tree().process_frame

		row_cards[style_name] = cards_in_row

		# Apply the glow animation to the selected row as soon as its
		# cards are all loaded, so the player sees it highlight immediately
		# rather than waiting for every row to finish
		if style_name == current_energy_style:
			_animate_picker_row(style_name, row_cards, row_tweens)


## The unlocked energy style names — this is what decides which rows appear in the picker.
## ISSUE #155: reads GameState rather than re-opening player_progress.json. The old version parsed
## the file every time it was called, so a style granted in-session (by the cheat, or by an NPC
## gift) was invisible until the file happened to be rewritten. GameState.progress is the live copy.
func _get_unlocked_energy_styles() -> Array:
	return GameState.get_energy_styles()


## Called when any card in the picker grid is clicked.
## Selects that row's style — removes animation from the old selection
## and applies it to the new one.
func _on_picker_card_clicked(event: InputEvent, style_name: String,
		picker_selection: Dictionary, row_cards: Dictionary,
		row_tweens: Dictionary) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var old_style : String = picker_selection["style"]

	# If clicking the already-selected style, do nothing
	if old_style == style_name:
		return

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)

	# Remove animation from old selection
	if row_cards.has(old_style):
		_stop_picker_row_animation(old_style, row_cards, row_tweens)

	# Apply animation to new selection
	picker_selection["style"] = style_name
	_animate_picker_row(style_name, row_cards, row_tweens)


## Starts the glow + grow loop on all 6 cards in a picker row.
## Each card gets its own tween so they all pulse together.
func _animate_picker_row(style_name: String, row_cards: Dictionary,
		row_tweens: Dictionary) -> void:
	# Kill any existing tweens for this row first
	_stop_picker_row_animation(style_name, row_cards, row_tweens)

	var tweens_for_row : Array = []
	for card_rect in row_cards[style_name]:
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(card_rect, "modulate", Color.WHITE * 1.4, 0.5)
		tw.parallel().tween_property(card_rect, "scale", Vector2(1.05, 1.05), 0.5)
		tw.tween_property(card_rect, "modulate", Color.WHITE * 1.0, 0.5)
		tw.parallel().tween_property(card_rect, "scale", Vector2(1.0, 1.0), 0.5)
		tweens_for_row.append(tw)
	row_tweens[style_name] = tweens_for_row


## Stops all glow/grow animations on a picker row and resets the cards
## to the dimmed state (20% darker) so the selected row stands out.
func _stop_picker_row_animation(style_name: String, row_cards: Dictionary,
		row_tweens: Dictionary) -> void:
	if row_tweens.has(style_name) and row_tweens[style_name] != null:
		for tw in row_tweens[style_name]:
			if tw != null:
				tw.kill()
		row_tweens[style_name] = null

	if row_cards.has(style_name):
		for card_rect in row_cards[style_name]:
			card_rect.modulate = Color(0.8, 0.8, 0.8, 1.0)
			card_rect.scale = Vector2(1.0, 1.0)


## Called when the picker's "save style" button is pressed.
## Saves the newly selected style to player_data.json, then swaps any
## energy cards already in the deck from the old style to the new style,
## updates the icons, and closes the picker.
func _on_energy_picker_save(new_style: String) -> void:
	var old_style := current_energy_style

	# ── Swap energy cards in the deck from old style → new style ──
	# If the player had e.g. 10 × base1-99 (Base1 grass) in their deck,
	# and they switch to ex13, we need to replace those with ex13-105.
	if old_style != new_style and GameState.ENERGY_STYLES.has(old_style) and GameState.ENERGY_STYLES.has(new_style):
		var old_ids : Array = GameState.ENERGY_STYLES[old_style]
		var new_ids : Array = GameState.ENERGY_STYLES[new_style]
		for i in range(6):
			var old_id : String = old_ids[i]
			var new_id : String = new_ids[i]
			if deck_cards.has(old_id):
				var count : int = deck_cards[old_id]
				deck_cards.erase(old_id)
				deck_cards[new_id] = count

	current_energy_style = new_style

	# Rebuild name-group tracking after the card ID swap
	_rebuild_deck_name_counts()

	# Save to player_data.json
	_save_energy_style_to_player_data(new_style)

	# Write the updated deck to disk so the swapped energy card IDs persist.
	# Without this, the in-memory deck_cards has the new IDs but the .json
	# file on disk still has the old ones — closing the scene without using
	# the main "save deck" button would lose the swap.
	if current_deck_name != "":
		_save_deck_file(current_deck_name)

	# Snapshot so dirty-tracking knows the deck is clean after the swap
	_snapshot_deck_state()

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	# Close picker and return to normal view.
	# Destroy the overlay entirely (not just hide) because the style
	# changed — the cached glow animation would be on the wrong row.
	# It will rebuild with progressive loading next time.
	_close_energy_picker()
	if energy_picker_overlay != null:
		energy_picker_overlay.queue_free()
		energy_picker_overlay = null

	# Update the energy icons to show the new style's images
	_update_energy_icons()
	_refresh_energy_icons_from_deck()


## Called when the picker's "cancel" button is pressed.
## Closes the picker without saving — the original style is preserved.
func _on_energy_picker_cancel() -> void:
	_close_energy_picker()


## Hides the energy picker overlay and restores all normal UI.
## The overlay is hidden rather than freed so that reopening it is
## instant — the card images are already loaded in memory.
func _close_energy_picker() -> void:
	energy_picker_active = false

	if energy_picker_overlay != null:
		energy_picker_overlay.visible = false

	_set_ui_visibility(true)


# ─── Deck viewer sorting ─────────────────────────────────────────────────────
# The sort itself — Pokémon bucketed by type then grouped into evolution families and ordered
# Stage 2 → Stage 1 → Basic → Baby, then Trainers (Normal/Stadium/Tool), then Energy
# (Special/Basic) — lives in CardViewerList (Scripts/Utilities/Card_Viewer_List.gd) so the
# Card Buyer's bulk-sell screen lays its cards out in exactly the same order.
# Card metadata is handed over as a Callable rather than moved with it, which keeps this
# screen's cache — and the extra ability/artist fields the search screen stores in it —
# private to this script.


## Fills the chrome bars with the deck viewer's own header and footer.
##
## Left: the card count. Centre: the deck name. Right: one chip per category,
## which is where the old CATEGORIES block in the side bar has gone. Footer: Close.
func _build_viewer_chrome() -> void:
	_clear_viewer_chrome()
	if _header == null or _footer == null:
		return

	var count_chip := UIKit.make_chip("%d cards" % total_deck_count, "on_chrome")
	_header.left.add_child(count_chip)
	_viewer_chrome.append(count_chip)

	var name_label := Label.new()
	UIKit.set_label(name_label, "title",
		current_deck_name if current_deck_name != "" else "Deck", "chrome_fg")
	_header.centre.add_child(name_label)
	_viewer_chrome.append(name_label)

	# ISSUE #191: NO category chips. They repeated the Composition box the deck
	# screen already shows one keypress away, and with seven of them the header's
	# right slot was busier than the deck name it sat beside.

	var close_btn := UIKit.make_footer_button("Close", "primary")
	close_btn.pressed.connect(_close_deck_viewer)
	_footer.centre.add_child(close_btn)
	_viewer_chrome.append(close_btn)


## Removes everything _build_viewer_chrome added, so the deck builder's own
## header and footer come back untouched.
func _clear_viewer_chrome() -> void:
	for n in _viewer_chrome:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_viewer_chrome.clear()


## The right-hand contents list: one boxed row per unique card, name on the left
## and the count on the right.
##
## REPLACES CardViewerList.build_side_list here. That helper draws an INDIVIDUAL
## heading over a run of plain text lines and a CATEGORIES block under it; the
## categories are chips in the header now, and a boxed row per card reads far
## better than a text column. The helper is untouched for the bulk-sell screen.
func _build_viewer_contents(sorted_ids: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(VIEWER_LIST_X, UIKit.CONTENT_TOP + VIEWER_LIST_PAD)
	scroll.size = Vector2(VIEWER_LIST_W, UIKit.CONTENT_H - VIEWER_LIST_PAD * 2.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.z_index = 55
	deck_viewer_overlay.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", VIEWER_ROW_GAP)
	scroll.add_child(col)

	var heading := Label.new()
	UIKit.set_label(heading, "small_label", "Contents", "field_mute")
	col.add_child(heading)

	for card_id in sorted_ids:
		var n: int = int(deck_cards.get(card_id, 0))
		if n <= 0:
			continue
		var meta = _get_card_meta(card_id)
		var card_name: String = String(meta.get("name", card_id)) if meta != null else card_id

		var row := UIKit.make_panel()
		row.custom_minimum_size = Vector2(VIEWER_LIST_W - VIEWER_LIST_PAD * 2.0, VIEWER_ROW_H)
		col.add_child(row)

		# ISSUE #190: the row text sat hard against the panel border on both
		# sides. PanelContainer has no padding of its own, so the inset is a
		# MarginContainer between the panel and the row.
		var pad := MarginContainer.new()
		for side in ["margin_left", "margin_right"]:
			pad.add_theme_constant_override(side, VIEWER_ROW_PAD)
		row.add_child(pad)

		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 8)
		pad.add_child(inner)

		var name_lbl := Label.new()
		UIKit.set_label(name_lbl, "attack_name", card_name, "field_fg")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Long names ellipsise rather than pushing the count off the row.
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.clip_text = true
		inner.add_child(name_lbl)

		var count_lbl := Label.new()
		UIKit.set_label(count_lbl, "hp", "x%d" % n, "accent")
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		inner.add_child(count_lbl)



## Returns the full sorted card_id list for the current deck, ready for the viewer.
## Order: Pokémon by type → Trainers (Normal/Stadium/Tool) → Energy (Special/Basic).
func _sort_deck_for_viewer() -> Array:
	return CardViewerList.sort_ids(deck_cards.keys(), _get_card_meta)


# ─── Deck viewer overlay ─────────────────────────────────────────────────────

## Opens a full-screen overlay showing every copy of every card in the current
## deck laid out in a scrollable grid — no count labels, just raw card images.
## The overlay is always rebuilt fresh so it reflects the current deck state.
func _on_view_deck_pressed() -> void:
	if deck_viewer_active or energy_picker_active or is_zoomed:
		return
	if deck_cards.is_empty():
		return

	deck_viewer_active = true
	_set_ui_visibility(false)

	deck_viewer_overlay = Control.new()
	deck_viewer_overlay.z_index = 10
	deck_viewer_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ISSUE #186: THE CLOSE BUTTON WAS UNCLICKABLE, and this is why. Godot picks
	# GUI input by walking the root's children in REVERSE order and ignores
	# z_index entirely, so this full-screen overlay — added after the chrome bars
	# — was picked before the footer and ate every click on it. The overlay itself
	# passes input through now; its backdrop still blocks the board behind, but
	# only across the content band (see below), never over the two bars.
	deck_viewer_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deck_viewer_overlay)

	# ISSUE #151 FIX: this used to be 55% black and sat at z 55 — ABOVE the card grid — which is
	# what darkened the cards themselves rather than the screen behind them. It is fully transparent
	# now and drops BELOW them, but it stays a real Control with the default MOUSE_FILTER_STOP so it
	# still swallows clicks on everything that isn't the Close button.
	# z_index only decides DRAW order here. Godot picks GUI input by walking the tree in reverse
	# child order and ignores z_index entirely, so the backdrop — added before the grid — is picked
	# last whatever its z. That is why the cards were always clickable through it, and why what
	# actually blocked the hold-Shift preview was the cards' own MOUSE_FILTER_IGNORE and missing
	# card_id metadata (fixed below), not this rect.
	var backdrop := ColorRect.new()
	backdrop.color          = Color(0, 0, 0, 0.0)
	# ISSUE #186: the content band ONLY — 92..988 — so the header and footer stay
	# clickable while everything behind the cards stays blocked.
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.offset_top     = UIKit.CONTENT_TOP
	backdrop.offset_bottom  = UIKit.CONTENT_BOTTOM - UIKit.SCREEN_H
	backdrop.z_index        = 0
	deck_viewer_overlay.add_child(backdrop)

	# THE VIEWER BORROWS THE CHROME BARS. It used to draw its own title at y=35 and
	# a Close button at y=1003, both of which now sit UNDER the header and footer.
	# _set_ui_visibility(false) has already hidden the deck builder's own header
	# content, so the slots are free.
	_build_viewer_chrome()

	var viewer_scroll := ScrollContainer.new()
	# ISSUE #194: the card container ran to y=1079, so the bottom rows were hidden
	# behind the footer, and started 18px late, which left a black band above the
	# first row. It matches the deck-mode grid exactly now: same x, same width,
	# and the full 92..988 band between the bars.
	viewer_scroll.position              = Vector2(GRID_X, UIKit.CONTENT_TOP)
	viewer_scroll.size                  = Vector2(GRID_W, UIKit.CONTENT_H)
	viewer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	viewer_scroll.vertical_scroll_mode  = ScrollContainer.SCROLL_MODE_AUTO
	viewer_scroll.z_index               = 5   # ISSUE #151: above the transparent click blocker
	viewer_scroll.clip_contents         = true
	deck_viewer_overlay.add_child(viewer_scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",   0)
	margin.add_theme_constant_override("margin_right",  0)
	# ISSUE #194: zero, matching the deck grid's GRID_INSET_Y — the 10px top inset
	# was the thin black band above the first row of cards.
	margin.add_theme_constant_override("margin_top",    0)
	margin.add_theme_constant_override("margin_bottom", 0)
	viewer_scroll.add_child(margin)

	var viewer_grid := GridContainer.new()
	viewer_grid.columns                 = COLUMNS
	viewer_grid.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	viewer_grid.add_theme_constant_override("h_separation", CARD_H_SEP)
	viewer_grid.add_theme_constant_override("v_separation", CARD_V_SEP)
	margin.add_child(viewer_grid)

	var sorted_ids : Array = _sort_deck_for_viewer()
	_build_viewer_contents(sorted_ids)

	await get_tree().process_frame

	# Add one TextureRect per copy of each card — no count label
	for card_id in sorted_ids:
		if not deck_viewer_active:
			return
		var cid        : String = card_id
		var count      : int    = deck_cards[cid]
		var card_set   : String = cid.split("-")[0]
		var image_path : String = "res://Image_Assets/Card_Image_Library/" + card_set + "/Large/" + cid + ".png"
		var card_texture        = load(image_path)

		for _i in range(count):
			if not deck_viewer_active:
				return
			var card_rect := TextureRect.new()
			if card_texture != null:
				card_rect.texture = card_texture
			card_rect.custom_minimum_size       = CARD_SIZE
			card_rect.size                      = CARD_SIZE
			card_rect.expand_mode               = TextureRect.EXPAND_IGNORE_SIZE
			card_rect.stretch_mode              = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			card_rect.size_flags_horizontal     = Control.SIZE_SHRINK_BEGIN
			card_rect.size_flags_vertical       = Control.SIZE_SHRINK_BEGIN
			# ISSUE #151 FIX: hold-Shift preview works in here now. _get_hovered_card() finds a card
			# by walking up from gui_get_hovered_control() looking for "card_id" metadata, so the
			# rects need both the metadata and a mouse_filter that registers hover — exactly what
			# the main deck grid's owned cards use (see _add_card_to_grid).
			card_rect.set_meta("card_id", cid)
			card_rect.mouse_filter              = Control.MOUSE_FILTER_STOP
			viewer_grid.add_child(card_rect)
			if not is_inside_tree():   # ISSUE #32 FIX: bail if freed mid-load
				return
			await get_tree().process_frame


# ─── Deck viewer card list (ISSUE #152) ──────────────────────────────────────
# The bar's geometry, its INDIVIDUAL / CATEGORIES sections and all three font fits moved to
# CardViewerList (Scripts/Utilities/Card_Viewer_List.gd) — the Card Buyer's bulk-sell screen
# shows the same list for the cards it is about to buy, and one copy is what keeps the two
# from drifting apart. Every tweakable in there (bar width, font floors and ceilings, the
# header colour, line spacing) is documented at its own constant; tune them there, not here.


## Builds the right-hand card list for the deck viewer. `sorted_ids` is the same unique-card order
## the grid is drawn in, so the list and the cards read down the screen together.
func _build_viewer_card_list(sorted_ids: Array) -> void:
	if deck_viewer_overlay == null or sorted_ids.is_empty():
		return
	var lines : Array = CardViewerList.individual_lines(sorted_ids, deck_cards, _get_card_meta)
	if lines.is_empty():
		return
	CardViewerList.build_side_list(deck_viewer_overlay, lines, _deck_category_rows())


## Per-copy counts for the CATEGORIES section, in display order. Counts COPIES, not unique
## cards, so the six numbers add up to the deck total.
func _deck_category_rows() -> Array:
	return CardViewerList.category_rows(deck_cards, _get_card_meta)


## Closes and frees the deck viewer overlay, restoring normal UI.
## Always freed (not hidden) because the deck may have changed since it was built.
func _close_deck_viewer() -> void:
	_clear_viewer_chrome()
	deck_viewer_active = false
	if deck_viewer_overlay != null:
		deck_viewer_overlay.queue_free()
		deck_viewer_overlay = null
	_set_ui_visibility(true)


## Writes the energy_style field to player_data.json without touching
## any other fields.
func _save_energy_style_to_player_data(style_name: String) -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("DeckBuild: cannot read " + PLAYER_DATA_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if not data is Dictionary:
		return

	data["energy_style"] = style_name

	var write_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("DeckBuild: cannot write " + PLAYER_DATA_PATH)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()


# ─── Scroll container ───────────────────────────────────────────────────────

## Wraps the GridContainer inside a ScrollContainer so the card grid
## can scroll vertically when a set has more cards than fit on screen.
## This is done in code rather than the scene file to keep the .tscn simple.
func _wrap_grid_in_scroll_container() -> void:
	var parent = grid.get_parent()

	var scroll := ScrollContainer.new()
	scroll.name = "deck_scroll_container"
	# The scroll container inherits the grid's position and size from the scene
	scroll.position = grid.position
	scroll.size     = grid.size
	# Only allow vertical scrolling — horizontal is handled by column count
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO

	# Reparent: remove grid from root, add scroll to root, put grid inside scroll
	parent.remove_child(grid)
	parent.add_child(scroll)
	scroll.add_child(grid)

	# Reset grid position inside the scroll container
	grid.position = Vector2.ZERO
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", CARD_H_SEP)
	grid.add_theme_constant_override("v_separation", CARD_V_SEP)


# ─── Grid display ────────────────────────────────────────────────────────────

## Clears the grid and populates it with cards from the current set.
## Cards are added one per frame so the player sees them appear progressively
## rather than a single freeze while the entire set loads at once.
func _display_current_set() -> void:
	# Determine which set to display
	if unlocked_indices.is_empty():
		return
	var set_idx  : int        = unlocked_indices[current_unlock_pos]
	var set_id   : String     = set_list[set_idx]["set_id"]
	var set_name : String     = set_list[set_idx]["set_name"]

	# Update the set name label
	set_label.text = set_name

	# ISSUE #32: block input behind a loading overlay while this set's grid builds (shown every set
	# load / set switch). Hidden once the grid finishes below; a set switch mid-load triggers a fresh
	# _display_current_set whose show() replaces this overlay, so aborted loads don't leak it.
	# ISSUE #32 (retest): the deck screen has a ~300px right-hand banner, so nudge the loading icon
	# 150px left to keep it centred over the visible card area. Shrink the input blocker 142px from the
	# top / 134px from the bottom so the banner's Cancel button and set-switch controls stay clickable.
	_loading_overlay.show_for_deck(self)

	# Clear existing cards — kill any active tweens first
	_clear_grid()

	# Load this set's owned-cards data
	var owned_cards := _load_owned_cards_for_set(set_id)

	# Pre-load the card metadata (names, subtypes) for this set so the
	# name-based copy limit checks work immediately when cards are clicked
	_ensure_set_metadata_loaded(set_id)

	# Store which set we're currently loading so we can detect if the player
	# switches set mid-load and abort the old load gracefully
	_loading_set_id = set_id

	# Populate the grid one card per frame for progressive visual loading
	for card_data in owned_cards:
		# If the player switched sets while we were still loading, stop
		if _loading_set_id != set_id:
			return
		# ISSUE #32 FIX: if the player pressed Escape and the scene is being freed, stop before
		# touching get_tree() (which is null once this node has left the tree) — this was the crash.
		if not is_inside_tree():
			return

		_add_card_to_grid(card_data)
		await get_tree().process_frame

	# ISSUE #32: grid finished building for the current set — allow player input again.
	_loading_overlay.hide()


## Removes all card entries from the grid, killing tweens to avoid
## errors from animating freed nodes.
func _clear_grid() -> void:
	for child in grid.get_children():
		# Each child is a TextureRect (card_rect) added directly to the grid
		var tw = child.get_meta("deck_tween", null)
		if tw:
			tw.kill()
		child.queue_free()

	# queue_free is deferred, so wait a frame before adding new children
	# ISSUE #32 FIX: guard against the scene having been freed (Escape mid-load) before get_tree().
	if not is_inside_tree():
		return
	await get_tree().process_frame
	
## Creates a single card entry in the grid.
## card_data is a dictionary: {card_id, owned}
func _add_card_to_grid(card_data: Dictionary) -> void:
	var card_id   : String = card_data["card_id"]
	var owned     : int    = int(card_data["owned"])
	var in_deck   : int    = deck_cards.get(card_id, 0)

	# ── Card visual ──
	# Owned cards show their Small image; unowned cards load no image at all —
	# they render as a plain black rectangle the same size as a card (the
	# count label is still overlaid below). This avoids loading textures the
	# player can't use just to darken them to near-black.
	#
	# For the TextureRect, EXPAND_IGNORE_SIZE tells it to report
	# custom_minimum_size (150x207) to the GridContainer for layout rather than
	# the texture's native pixel dimensions — without this a larger texture
	# would make the grid cell match the texture and cards would overlap.
	var card_rect : Control
	if owned == 0:
		# ISSUE #193: an EMPTY SLOT, not a black rectangle. This is the same
		# UIKit.make_slot() the sleeves and coin walls use for a locked tile —
		# translucent fill with an outline, so an unowned card reads as a place a
		# card goes rather than as a hole in the grid.
		card_rect = UIKit.make_slot(CARD_SIZE)
	else:
		var tex_rect := TextureRect.new()
		var card_set := card_id.split("-")[0]
		# ISSUE #274: Large, not Small. The grid draws these at CARD_SIZE either way
		# and STRETCH_KEEP_ASPECT_CENTERED scales whatever it is given, so the only
		# thing the small copy bought was a slightly blurrier card. What makes this
		# screen slow is the NUMBER of cells, not the size of each texture.
		var image_path := "res://Image_Assets/Card_Image_Library/" + card_set + "/Large/" + card_id + ".png"
		var card_texture = _load_card_texture_with_fallback(image_path)
		if card_texture != null:
			tex_rect.texture = card_texture
		else:
			push_error("DeckBuild: missing card image " + image_path)
		tex_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		# STRETCH_KEEP_ASPECT_CENTERED: scales the texture to fit within the
		# rect while preserving aspect ratio, so it scales DOWN to fit the cell.
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_rect = tex_rect

	card_rect.custom_minimum_size = CARD_SIZE
	card_rect.size                = CARD_SIZE
	# Prevent the card from growing if the grid offers more space
	card_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card_rect.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	# Pivot at center so scale animations grow from the middle
	card_rect.pivot_offset        = CARD_SIZE / 2.0

	# ── Count label ──
	# Overlaid on the bottom of the card image. The label and its background
	# are children of the card_rect so they move with it during animations.
	var label_bg := ColorRect.new()
	label_bg.color = Color(0, 0, 0, 0.65)
	label_bg.position = Vector2(0, CARD_SIZE.y - COUNT_STRIP_H)
	label_bg.size = Vector2(CARD_SIZE.x, COUNT_STRIP_H)
	label_bg.z_index = 10
	label_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var count_label := Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	# Spaces around the slash: "1 / 4" reads as a fraction, "1/4" as one token.
	count_label.text = "%d / %d" % [in_deck, owned]
	UIKit.style_label(count_label, "hp", "field_fg", COUNT_STRIP_FONT)
	count_label.position = Vector2.ZERO
	count_label.size = Vector2(CARD_SIZE.x, COUNT_STRIP_H)
	count_label.z_index = 11
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── Store metadata on the card_rect directly ──
	card_rect.set_meta("card_id",         card_id)
	card_rect.set_meta("owned",           owned)
	card_rect.set_meta("in_deck",         in_deck)
	card_rect.set_meta("card_rect",       card_rect)
	card_rect.set_meta("count_label",     count_label)

	# ── Visual styling based on ownership ──
	if owned == 0:
		# The placeholder ColorRect is already black — just make it inert.
		card_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		card_rect.modulate     = Color.WHITE
		card_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		card_rect.gui_input.connect(_on_card_gui_input.bind(card_rect))

		if in_deck > 0:
			_apply_selected_animation(card_rect as TextureRect)

	# ── Assemble and add to grid ──
	label_bg.add_child(count_label)
	card_rect.add_child(label_bg)
	grid.add_child(card_rect)


# ─── Card click handling ─────────────────────────────────────────────────────

## Handles mouse input on a card image.
## Left click  = add one copy to deck
## Right click = remove one copy from deck
func _on_card_gui_input(event: InputEvent, card_node: Control) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	var card_id   : String     = card_node.get_meta("card_id")
	var owned     : int        = card_node.get_meta("owned")
	var in_deck   : int        = card_node.get_meta("in_deck")
	var card_rect : TextureRect = card_node.get_meta("card_rect")
	var label     : Label      = card_node.get_meta("count_label")

	# Determine the max copies allowed using name-based group limits
	var max_allowed : int = _get_max_for_card(card_id, owned)

	if event.button_index == MOUSE_BUTTON_LEFT:
		# ── Add a copy ──
		if in_deck >= max_allowed:
			return     # already at limit for this card

		in_deck += 1
		total_deck_count += 1
		deck_cards[card_id] = in_deck

		# Update the name-group counter
		var group_key := _get_name_group(card_id)
		deck_name_counts[group_key] = deck_name_counts.get(group_key, 0) + 1

		card_node.set_meta("in_deck", in_deck)

		SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)

		# Start selection animation when the first copy is added
		if in_deck == 1:
			_apply_selected_animation(card_rect)

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		# ── Remove a copy ──
		if in_deck <= 0:
			return     # nothing to remove

		in_deck -= 1
		total_deck_count -= 1

		# Update the name-group counter
		var group_key := _get_name_group(card_id)
		deck_name_counts[group_key] = maxi(deck_name_counts.get(group_key, 0) - 1, 0)

		if in_deck == 0:
			deck_cards.erase(card_id)
			# Stop animation when last copy is removed
			_remove_selected_animation(card_rect)
		else:
			deck_cards[card_id] = in_deck

		card_node.set_meta("in_deck", in_deck)
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)

	else:
		return   # ignore middle-click etc.

	# Update the label and global UI
	label.text = "%d / %d" % [in_deck, owned]
	_update_deck_count_label()
	_refresh_save_button()


# ─── Selection animation ────────────────────────────────────────────────────

## Starts a looping glow + scale animation on a card to show it is in the deck.
## Matches the style from cardimage.gd set_selected(true).
func _apply_selected_animation(card_rect: TextureRect) -> void:
	# Kill any existing tween on this card
	var old_tween = card_rect.get_meta("deck_tween", null)
	if old_tween:
		old_tween.kill()

	card_rect.pivot_offset = CARD_SIZE / 2.0
	card_rect.modulate     = Color.WHITE

	var tw := create_tween()
	tw.set_loops()
	card_rect.set_meta("deck_tween", tw)

	# Glow brighter + grow slightly, then return to normal — loops forever
	tw.tween_property(card_rect, "modulate", Color.WHITE * 1.4, 0.5)
	tw.parallel().tween_property(card_rect, "scale", Vector2(1.03, 1.03), 0.5)
	tw.tween_property(card_rect, "modulate", Color.WHITE * 1.0, 0.5)
	tw.parallel().tween_property(card_rect, "scale", Vector2(1.0, 1.0), 0.5)


## Stops the selection animation and resets the card to its normal state.
func _remove_selected_animation(card_rect: TextureRect) -> void:
	var tw = card_rect.get_meta("deck_tween", null)
	if tw:
		tw.kill()
		card_rect.set_meta("deck_tween", null)
	card_rect.modulate = Color.WHITE
	card_rect.scale    = Vector2(1.0, 1.0)


# ─── Set navigation ─────────────────────────────────────────────────────────

## Move to the next unlocked set (wraps around to the start).
func _on_next_set() -> void:
	if unlocked_indices.is_empty():
		return
	# The arrows are hidden in search-results mode, but a stray keyboard "press" on a focused
	# button would still fire this and blow the results away — ignore it while a search is up.
	if search_active:
		return
	current_unlock_pos = (current_unlock_pos + 1) % unlocked_indices.size()
	_display_current_set()
	# Scroll back to top when switching sets
	_reset_scroll_position()


## Move to the previous unlocked set (wraps around to the end).
func _on_prev_set() -> void:
	if unlocked_indices.is_empty():
		return
	if search_active:
		return
	current_unlock_pos -= 1
	if current_unlock_pos < 0:
		current_unlock_pos = unlocked_indices.size() - 1
	_display_current_set()
	_reset_scroll_position()


## Scrolls the scroll container back to the top.
func _reset_scroll_position() -> void:
	var scroll = grid.get_parent()
	if scroll is ScrollContainer:
		scroll.scroll_vertical = 0


# ─── Card search ─────────────────────────────────────────────────────────────
#
# The search button always reads "SEARCH" and always does the same thing: open the filter screen.
# Pressing it while results are on screen brings the screen back with every filter still set, so the
# player can tweak one thing and search again. From there:
#   SEARCH  -> run the (edited) filters and show the new results
#   RESET   -> wipe the filters but stay on the screen, ready to build a fresh search
#   CANCEL  -> clear the search entirely and drop back to normal set browsing
# Escape mirrors CANCEL on the screen, and clears the results when pressed over them; a second
# Escape then leaves the deck builder as usual.
#
# Because the filters have to survive being reopened, the overlay is only HIDDEN after a successful
# search — it is freed when the search is cleared, so the next one starts blank.
#
# Filter semantics: OR within a category, AND between categories, with the name box always ANDed
# on top as a case-insensitive substring. Only cards the player actually owns are ever returned —
# the blacked-out unowned placeholders that appear in the per-set view are skipped entirely.

## True only while the filter screen is actually on screen. A hidden-but-alive overlay means "a
## search is showing and these were its filters", which must not count as open.
func _search_screen_open() -> bool:
	return search_overlay != null and search_overlay.visible


## ISSUE #141 FIX: swaps the scene's background layers between browsing and filtering.
## filtering = true  -> filter_background + filter_border, scroller and right banner hidden
## filtering = false -> back to the browsing pair
## Called from every entry to and exit from the search screen (open / cancel / confirm / clear),
## so a hidden-but-alive overlay (search results showing) correctly counts as NOT filtering.
func _set_filter_chrome(filtering: bool) -> void:
	for node in [background_scroller, top_and_right_border]:
		if node != null and is_instance_valid(node):
			node.visible = not filtering
	for node in [filter_background, filter_border]:
		if node != null and is_instance_valid(node):
			node.visible = filtering


func _on_search_pressed() -> void:
	_open_search_overlay()


func _open_search_overlay() -> void:
	if _search_screen_open():
		return
	if energy_picker_active or deck_viewer_active or load_popup != null:
		return

	# Hide the deck UI behind the search screen, the same way the energy picker does
	_set_ui_visibility(false)
	_set_filter_chrome(true)   # ISSUE #141

	# Reopening after a search: the overlay was only hidden, so showing it again brings back exactly
	# the filters that produced the results currently on screen.
	if search_overlay != null:
		search_overlay.visible = true
		return

	# Build the list of unlocked set_ids in release order — this drives both which set icons the
	# screen shows and which gated filter options (Baby, Stadium, ex, delta...) are available.
	var unlocked_set_ids : Array = []
	for idx in unlocked_indices:
		unlocked_set_ids.append(set_list[idx]["set_id"])

	search_overlay = CardSearchOverlay.new()
	add_child(search_overlay)
	search_overlay.setup(unlocked_set_ids, set_list)
	search_overlay.search_confirmed.connect(_on_search_confirmed)
	search_overlay.search_cancelled.connect(_on_search_cancelled)
	search_overlay.search_reset.connect(_on_search_reset)


## CANCEL / Escape on the search screen — back out to whatever the grid was already showing and KEEP
## the filters. The overlay is hidden rather than freed, so pressing SEARCH again brings back exactly
## the selections the player just backed out of, and a search that is already running stays on screen
## behind it. Escape a second time is what actually clears a search — see the Escape handler.
##
## If RESET was pressed while the screen was up, the search is already gone and the grid still owes a
## redraw; that is done here rather than at the moment of the reset, so its loading overlay doesn't
## flash over the search screen.
func _on_search_cancelled() -> void:
	if search_overlay != null:
		search_overlay.visible = false
	_set_filter_chrome(false)   # ISSUE #141
	_set_ui_visibility(true)

	if _search_grid_stale:
		_search_grid_stale = false
		_restore_set_browsing_chrome()
		_display_current_set()
		_reset_scroll_position()


## SEARCH pressed with at least one filter set. Runs the filter, and only switches the grid over to
## results mode if something actually matched — a search that finds nothing keeps the player on the
## filter screen with their selections intact so they can adjust them.
func _on_search_confirmed(criteria: Dictionary) -> void:
	var results := await _run_search(criteria)

	if results.is_empty():
		# The screen may have been cancelled while the search was running
		if _search_screen_open():
			_show_deck_message("No cards found")
		return

	search_results = results
	search_active  = true
	# A fresh set of results replaces the grid outright, so any redraw a RESET left owing is moot.
	_search_grid_stale = false

	# Hidden rather than freed, so pressing SEARCH again restores these exact filters
	if search_overlay != null:
		search_overlay.visible = false

	_set_filter_chrome(false)   # ISSUE #141: results are browsing, not filtering
	_set_ui_visibility(true)
	await _display_search_results()


## Drops out of results mode and goes back to browsing the set the player was last on. Also frees the
## filter screen — a cleared search keeps no filters, so the next SEARCH press opens blank.
func _clear_search() -> void:
	_close_search_overlay()
	_set_filter_chrome(false)   # ISSUE #141
	var had_results := _drop_search_results()
	if not (had_results or _search_grid_stale):
		return
	_search_grid_stale = false
	_restore_set_browsing_chrome()
	_display_current_set()
	_reset_scroll_position()


## RESET on the filter screen. The screen has blanked its own selections, so the search applied to
## the grid has to go with them or the two would disagree — an empty filter screen sitting in front
## of filtered results, with SEARCH disabled and no button back out.
##
## The overlay deliberately stays OPEN (the player may be about to build a new filter), and the grid
## is NOT rebuilt yet: the rebuild puts up the shared loading overlay, which would flash over the top
## of the search screen. _on_search_cancelled() does it on the way out instead.
func _on_search_reset() -> void:
	if _drop_search_results():
		_search_grid_stale = true


## Forgets the active search without touching the overlay or the grid. Returns false when there was
## no search to forget, so callers can skip the redraw.
func _drop_search_results() -> bool:
	if not search_active:
		return false
	search_active = false
	search_results.clear()
	_search_load_token += 1        # abort any results build still in flight
	return true


## The set name and the < > switch buttons are hidden while results are showing; bring them back.
func _restore_set_browsing_chrome() -> void:
	set_label.visible = true
	next_btn.visible  = true
	prev_btn.visible  = true


func _close_search_overlay() -> void:
	if search_overlay == null:
		return
	search_overlay.queue_free()
	search_overlay = null


## Rebuilds whatever the grid is currently meant to be showing. Anything that needs to redraw the
## cards from scratch (loading a different deck, for instance) must go through here rather than
## calling _display_current_set directly, or it would silently drop the player out of their search
## results while the UI still claimed a search was active.
func _refresh_card_grid() -> void:
	if search_active:
		_display_search_results()
	else:
		_display_current_set()


## Walks every unlocked set and returns the {card_id, owned} entries that match the criteria,
## already sorted into the requested order. Unowned cards are never included.
func _run_search(criteria: Dictionary) -> Array:
	# Parsing up to 38 set JSONs plus their owned-card files can take a moment, so block input
	# behind the shared loading overlay exactly like a set load does.
	_loading_overlay.show_for_deck(self)
	await get_tree().process_frame

	var wanted_sets : Array = criteria.get("sets", [])
	var results : Array = []

	for idx in unlocked_indices:
		var set_id : String = set_list[idx]["set_id"]

		# A set filter is an OR within its own category, so a set that isn't listed can be skipped
		# wholesale rather than tested card by card.
		if not wanted_sets.is_empty() and not (set_id in wanted_sets):
			continue

		_ensure_set_metadata_loaded(set_id)
		for card_data in _load_owned_cards_for_set(set_id):
			if int(card_data.get("owned", 0)) <= 0:
				continue
			if _card_matches_search(card_data["card_id"], criteria):
				results.append(card_data)

		if not is_inside_tree():
			_loading_overlay.hide()
			return []
		await get_tree().process_frame

	_sort_search_results(results, criteria.get("sort", "set"))
	_loading_overlay.hide()
	return results


## ISSUE #149: true when `haystack` contains ANY of the (already lower-cased) comma-separated
## terms, and also true when there are no terms — an empty list means the player left that box
## blank, which is not a filter. Shared by the name and illustrator boxes so they cannot drift.
func _matches_any_term(haystack: String, terms: Array) -> bool:
	if terms.is_empty():
		return true
	var lower := haystack.to_lower()
	for term in terms:
		if String(term) in lower:
			return true
	return false


## Tests one card against every category. Each category is skipped when the player selected nothing
## in it; when they did select something, the card must match ONE of their choices (OR within the
## category). Every category that is in play must pass (AND between categories).
func _card_matches_search(card_id: String, criteria: Dictionary) -> bool:
	var meta = _get_card_meta(card_id)
	if meta == null:
		return false

	var card_name : String = meta["name"]
	var supertype : String = meta["supertype"]
	var subtypes  : Array  = meta["subtypes"]
	var types     : Array  = meta.get("types", [])

	# Subtype spelling isn't perfectly consistent across the card data — the 8 ex promos in np.json
	# are tagged "EX" rather than "ex", for instance. The rest of the engine already compares these
	# case-insensitively (see is_ex_pokemon / _get_name_group), so the search does too rather than
	# quietly dropping those cards out of every result.
	var subtypes_lower : Array = []
	for st in subtypes:
		subtypes_lower.append(str(st).to_lower())

	# ── Name ── ISSUE #149: one or more COMMA-separated terms, parsed out of the box by
	# CardSearchOverlay.parse_search_terms(). The terms OR together and the result still ANDs with
	# every other category, exactly as the single substring used to. An empty term list means the
	# box was blank (or held only commas), i.e. no name filter at all.
	if not _matches_any_term(card_name, criteria.get("name_terms", [])):
		return false

	# ── Set ── (already filtered per-set in _run_search, kept here so this stays a complete test)
	var wanted_sets : Array = criteria.get("sets", [])
	if not wanted_sets.is_empty() and not (card_id.split("-")[0] in wanted_sets):
		return false

	# ── Card type (supertype) ──
	var wanted_card_types : Array = criteria.get("card_types", [])
	if not wanted_card_types.is_empty() and not (supertype in wanted_card_types):
		return false

	# ── Pokemon type ── only Pokemon carry a "types" array, so this is inherently Pokemon-only
	var wanted_types : Array = criteria.get("types", [])
	if not wanted_types.is_empty():
		var type_hit := false
		for t in types:
			if t in wanted_types:
				type_hit = true
				break
		if not type_hit:
			return false

	# ── Pokemon stage ── Baby cards carry only "Baby", never "Basic", so the four are exclusive
	var wanted_stages : Array = criteria.get("stages", [])
	if not wanted_stages.is_empty() and not _any_subtype_matches(subtypes_lower, wanted_stages):
		return false

	# ── Trainer sub type ──
	var wanted_trainer_subs : Array = criteria.get("trainer_subs", [])
	if not wanted_trainer_subs.is_empty() and not _any_subtype_matches(subtypes_lower, wanted_trainer_subs):
		return false

	# ── Pokemon sub type ──
	var wanted_pokemon_subs : Array = criteria.get("pokemon_subs", [])
	if not wanted_pokemon_subs.is_empty():
		if not _card_matches_pokemon_sub(card_name, subtypes_lower, types, wanted_pokemon_subs):
			return false

	# ── Rarity ── a whole-card property, so this applies to Trainers and Energy too
	var wanted_rarities : Array = criteria.get("rarities", [])
	if not wanted_rarities.is_empty():
		if not _card_matches_rarity(str(meta.get("rarity", "")), wanted_rarities):
			return false

	# ── Has Power / Body ── ISSUE #140. A whole-card property like rarity, so it is NOT restricted
	# to Pokemon: the Claw Fossil / Root Fossil Trainers carry a real Poké-Body and must match.
	var wanted_powers : Array = criteria.get("powers", [])
	if not wanted_powers.is_empty():
		if not _card_matches_power(meta, wanted_powers):
			return false

	# ── Illustrator ── ISSUE #143, and ISSUE #149's comma terms, exactly like the name box above.
	if not _matches_any_term(str(meta.get("artist", "")), criteria.get("illus_terms", [])):
		return false

	# ── Effect ── reserved; matches everything until CardSearchOverlay.EFFECT_FILTERS is populated
	var wanted_effects : Array = criteria.get("effects", [])
	if not wanted_effects.is_empty():
		if not _card_matches_effect(card_id, wanted_effects):
			return false

	return true


## True when any of the wanted subtype names is on the card. `subtypes_lower` is the card's subtype
## list already lowercased; the wanted names come from the search screen's option tables in their
## display casing, so they're lowered here to meet it.
func _any_subtype_matches(subtypes_lower: Array, wanted: Array) -> bool:
	for want in wanted:
		if str(want).to_lower() in subtypes_lower:
			return true
	return false


## The Pokemon sub types aren't all plain subtype lookups:
##   ex       — a real "ex" subtype
##   shining  — the Neo "Shining <name>" cards AND the later gold Star cards, which the search
##              screen deliberately groups under one icon
##   delta    — the delta symbol in the printed name, matching card_object.is_delta()
##   dualtype — more than one entry in the card's "types" array (Psychic/Metal Metagross,
##              Water/Darkness Team Aqua's Kyogre, and so on)
func _card_matches_pokemon_sub(card_name: String, subtypes_lower: Array, types: Array, wanted: Array) -> bool:
	for key in wanted:
		match key:
			"ex":
				if "ex" in subtypes_lower:
					return true
			"shining":
				if card_name.begins_with("Shining ") or "star" in subtypes_lower:
					return true
			"delta":
				if "δ" in card_name:
					return true
			"dualtype":
				if types.size() > 1:
					return true
	return false


## ISSUE #140: does the card carry the kind of ability the player asked for? Both flags are
## precomputed in _ensure_set_metadata_loaded, so this is two dictionary reads.
##
## OR within the row, matching every other filter category on the screen — ticking both POWER and
## BODY finds cards with either, not only the handful that have both.
func _card_matches_power(meta: Dictionary, wanted: Array) -> bool:
	for key in wanted:
		match key:
			"power":
				if bool(meta.get("has_power", false)):
					return true
			"body":
				if bool(meta.get("has_body", false)):
					return true
	return false


## Maps a card's printed rarity onto the four buckets the search screen offers.
##
## The data holds ten distinct rarity strings. Common / Uncommon / Rare map one-to-one; "holorare"
## takes everything else beginning with "Rare" — Rare Holo, Rare Holo EX, Rare Holo Star,
## Rare Shining and Rare Secret (the secret rares are all holofoil cards). Matching on the prefix
## rather than a fixed list means any new Rare variant lands in the holo bucket automatically.
##
## Two groups deliberately match NO bucket, because they carry no rarity symbol on the card:
## the 94 "Promo" cards (basep + np) and the 48 with no rarity at all (basic Energy in
## base1/gym1/gym2/neo1/ecard1, plus all 18 Southern Islands cards).
func _card_matches_rarity(card_rarity: String, wanted: Array) -> bool:
	var r := card_rarity.to_lower()
	if r == "":
		return false

	for key in wanted:
		match key:
			"common":
				if r == "common":
					return true
			"uncommon":
				if r == "uncommon":
					return true
			"rare":
				if r == "rare":
					return true
			"holorare":
				if r.begins_with("rare") and r != "rare":
					return true
	return false


## RESERVED: card-effect matching for the effect filter row. Returns true for now so a criteria
## dictionary carrying effect keys can't silently filter everything out. Implement alongside
## CardSearchOverlay.EFFECT_FILTERS — the keys here are the same "key" values from that table.
func _card_matches_effect(_card_id: String, _wanted_effects: Array) -> bool:
	return true


## ISSUE #225: the order the Pokemon energy types sort in when sort_mode is
## "type". Anything not in this list (a Trainer, an Energy card, an unrecognised
## type) sorts after every Pokemon — see _search_type_key.
const TYPE_SORT_ORDER := ["Grass", "Fire", "Water", "Lightning", "Psychic",
	"Fighting", "Colorless", "Darkness", "Metal"]


## "set"  — release order, then card number within each set (what browsing a set already looks like)
## "name" — grouped by card name, then release order and card number within each name
## "type" — ISSUE #225: Pokemon first, bucketed by energy type in TYPE_SORT_ORDER,
##          then Trainers, then Energy cards. Within a bucket it falls back to the
##          same release-order tiebreak as "set".
func _sort_search_results(results: Array, sort_mode: String) -> void:
	# Position of each set in the dictionary's release order, so sorting never has to search the list
	var set_order : Dictionary = {}
	for i in range(set_list.size()):
		set_order[set_list[i]["set_id"]] = i

	if sort_mode == "type":
		results.sort_custom(func(a, b):
			var ka : int = _search_type_key(a["card_id"])
			var kb : int = _search_type_key(b["card_id"])
			if ka != kb:
				return ka < kb
			return _search_sort_key(a["card_id"], set_order) < _search_sort_key(b["card_id"], set_order)
		)
	elif sort_mode == "name":
		results.sort_custom(func(a, b):
			var name_a : String = _search_card_name(a["card_id"])
			var name_b : String = _search_card_name(b["card_id"])
			if name_a != name_b:
				return name_a.naturalnocasecmp_to(name_b) < 0
			return _search_sort_key(a["card_id"], set_order) < _search_sort_key(b["card_id"], set_order)
		)
	else:
		results.sort_custom(func(a, b):
			return _search_sort_key(a["card_id"], set_order) < _search_sort_key(b["card_id"], set_order)
		)


## ISSUE #225: the sort bucket for "type". Pokemon take their first listed energy
## type's index (0-8), Trainers 100 and Energy cards 200, so the three supertypes
## never interleave. A card with no metadata sorts last rather than crashing.
##
## "first listed type" is deliberate: a dual-type or delta Pokemon files under the
## type printed first on the card, which is how the player reads it.
func _search_type_key(card_id: String) -> int:
	var meta = _get_card_meta(card_id)
	if meta == null:
		return 900
	var supertype := String(meta.get("supertype", ""))
	if supertype == "Trainer":
		return 100
	if supertype == "Energy":
		return 200
	var types: Array = meta.get("types", [])
	if types.is_empty():
		return 99
	var idx := TYPE_SORT_ORDER.find(String(types[0]))
	return idx if idx >= 0 else 99


## Packs a card's set position and card number into one comparable integer so both sorts can share
## the same "release order, then card number" tiebreak.
func _search_sort_key(card_id: String, set_order: Dictionary) -> int:
	var parts := card_id.split("-")
	var set_idx : int = set_order.get(parts[0], 9999)
	# Card numbers aren't always plain integers (e.g. "H12" in the e-Card sets), so strip to digits
	# and fall back to 0 — same-numbered oddities then just keep their file order.
	var num_text := "" if parts.size() < 2 else parts[1]
	var digits := ""
	for c in num_text:
		if c >= "0" and c <= "9":
			digits += c
	var num : int = 0 if digits == "" else int(digits)
	return set_idx * 100000 + num


func _search_card_name(card_id: String) -> String:
	var meta = _get_card_meta(card_id)
	return "" if meta == null else meta["name"]


## Fills the grid with the search results. Mirrors _display_current_set, but batches whole rows per
## frame because a broad search can return the player's entire collection.
func _display_search_results() -> void:
	_loading_overlay.show_for_deck(self)

	_search_load_token += 1
	var token := _search_load_token

	# The loading overlay deliberately leaves the top strip of the screen clickable, and the search
	# button lives up there — so a set grid can still be building one-card-per-frame when we get
	# here. Blanking _loading_set_id makes that loop bail on its next iteration instead of dribbling
	# its remaining cards into the results grid we're about to fill.
	_loading_set_id = ""

	_clear_grid()
	_reset_scroll_position()

	var added := 0
	for card_data in search_results:
		# The player cleared the search (or started another) while this build was still running
		if token != _search_load_token:
			return
		if not is_inside_tree():
			return

		_add_card_to_grid(card_data)
		added += 1
		if added % SEARCH_LOAD_BATCH == 0:
			await get_tree().process_frame

	_loading_overlay.hide()


# ─── Shared confirm popup ────────────────────────────────────────────────────

## The one styled Yes/No confirm on this screen. `confirm_label` names the destructive button
## ("Empty", "Delete"); `on_confirm` runs after the popup closes, so the callback never has to
## think about tearing it down. Cancel is green and confirm is red, matching the main menu's quit
## dialog — the whole game asks destructive questions the same way.
##
## Keyboard is handled in _input(): accept runs the action, cancel backs out. Layer 110 puts it
## above the load popup (100), which is where the Delete confirm is raised from.
func _show_confirm_popup(message: String, confirm_label: String, on_confirm: Callable) -> void:
	if confirm_popup != null and is_instance_valid(confirm_popup):
		return

	_confirm_action = on_confirm

	confirm_popup = CanvasLayer.new()
	confirm_popup.layer = 110
	add_child(confirm_popup)

	# Dim the screen behind the popup
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	confirm_popup.add_child(overlay)

	# Centered panel
	var panel := UIKit.make_modal_panel()
	panel.custom_minimum_size = Vector2(560, 240)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -280
	panel.offset_top    = -120
	panel.offset_right  = 280
	panel.offset_bottom = 120
	confirm_popup.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var msg := Label.new()
	msg.text = message
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(500, 0)
	msg.add_theme_font_size_override("font_size", 24)
	vbox.add_child(msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var yes_btn := Button.new()
	yes_btn.text = confirm_label
	yes_btn.custom_minimum_size = Vector2(150, 48)
	yes_btn.add_theme_font_size_override("font_size", 22)
	# Destructive: this popup only ever confirms "Empty" or "Delete".
	UIKit.style_button(yes_btn, "danger")
	yes_btn.pressed.connect(_run_confirm_action)
	btn_row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "Cancel"
	no_btn.custom_minimum_size = Vector2(150, 48)
	no_btn.add_theme_font_size_override("font_size", 22)
	UIKit.style_button(no_btn, "secondary")
	no_btn.pressed.connect(_close_confirm_popup)
	btn_row.add_child(no_btn)


## Closes the popup FIRST, then runs the action — so a callback that opens another popup (delete
## re-opening the refreshed load list) can't collide with the one being torn down.
func _run_confirm_action() -> void:
	var cb := _confirm_action
	_close_confirm_popup()
	if cb.is_valid():
		cb.call()


func _close_confirm_popup() -> void:
	_confirm_action = Callable()
	if confirm_popup != null:
		confirm_popup.queue_free()
		confirm_popup = null


# ─── Empty deck ──────────────────────────────────────────────────────────────

## Asks the player to confirm before wiping the entire deck.
## Emptying a full 60-card deck by an accidental click is painful, so we gate
## the destructive action behind a Yes/No popup.
func _on_empty_deck_pressed() -> void:
	# Nothing to clear, and don't stack popups
	if total_deck_count == 0 or confirm_popup != null:
		return
	_show_confirm_popup("Empty the entire deck?\nThis cannot be undone.", "Empty", _do_empty_deck)


## Clears the entire deck — resets all in-deck counts to 0.
func _do_empty_deck() -> void:
	deck_cards.clear()
	deck_name_counts.clear()
	total_deck_count = 0
	deck_name_edit.text = ""
	_update_deck_count_label()
	_refresh_save_button()

	# Refresh every card in the current grid to remove animations and counts
	for card_rect in grid.get_children():
		var label     : Label       = card_rect.get_meta("count_label", null)
		var owned     : int         = card_rect.get_meta("owned", 0)

		if label == null:
			continue

		card_rect.set_meta("in_deck", 0)
		label.text = "0/" + str(owned)

		# Only remove animation from owned cards — unowned cards must stay dark
		if owned > 0:
			_remove_selected_animation(card_rect)
		# Unowned cards keep their darkened modulate untouched

	# Also reset the energy icon labels and animations
	_refresh_energy_icons_from_deck()


# ─── Save ────────────────────────────────────────────────────────────────────

## Saves the current deck to a JSON file and updates player_data.json.
func _on_save_pressed() -> void:
	# ISSUE #84 FIX: every reason a save can be refused now produces a visible floating message instead
	# of the button silently doing nothing. The size checks used to be duplicated here (and hardcoded to
	# != DECK_SIZE, ignoring the debug-mode relaxation) — they all live in _deck_save_blocker() now.
	var blocker := _deck_save_blocker()
	if blocker != "":
		_show_deck_message(blocker)
		return

	if not _is_deck_dirty():
		_show_deck_message("No changes to save")
		return

	var display_name := deck_name_edit.text.strip_edges()

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	# Write the deck file
	_save_deck_file(display_name)

	# Update player_data.json with the new deck name and last set loaded
	_save_player_data(display_name)

	current_deck_name = display_name
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	# Snapshot the deck so dirty-tracking knows this is the saved state
	_snapshot_deck_state()

	# Disable save button after saving (dirty check will return false)
	_refresh_save_button()


## Writes the current deck_cards dictionary to a JSON file in the
## playerdecks folder.  Used both by the main "save deck" button and
## by the energy style picker when it swaps energy card IDs.
func _save_deck_file(file_name: String) -> void:
	var deck_array : Array = []
	for card_id in deck_cards:
		deck_array.append({
			"id": card_id,
			"count": deck_cards[card_id]
		})

	# Sort by card ID for consistent file output
	deck_array.sort_custom(func(a, b): return a["id"] < b["id"])

	var deck_path := PLAYER_DECKS_FOLDER + file_name + ".json"
	var deck_file := FileAccess.open(deck_path, FileAccess.WRITE)
	if deck_file == null:
		push_error("DeckBuild: cannot write " + deck_path)
		return
	deck_file.store_string(JSON.stringify(deck_array, "\t"))
	deck_file.close()


## Updates player_data.json — writes the active deck name and last set viewed.
func _save_player_data(deck_file_name: String) -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("DeckBuild: cannot read " + PLAYER_DATA_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if not data is Dictionary:
		return

	data["deck"] = deck_file_name
	# Store the current set's ID so we return here next time
	var set_idx = unlocked_indices[current_unlock_pos]
	data["last_set_loaded"] = set_list[set_idx]["set_id"]

	var write_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("DeckBuild: cannot write " + PLAYER_DATA_PATH)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()


# ─── Cancel ──────────────────────────────────────────────────────────────────

## ISSUE #228: leaving with unsaved deck changes now asks first.
##
## _is_deck_dirty() already exists and drives the Save button's colour, so the
## screen has always known this — it just never used it on the way out. Both exits
## come through here: the Cancel button and the Escape key (see _input, which calls
## this last once every overlay has had its chance to close).
func _on_cancel_pressed() -> void:
	if _is_deck_dirty():
		_show_confirm_popup(
			"You have unsaved changes.
Are you sure you want to leave?",
			"Leave", _do_leave_deck_builder)
		return
	_do_leave_deck_builder()


## The actual exit, once the unsaved-changes question (if any) has been answered.
func _do_leave_deck_builder() -> void:
	_save_last_set_loaded()
	SoundManagerScript.stop_bgm()
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


## Writes only last_set_loaded to player_data.json without touching deck name.
func _save_last_set_loaded() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		return

	var set_idx = unlocked_indices[current_unlock_pos]
	data["last_set_loaded"] = set_list[set_idx]["set_id"]

	var write_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()


# ─── Input handling (Escape + Shift zoom) ───────────────────────────────────

## Handles global keyboard input for the deck build screen.
## - Escape: backs out one layer — closes whichever popup/overlay is on top
##   (load-deck, zoom, deck viewer, energy picker, search screen, search results)
##   and returns to normal deck-building mode; only an Escape with nothing open
##   leaves for the menu
## - Shift press: zooms into the hovered card's large image
## - Shift release: closes the zoom overlay and restores UI
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_update_composition_panel()

	# The rename box owns the keys while it is up, but it owns them by GETTING OUT OF THE WAY:
	# only Escape is consumed (to close it), and every other key returns unhandled so the LineEdit
	# still receives it. Two things break if this branch is written the usual way —
	#   - consuming everything would stop the player typing at all, since _input runs before GUI
	#     input and set_input_as_handled() would starve the LineEdit;
	#   - treating accept as "confirm" would make the SPACE BAR rename the deck, because
	#     UIInput.is_accept() counts Space and deck names contain spaces. Enter is handled by the
	#     LineEdit's own text_submitted signal instead.
	# Shift is the card-preview key further down this function, and it is also how you type a
	# capital letter — the early return is what stops a preview opening behind the box.
	if rename_popup != null and is_instance_valid(rename_popup):
		if UIInput.is_cancel(event):
			get_viewport().set_input_as_handled()
			_close_rename_popup()
		return

	# The "Empty the entire deck?" confirm owns the keys while it is up: accept
	# empties the deck, cancel backs out. Without this, Escape fell straight through
	# to _on_cancel_pressed() and left the deck builder with the popup still open,
	# and Space started a card preview behind it.
	if confirm_popup != null and is_instance_valid(confirm_popup):
		if UIInput.is_accept(event):
			get_viewport().set_input_as_handled()
			_run_confirm_action()
		elif UIInput.is_cancel(event):
			get_viewport().set_input_as_handled()
			_close_confirm_popup()
		return

	# ── Cancel / Escape ──
	# Backs out exactly ONE layer per press: whichever popup or overlay is on top
	# closes and drops the player back into normal deck-building mode, and only an
	# Escape with nothing open leaves for the menu. Ordered topmost-first, so the
	# load popup — a modal CanvasLayer sitting above everything else — takes the
	# press before the overlays underneath it.
	# UIInput rather than a keycode test, so pad B backs out too (see UI_Input.gd).
	if UIInput.is_cancel(event):
		# Consumed up front: _on_cancel_pressed() at the bottom tears this screen
		# down, after which get_viewport() is no longer safe to call (ISSUE #51).
		get_viewport().set_input_as_handled()
		# Load-deck popup — same as pressing its Cancel button. Without this the
		# press fell straight through to _on_cancel_pressed() and left the deck
		# builder entirely, with the popup still open on the way out.
		if load_popup != null and is_instance_valid(load_popup):
			_close_load_popup()
			return
		# If zoomed in, close the zoom instead of leaving the scene
		if is_zoomed:
			# Drop the hold too, or _process would immediately re-open the preview (ISSUE #13)
			zoom_held = false
			_hide_zoom()
			return
		# If the deck viewer is open, close it
		if deck_viewer_active:
			_close_deck_viewer()
			return
		# If the energy picker is open, close it (same as pressing cancel)
		if energy_picker_active:
			_on_energy_picker_cancel()
			return
		# Search screen open — same as pressing its CANCEL button
		if _search_screen_open():
			_on_search_cancelled()
			return
		# Showing search results — the first Escape drops back to normal set browsing,
		# a second one then leaves the deck builder as usual
		if search_active:
			_clear_search()
			return
		_on_cancel_pressed()
		return

	# ── Hold-to-preview ──
	# Shift, not Space. Space is the accept key, so the old binding fought with it: an
	# unhandled press fell through to "ui_accept" and re-pressed whichever button last had
	# focus, and it had to be consumed to stop that. Shift has no other job on this screen,
	# so nothing needs consuming and typing in the name box is unaffected.
	# Above the InputEventKey guard below so the pad shoulder button reaches it too.
	if UIInput.is_zoom_start(event):
		# Don't preview if a popup or picker is open, or the deck name field has focus
		if load_popup != null:
			return
		if energy_picker_active:
			return
		# ISSUE #151: the deck viewer used to block the preview outright. It is allowed now — the
		# viewer's cards carry card_id metadata and are hoverable, so the same hold-Shift preview
		# the main grid uses works over them. Escape still closes the preview before the viewer
		# (see the cancel chain above), so the two back out one layer at a time.
		if _search_screen_open():
			return          # typing in the search name box must not trigger the preview
		if deck_name_edit.has_focus():
			return
		zoom_held = true
		print("ISSUE #13 FIX ACTIVE (deck view zoom key): preview now follows the mouse while Shift is held")
		_refresh_hover_preview()
		return
	if UIInput.is_zoom_end(event):
		zoom_held = false
		_hide_zoom()
		return


## ISSUE #13: while the zoom key is held, keep the preview locked to whatever card the mouse is over.
## The is_zoom_held() re-check is for the one case the key events miss — alt-tabbing away with the
## key down eats the release, which would otherwise leave the preview stuck open.
func _process(_delta: float) -> void:
	if not zoom_held:
		return
	if not UIInput.is_zoom_held():
		zoom_held = false
		_hide_zoom()
		return
	_refresh_hover_preview()


## Shows the hovered card, swapping the image when the hover moves to a different card.
##
## ISSUE #98: this used to hide the preview the instant the mouse was over nothing. Sliding between
## two adjacent cards crosses the few pixels of grid separation, so the overlay was torn down and
## rebuilt on every crossing — one frame of the bright deck-builder UI showing through, read as a
## white flash. While the key is held the preview is now STICKY: it only ever changes to another
## card, never back to nothing. Releasing the key is the only thing that closes it.
func _refresh_hover_preview() -> void:
	var card := _get_hovered_card()
	if card == zoomed_card:
		return
	if card == null:
		return   # mouse is in the gap between cards (or off the grid) — hold the current preview
	_show_zoom(card)


# ─── Card zoom ──────────────────────────────────────────────────────────────

## Returns the card TextureRect under the mouse cursor, or null if none.
## Uses Godot's built-in gui_get_hovered_control() which returns whichever
## Control node the mouse is currently over. Because the mouse might land
## on a child node (the count label, its ColorRect background, etc.) rather
## than the card TextureRect itself, we walk up the node tree looking for
## a node that carries our "card_id" metadata — that's the actual card.
func _get_hovered_card() -> TextureRect:
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return null
	# Walk up to 5 parents looking for our card_id metadata
	var node = hovered
	for i in range(5):
		if node == null:
			return null
		if node.has_meta("card_id"):
			return node as TextureRect
		node = node.get_parent()
	return null


## Shows the enlarged view of the given card.
## Creates a CanvasLayer overlay (layer 150, above everything including the
## load popup at layer 100) with a dimmed background and a CardDetailPanel: the
## card art down the left-hand half, and every piece of the card's data broken
## into its own message box down the right. See Card_Detail_Panel.gd.
func _show_zoom(card_rect: TextureRect) -> void:
	var card_id : String = card_rect.get_meta("card_id")
	zoomed_card = card_rect

	# ISSUE #98 FIX ACTIVE: an overlay is already up (the player slid onto another card while holding
	# the zoom key) — hand the new card to the live panel. Freeing and rebuilding the CanvasLayer let
	# the bright UI underneath show through for a frame, which is the white flash between cards.
	if is_zoomed and detail_panel != null and is_instance_valid(detail_panel):
		detail_panel.show_card(card_id)
		return

	is_zoomed = true

	# Build the overlay — CanvasLayer renders above everything at layer 150
	zoom_overlay = CanvasLayer.new()
	zoom_overlay.layer = 150
	add_child(zoom_overlay)

	# Semi-transparent black backdrop
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.95)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	# ISSUE #13: the overlay must never absorb hover, or gui_get_hovered_control() would report
	# the backdrop instead of the card grid underneath and the live preview would flicker off.
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.add_child(backdrop)

	detail_panel = CardDetailPanel.new()
	zoom_overlay.add_child(detail_panel)
	detail_panel.show_card(card_id)


## Removes the zoom overlay and restores all UI elements.
func _hide_zoom() -> void:
	if not is_zoomed:
		return

	is_zoomed = false
	zoomed_card = null
	detail_panel = null

	if zoom_overlay != null:
		zoom_overlay.queue_free()
		zoom_overlay = null



# ─── UI helpers ──────────────────────────────────────────────────────────────

## Updates the "XX/60" label in the top bar.
func _update_deck_count_label() -> void:
	deck_count_label.text = "%d / %d" % [total_deck_count, DECK_SIZE]
	_refresh_deck_count_chip()
	_update_composition_panel()






## Hides or shows all UI elements so overlays (deck viewer, energy picker) can
## take over the full screen without interference from the main deck-build UI.
func _set_ui_visibility(visible_flag: bool) -> void:
	var scroll = grid.get_parent()
	var nodes_to_toggle := [
		scroll,
		save_btn,
		cancel_btn,
		empty_btn,
		load_btn,
		next_btn,
		prev_btn,
		set_label,
		deck_name_edit,
		# ISSUE #182: deck_count_label is permanently hidden — the sidebar pill
		# replaced it. Leaving it in this list made every return from the deck
		# viewer or the search screen show the old 61px "XX / XX" back in the
		# middle of the screen.
		view_deck_btn,
		search_btn,
	]

	for energy_type in ENERGY_TYPES:
		nodes_to_toggle.append(energy_icons[energy_type])
		nodes_to_toggle.append(energy_labels[energy_type])

	# The two sidebar panels and every row inside the composition box.
	nodes_to_toggle.append_array(_energy_panel_nodes)
	for key in _comp_rows:
		var row: Dictionary = _comp_rows[key]
		nodes_to_toggle.append(row["count"])
		nodes_to_toggle.append(row["meter"])
		nodes_to_toggle.append(row["name"])
	if _comp_panel != null:
		nodes_to_toggle.append(_comp_panel)
	if _comp_heading != null:
		nodes_to_toggle.append(_comp_heading)
	if _deck_count_chip_holder != null and is_instance_valid(_deck_count_chip_holder):
		nodes_to_toggle.append(_deck_count_chip_holder)   # ISSUE #187

	for node in nodes_to_toggle:
		if node != null and is_instance_valid(node):
			node.visible = visible_flag

	# In search-results mode the grid isn't showing a single set, so the < > switch buttons stay
	# hidden even when the rest of the UI is being restored.
	# ISSUE #148 FIX: the set NAME label no longer hides with them — it stays up and reads
	# SEARCH_MODE_LABEL instead, so the screen says why it isn't showing a set. _display_current_set()
	# writes the real set name back over it the moment browsing resumes.
	if visible_flag and search_active:
		set_label.visible = true
		set_label.text    = SEARCH_MODE_LABEL
		next_btn.visible  = false
		prev_btn.visible  = false


## Called every time the player types or deletes in the deck name field.
## text_changed passes the new text as an argument but we just need to
## re-evaluate whether the save button should be enabled or disabled.
func _on_deck_name_changed(_new_text: String) -> void:
	_refresh_save_button()


# ─── Floating message (ISSUE #84) ────────────────────────────────────────────
# TWEAKABLE VALUES for the floating message shown when a save is refused, or when a search matches
# nothing ("No cards found").
const MSG_ANCHOR_Y       := 0.82    # vertical screen position, as a fraction of screen height
const MSG_HEIGHT         := 90.0    # strip height the text is centred in
const MSG_FONT_SIZE      := 51      # +50%: this label reports a refusal, so it has to be read
const MSG_RISE_PIXELS    := 120.0   # how far it drifts upward
const MSG_RISE_SECONDS   := 2.0     # drift duration
const MSG_FADE_SECONDS   := 1.6     # fade duration (starts with the drift)
const MSG_COLOUR         := Color(1.0, 0.45, 0.45)

# The message has to sit above EVERYTHING, including the search screen — "No cards found" is shown
# while that screen is still up, and it was being painted over by the filter rows.
# The label is a direct child of this Control, so its z_index is its effective z. The search overlay
# is z 10 and puts its own controls on CardSearchOverlay.CONTENT_Z (250), i.e. an effective 260, so
# this must beat 260. Keep it ahead of CONTENT_Z if either number is ever changed.
const MSG_Z_INDEX        := 300

# kenvector_future.ttf ships in a single weight with no bold face, so "bold" is synthesised with a
# FontVariation — it thickens the strokes without changing glyph advances, so the text bolds in
# place and its measured width is unchanged. Same approach and same strength as the NEW! / Bonus!
# floating labels in Pack_Opening_Manager.
const MSG_EMBOLDEN       := 0.6     # 0.0 is the plain face, ~0.6 reads as bold

var _deck_message_label: Label = null
var _msg_bold_font: FontVariation = null


## The emboldened theme font, built once and reused. Returns null if the theme has no default font,
## in which case the caller just leaves the label on the plain face.
func _get_msg_bold_font() -> FontVariation:
	if _msg_bold_font != null:
		return _msg_bold_font
	var theme_res = load("res://UI_Themes/ui/ui_secondary.tres")
	if theme_res == null or theme_res.default_font == null:
		return null
	_msg_bold_font = FontVariation.new()
	_msg_bold_font.base_font          = theme_res.default_font
	_msg_bold_font.variation_embolden = MSG_EMBOLDEN
	return _msg_bold_font

## Shows a short message that rises and fades near the bottom of the screen, in the same style as the
## in-match floating labels. Calling it again replaces any message still on screen so rapid clicks
## never stack labels on top of each other.
func _show_deck_message(text: String) -> void:
	if _deck_message_label != null and is_instance_valid(_deck_message_label):
		_deck_message_label.queue_free()
	_deck_message_label = null

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = MSG_Z_INDEX
	var kenney_theme = load("res://UI_Themes/ui/ui_secondary.tres")
	if kenney_theme:
		lbl.theme = kenney_theme
	var bold := _get_msg_bold_font()
	if bold != null:
		lbl.add_theme_font_override("font", bold)
	lbl.add_theme_font_size_override("font_size", MSG_FONT_SIZE)
	lbl.add_theme_color_override("font_color", MSG_COLOUR)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 10)
	# Full-width strip so the text is centred horizontally whatever its length. Both vertical offsets
	# are tweened together (the label is anchored, so tweening `position` would fight the layout).
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = MSG_ANCHOR_Y
	lbl.anchor_bottom = MSG_ANCHOR_Y
	lbl.offset_top = 0.0
	lbl.offset_bottom = MSG_HEIGHT
	add_child(lbl)
	_deck_message_label = lbl

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "offset_top", -MSG_RISE_PIXELS, MSG_RISE_SECONDS)
	tween.tween_property(lbl, "offset_bottom", MSG_HEIGHT - MSG_RISE_PIXELS, MSG_RISE_SECONDS)
	tween.tween_property(lbl, "modulate:a", 0.0, MSG_FADE_SECONDS)
	await tween.finished
	if is_instance_valid(lbl):
		lbl.queue_free()
	if _deck_message_label == lbl:
		_deck_message_label = null


## ISSUE #84: the single source of truth for "can this deck be saved?".
## Returns "" when the deck is saveable, otherwise the reason to show the player.
## The save button's colour and _on_save_pressed()'s floating message both read this, so the button's
## appearance and the explanation can never disagree.
##
## Checks, in the order they are reported:
##   1) card count — must be exactly 60 (relaxed to "at least 1" while debug mode is on)
##   2) at least one Basic Pokemon — enforced even in debug mode, because a deck with no Basic
##      cannot be set up at the start of a match at all, so saving one is never useful
##   3) a deck name has been entered
func _deck_save_blocker() -> String:
	if DebugMode.is_enabled():
		if total_deck_count < 1:
			return "Deck is empty"
	elif total_deck_count < DECK_SIZE:
		return "Deck does not have enough cards. 60 cards required"
	elif total_deck_count > DECK_SIZE:
		return "Deck has too many cards. 60 cards required"

	if not _deck_has_basic_pokemon():
		return "Deck needs at least 1 Basic Pokemon"

	if deck_name_edit.text.strip_edges() == "":
		return "No Deck name entered"

	return ""


## ISSUE #84: true when the deck contains at least one Basic Pokemon.
## A card counts as Basic when its metadata supertype is Pokemon and "Basic" is among its subtypes —
## this deliberately excludes Basic ENERGY, whose supertype is "Energy".
func _deck_has_basic_pokemon() -> bool:
	for card_id in deck_cards:
		if deck_cards[card_id] <= 0:
			continue
		var meta = _get_card_meta(card_id)
		if meta == null:
			continue
		if meta["supertype"] != "Pokémon":
			continue
		for st in meta["subtypes"]:
			if str(st).to_lower() == "basic":
				return true
	return false


## Colours the save button green when the deck is saveable and something has changed.
## ISSUE #84: the button is never actually `disabled` any more — a disabled Button emits no `pressed`
## signal, so the player got no feedback at all when they clicked it. It now always accepts the click
## and _on_save_pressed() explains why nothing was saved; the theme still shows at a glance whether
## saving will work.
func _refresh_save_button() -> void:
	var can_save := _deck_save_blocker() == "" and _is_deck_dirty()
	save_btn.disabled = false
	UIKit.style_button(save_btn, "good" if can_save else "primary")


# ─── Load deck popup ────────────────────────────────────────────────────────
# TWEAKABLE VALUES for the load-deck popup (ISSUE #154).
# The panel is wider and a little taller than it was, the title has real space above it, and the
# dead band that used to sit under Load/Cancel is gone — the deck list carries SIZE_EXPAND_FILL now,
# so leftover height goes into the list rather than pooling at the bottom of the panel.
const LOAD_PANEL_W      := 700.0
const LOAD_PANEL_H      := 680.0
const LOAD_MARGIN_SIDE  := 40     # black space either side of every button
const LOAD_MARGIN_TOP   := 34     # black space above "Load a Deck"
const LOAD_MARGIN_BOTTOM := 22    # deliberately small — see the note above
const LOAD_TITLE_FONT   := 32     # was 28
const LOAD_ROW_H        := 48.0   # height of one deck row, and the side of its square delete button
const LOAD_ROW_FONT     := 20
const LOAD_ACTION_W     := 160.0
const LOAD_ACTION_H     := 52.0
const LOAD_ACTION_FONT  := 22

# The trash glyph is drawn in code — there is no bin icon anywhere in Image_Assets, and a
# hand-drawn one scales with LOAD_ROW_H for free. All values are fractions of the button, so
# changing LOAD_ROW_H rescales the icon with it.
const TRASH_COLOUR := Color(1, 1, 1, 0.95)
const RENAME_COLOUR := Color(1, 1, 1, 0.95)

# ── Rename box ──
const RENAME_PANEL_W    := 640.0
const RENAME_PANEL_H    := 260.0
const RENAME_TITLE_FONT := 24
const RENAME_EDIT_H     := 54.0
const RENAME_EDIT_FONT  := 24
const RENAME_MAX_LENGTH := 40
# Characters Windows will not accept in a filename. A deck name becomes one verbatim, so these have
# to be refused at the box rather than discovered as a failed write.
const RENAME_ILLEGAL_CHARS := ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]


## A square delete button for one deck row. Red, so it reads as destructive next to the neutral
## deck name button, and it asks before it does anything.
func _make_delete_deck_button(deck_name: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(LOAD_ROW_H, LOAD_ROW_H)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.tooltip_text = "Delete this deck"
	UIKit.style_button(btn, "secondary")

	# MOUSE_FILTER_IGNORE so the glyph never eats the click meant for the button under it.
	var glyph := Control.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.draw.connect(_draw_trash_icon.bind(glyph))
	btn.add_child(glyph)

	btn.pressed.connect(func(): _on_delete_deck_pressed(deck_name))
	return btn


## Draws the little trash bin: lid handle, lid, tapered body outline and two slots.
func _draw_trash_icon(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var cx := w * 0.5
	var body_w := w * 0.44
	var body_h := h * 0.42
	var body_top := h * 0.34
	var thick := maxf(1.0, h * 0.055)

	# handle, then the lid just under it
	c.draw_rect(Rect2(cx - body_w * 0.20, body_top - h * 0.20, body_w * 0.40, h * 0.055), TRASH_COLOUR)
	c.draw_rect(Rect2(cx - body_w * 0.62, body_top - h * 0.13, body_w * 1.24, h * 0.065), TRASH_COLOUR)
	# body outline
	c.draw_rect(Rect2(cx - body_w * 0.5, body_top, body_w, body_h), TRASH_COLOUR, false, thick)
	# two slots down the body
	var slot_top := body_top + body_h * 0.20
	var slot_h := body_h * 0.60
	c.draw_rect(Rect2(cx - body_w * 0.20 - thick * 0.5, slot_top, thick, slot_h), TRASH_COLOUR)
	c.draw_rect(Rect2(cx + body_w * 0.20 - thick * 0.5, slot_top, thick, slot_h), TRASH_COLOUR)


## A square rename button for one deck row. Blue rather than the delete button's red — renaming is
## reversible, and the destructive action should be the only red thing on the row.
##
## Sits to the LEFT of the bin so the destructive button stays on the outside edge, where a
## mis-aimed click is least likely to land on it.
func _make_rename_deck_button(deck_name: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(LOAD_ROW_H, LOAD_ROW_H)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.tooltip_text = "Rename this deck"
	var blue_theme = load("res://UI_Themes/ui/ui_secondary.tres")
	if blue_theme:
		btn.theme = blue_theme

	# MOUSE_FILTER_IGNORE so the glyph never eats the click meant for the button under it.
	var glyph := Control.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.draw.connect(_draw_rename_icon.bind(glyph))
	btn.add_child(glyph)

	btn.pressed.connect(func(): _on_rename_deck_pressed(deck_name))
	return btn


## Draws the edit glyph: a sheet of paper with two ruled lines, and a pencil laid across its
## bottom-right corner with the tip pointing down at the page.
##
## Hand-drawn for the same reason the bin is — there is no edit icon anywhere in Image_Assets, and
## every value here is a fraction of the button, so changing LOAD_ROW_H rescales it for free.
##
## The pencil is built from the axis vector rather than hardcoded points: a triangle for the tip
## and a quad for the shaft, both derived from the same direction and a perpendicular. Retuning the
## angle is then a matter of moving PENCIL_TIP / PENCIL_TOP and everything else follows.
func _draw_rename_icon(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var thick := maxf(1.0, h * 0.055)

	# ── The page: outline plus two ruled lines ──
	var page := Rect2(w * 0.16, h * 0.16, w * 0.46, h * 0.62)
	c.draw_rect(page, RENAME_COLOUR, false, thick)
	var line_x := page.position.x + page.size.x * 0.18
	var line_w := page.size.x * 0.54
	for i in range(2):
		var ly := page.position.y + page.size.y * (0.28 + 0.24 * float(i))
		c.draw_rect(Rect2(line_x, ly, line_w, thick), RENAME_COLOUR)

	# ── The pencil, crossing the page's bottom-right corner ──
	var tip := Vector2(w * 0.46, h * 0.86)
	var top := Vector2(w * 0.90, h * 0.24)
	var axis := (top - tip).normalized()
	var perp := Vector2(-axis.y, axis.x)
	var half := maxf(1.0, h * 0.090)
	var neck := tip + axis * (h * 0.22)

	# Tip triangle, then the shaft as a quad running up to the eraser end.
	c.draw_colored_polygon(PackedVector2Array([
		tip, neck + perp * half, neck - perp * half]), RENAME_COLOUR)
	c.draw_colored_polygon(PackedVector2Array([
		neck + perp * half, top + perp * half,
		top - perp * half, neck - perp * half]), RENAME_COLOUR)


## Rename pressed — opens the text box. No confirm step: the box IS the confirmation, and the
## action is reversible by renaming back.
func _on_rename_deck_pressed(deck_name: String) -> void:
	if rename_popup != null and is_instance_valid(rename_popup):
		return


	rename_popup = CanvasLayer.new()
	rename_popup.layer = 110   # above the load popup at 100, same as the delete confirm
	add_child(rename_popup)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	rename_popup.add_child(overlay)

	var panel := UIKit.make_modal_panel()
	panel.custom_minimum_size = Vector2(RENAME_PANEL_W, RENAME_PANEL_H)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -RENAME_PANEL_W * 0.5
	panel.offset_top    = -RENAME_PANEL_H * 0.5
	panel.offset_right  = RENAME_PANEL_W * 0.5
	panel.offset_bottom = RENAME_PANEL_H * 0.5
	rename_popup.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Rename \"%s\"" % deck_name.replace("_", " ")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", RENAME_TITLE_FONT)
	vbox.add_child(title)

	_rename_edit = LineEdit.new()
	# Pre-filled with the name as SHOWN in the list, not the raw filename — the two differ for any
	# legacy deck saved with underscores, and the player should be editing what they can see.
	_rename_edit.text = deck_name.replace("_", " ")
	_rename_edit.max_length = RENAME_MAX_LENGTH
	_rename_edit.custom_minimum_size = Vector2(0, RENAME_EDIT_H)
	_rename_edit.add_theme_font_size_override("font_size", RENAME_EDIT_FONT)
	# Enter confirms. Deliberately the LineEdit's own signal rather than UIInput.is_accept(), which
	# also counts SPACE -- and deck names have spaces in them ("Your First Deck"), so routing this
	# through the usual accept test would make the space bar rename the deck mid-word.
	_rename_edit.text_submitted.connect(func(t: String): _rename_deck(deck_name, t))
	vbox.add_child(_rename_edit)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	var ok_btn := Button.new()
	ok_btn.text = "Rename"
	ok_btn.custom_minimum_size = Vector2(LOAD_ACTION_W, LOAD_ACTION_H)
	ok_btn.add_theme_font_size_override("font_size", LOAD_ACTION_FONT)
	UIKit.style_button(ok_btn, "primary")
	ok_btn.pressed.connect(func(): _rename_deck(deck_name, _rename_edit.text))
	btn_row.add_child(ok_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(LOAD_ACTION_W, LOAD_ACTION_H)
	cancel_btn.add_theme_font_size_override("font_size", LOAD_ACTION_FONT)
	UIKit.style_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(_close_rename_popup)
	btn_row.add_child(cancel_btn)

	# Focus and select-all, so typing replaces the old name straight away.
	await get_tree().process_frame
	if _rename_edit != null and is_instance_valid(_rename_edit):
		_rename_edit.grab_focus()
		_rename_edit.select_all()


func _close_rename_popup() -> void:
	_rename_edit = null
	if rename_popup != null and is_instance_valid(rename_popup):
		rename_popup.queue_free()
	rename_popup = null


## Renames a deck file, after checking everything that can go wrong with turning typed text into a
## filename. Rejections leave the box open so the name can be corrected rather than retyped.
func _rename_deck(old_name: String, raw_new: String) -> void:
	var new_name := raw_new.strip_edges()

	if new_name == "":
		_show_deck_message("Enter a name for the deck")
		return

	# Deck names ARE filenames — _save_deck_file() writes PLAYER_DECKS_FOLDER + name + ".json" with
	# no sanitising at all — so anything the filesystem rejects has to be caught here instead.
	for bad in RENAME_ILLEGAL_CHARS:
		if bad in new_name:
			_show_deck_message("A deck name cannot contain  %s" % " ".join(RENAME_ILLEGAL_CHARS))
			return

	if new_name == old_name:
		_close_rename_popup()
		return

	var new_path := PLAYER_DECKS_FOLDER + new_name + ".json"
	if FileAccess.file_exists(new_path):
		_show_deck_message("A deck called \"%s\" already exists" % new_name)
		return

	var old_path := PLAYER_DECKS_FOLDER + old_name + ".json"
	var err := DirAccess.rename_absolute(old_path, new_path)
	if err != OK:
		push_error("DeckBuild: could not rename " + old_path + " (error " + str(err) + ")")
		_show_deck_message("Could not rename that deck")
		return
	print("DeckBuild: renamed deck ", old_path, " -> ", new_path)

	# The name is a KEY, not just a label: Player_Current_Data.json remembers the active deck by
	# name, so renaming the active one without following up leaves that pointer aimed at a file
	# that no longer exists. Checked against the file rather than against current_deck_name,
	# because the active deck is not necessarily the one open in the builder right now.
	if _active_deck_name() == old_name:
		_save_player_data(new_name)
	# And if it IS the one open in the builder, the header box has to follow too.
	if current_deck_name == old_name:
		current_deck_name = new_name
		if deck_name_edit != null and is_instance_valid(deck_name_edit):
			deck_name_edit.text = new_name

	_close_rename_popup()
	# Rebuild the list so it reflects the new name, exactly as _delete_deck() does.
	_close_load_popup()
	_on_load_deck_pressed()


## The deck name Player_Current_Data.json currently points at, or "" if it cannot be read.
func _active_deck_name() -> String:
	var f := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if f == null:
		return ""
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		return str(data.get("deck", ""))
	return ""


## Trash pressed — confirm first, in the same styled Yes/No box the game uses to ask before
## quitting or emptying a deck.
func _on_delete_deck_pressed(deck_name: String) -> void:
	var shown := deck_name.replace("_", " ")
	_show_confirm_popup("Are you sure you want to delete\n\"%s\"?\nThis cannot be undone." % shown,
		"Delete", func(): _delete_deck(deck_name))


## Deletes a deck file and reopens the load popup over the refreshed list.
## Deleting the deck that is currently loaded is deliberately allowed — the cards stay in memory and
## the player can save them again under the same or a new name. _load_deck() already survives a
## missing file, so a stale name left in player_data.json cannot break the next visit either.
func _delete_deck(deck_name: String) -> void:
	var path := PLAYER_DECKS_FOLDER + deck_name + ".json"
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_error("DeckBuild: could not delete " + path + " (error " + str(err) + ")")
		_show_deck_message("Could not delete that deck")
		return

	# Rebuild the popup so the list reflects the deletion. If that was the last deck,
	# _on_load_deck_pressed() finds nothing to show and simply leaves the screen clear.
	_close_load_popup()
	_on_load_deck_pressed()

## Opens a popup showing all saved decks in the playerdecks folder.
## The player picks one from the list and clicks Load, or clicks Cancel.
func _on_load_deck_pressed() -> void:
	# Prevent opening multiple popups
	if load_popup != null:
		return

	# Read all .json files from the decks folder
	var deck_files : Array = []
	var dir := DirAccess.open(PLAYER_DECKS_FOLDER)
	if dir == null:
		push_error("DeckBuild: cannot open " + PLAYER_DECKS_FOLDER)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			deck_files.append(fname.trim_suffix(".json"))
		fname = dir.get_next()
	dir.list_dir_end()
	deck_files.sort()

	if deck_files.is_empty():
		return

	# ── Build the popup UI ──
	# CanvasLayer ensures the popup renders above everything else.
	load_popup = CanvasLayer.new()
	load_popup.layer = 100
	add_child(load_popup)

	# Semi-transparent background overlay to dim the screen behind the popup
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	load_popup.add_child(overlay)

	# Main panel — centered on screen. ISSUE #154: wider (500 -> LOAD_PANEL_W) and slightly taller
	# (600 -> LOAD_PANEL_H).
	var panel := UIKit.make_modal_panel()
	panel.custom_minimum_size = Vector2(LOAD_PANEL_W, LOAD_PANEL_H)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -LOAD_PANEL_W * 0.5
	panel.offset_top    = -LOAD_PANEL_H * 0.5
	panel.offset_right  = LOAD_PANEL_W * 0.5
	panel.offset_bottom = LOAD_PANEL_H * 0.5
	load_popup.add_child(panel)

	# ISSUE #154: the breathing room. Left/right margins are the black space either side of the
	# buttons, the top margin is the space above the title, and the bottom margin is deliberately
	# small — the old layout left a big dead band under Load/Cancel because nothing in the VBox
	# expanded, so all the slack piled up at the bottom.
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left",   LOAD_MARGIN_SIDE)
	margins.add_theme_constant_override("margin_right",  LOAD_MARGIN_SIDE)
	margins.add_theme_constant_override("margin_top",    LOAD_MARGIN_TOP)
	margins.add_theme_constant_override("margin_bottom", LOAD_MARGIN_BOTTOM)
	panel.add_child(margins)

	# Vertical layout inside the panel
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margins.add_child(vbox)

	# Title
	var title_label := Label.new()
	title_label.text = "Load a Deck"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", LOAD_TITLE_FONT)
	vbox.add_child(title_label)

	# Scrollable list of decks. ISSUE #154: EXPAND_FILL is what removes the dead space under the
	# Load/Cancel row — the list soaks up whatever height is left over instead of the panel doing it.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(list_vbox)

	# Track which deck is currently highlighted.
	# Using a Dictionary because GDScript lambdas capture objects by reference
	# but Strings by value — so a plain String variable updated in one lambda
	# would not be visible to another lambda. The Dictionary acts as a shared
	# mutable container that both lambdas can read and write.
	var selection := {"deck_name": "", "button": null}

	# One row per deck: the name button, then a square delete button (ISSUE #154).
	for deck_name in deck_files:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		list_vbox.add_child(row)

		var btn := Button.new()
		btn.text = deck_name.replace("_", " ")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UIKit.style_button(btn, "secondary")
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, LOAD_ROW_H)
		btn.add_theme_font_size_override("font_size", LOAD_ROW_FONT)
		# When clicked, highlight this button and store the deck name
		btn.pressed.connect(
			func():
				# Un-highlight previous selection
				if selection["button"] != null and is_instance_valid(selection["button"]):
					UIKit.style_button(selection["button"], "secondary")
				# Highlight new selection
				UIKit.style_button(btn, "selected")
				selection["button"] = btn
				selection["deck_name"] = deck_name
		)
		row.add_child(btn)
		row.add_child(_make_rename_deck_button(deck_name))
		row.add_child(_make_delete_deck_button(deck_name))

	# Bottom row: Load + Cancel buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	var load_confirm_btn := Button.new()
	load_confirm_btn.text = "Load"
	load_confirm_btn.custom_minimum_size = Vector2(LOAD_ACTION_W, LOAD_ACTION_H)
	load_confirm_btn.add_theme_font_size_override("font_size", LOAD_ACTION_FONT)
	UIKit.style_button(load_confirm_btn, "primary")
	load_confirm_btn.pressed.connect(
		func():
			if selection["deck_name"] != "":
				var chosen_name : String = selection["deck_name"]
				_close_load_popup()
				# Load the chosen deck
				current_deck_name = chosen_name
				deck_name_edit.text = chosen_name.replace("_", " ")
				_load_deck(chosen_name)
				_update_deck_count_label()

				# Detect which energy style this deck uses by checking
				# if any of its card IDs match a known energy style.
				# E.g. if the deck contains base1-99, switch to "Base1";
				# if it contains ex13-105, switch to "ex13".
				var detected_style := _detect_energy_style_from_deck()
				if detected_style != "":
					current_energy_style = detected_style
					_save_energy_style_to_player_data(detected_style)
					_update_energy_icons()

				_refresh_energy_icons_from_deck()
				_refresh_card_grid()

				# Treat the loaded deck as already saved and active —
				# write it as the player's active deck in player_data.json
				_save_player_data(chosen_name)

				# Snapshot for dirty-tracking so save button stays disabled
				# until the player actually makes a change
				_snapshot_deck_state()
				_refresh_save_button()
	)
	btn_row.add_child(load_confirm_btn)

	var cancel_popup_btn := Button.new()
	cancel_popup_btn.text = "Cancel"
	cancel_popup_btn.custom_minimum_size = Vector2(LOAD_ACTION_W, LOAD_ACTION_H)
	cancel_popup_btn.add_theme_font_size_override("font_size", LOAD_ACTION_FONT)
	UIKit.style_button(cancel_popup_btn, "secondary")
	cancel_popup_btn.pressed.connect(_close_load_popup)
	btn_row.add_child(cancel_popup_btn)


## Removes the load-deck popup from the scene tree.
func _close_load_popup() -> void:
	if load_popup != null:
		load_popup.queue_free()
		load_popup = null
