extends Control

# ─── Constants ───────────────────────────────────────────────────────────────

var PLAYER_DATA_PATH: String:
	get: return GameState.PLAYER_CURRENT_DATA_PATH
const SET_DICT_PATH        := "res://Player_Data/Player_Owned_Cards/Set_ID_Names_Dictionary.json"
var OWNED_CARDS_FOLDER: String:
	get: return GameState.OWNED_CARDS_FOLDER
var PLAYER_DECKS_FOLDER: String:
	get: return GameState.PLAYER_DECKS_FOLDER

var PLAYER_PROGRESS_PATH: String:
	get: return GameState.PROGRESS_PATH

const CARD_SIZE     := Vector2(183, 254)
const CARD_H_SEP    := 2
const CARD_V_SEP    := 2
const COLUMNS       := 9
const MAX_COPIES    := 4
const DECK_SIZE     := 60

# ─── TEMP TESTING FLAG ──────────────────────────────────────────────────────
# When true, the deck builder drops the "exactly 60 cards" and "max 4 per name
# group" (and per-card ownership) save restrictions, so any deck can hold any
# number of any card. Set back to false to restore normal deck-building rules.
const TESTING_UNLIMITED_DECKS := true

# ─── Energy style data ──────────────────────────────────────────────────────
# Each style maps to 6 card IDs in a fixed order: grass, fire, water,
# lightning, psychic, fighting.  The order matters because each set has
# different numbering — we can't just loop through sequentially.

const ENERGY_TYPES := ["grass", "fire", "water", "lightning", "psychic", "fighting"]

const ENERGY_STYLES : Dictionary = {
	"Base1":  ["base1-99",  "base1-98",  "base1-102", "base1-100", "base1-101", "base1-97"],
	"Ecard1": ["ecard1-162","ecard1-161","ecard1-165","ecard1-163","ecard1-164","ecard1-160"],
	"ex1":    ["ex1-104",   "ex1-108",   "ex1-106",   "ex1-109",   "ex1-107",   "ex1-105"],
	"ex9":    ["ex9-101",   "ex9-102",   "ex9-103",   "ex9-104",   "ex9-105",   "ex9-106"],
	"ex13":   ["ex13-105",  "ex13-106",  "ex13-107",  "ex13-108",  "ex13-109",  "ex13-110"],
	"ex16":   ["ex16-103",  "ex16-104",  "ex16-105",  "ex16-106",  "ex16-107",  "ex16-108"],
}

# BBCode hex colours for the per-set deck breakdown label.
# "__trainer__" is the combined Trainer + Special Energy bucket.
const TYPE_COLOR_HEX : Dictionary = {
	"Colorless":   "#ffffff",
	"Darkness":    "#1a1a1a",
	"Fighting":    "#d9823c",
	"Fire":        "#ff4a36",
	"Grass":       "#47d647",
	"Lightning":   "#ffdc14",
	"Metal":       "#8c8c8c",
	"Psychic":     "#c247f0",
	"Water":       "#4592ff",
	"__trainer__": "#c8c8c8",
}

# Display order for Pokémon types in the deck viewer.
const POKEMON_TYPE_DISPLAY_ORDER : Array = [
	"Grass", "Fire", "Water", "Lightning", "Psychic",
	"Fighting", "Darkness", "Metal", "Colorless",
]

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
var empty_confirm_popup : CanvasLayer = null

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
# ISSUE #13: the preview tracks the mouse live for as long as Space is held. While space_held is
# true, _process re-reads the hovered card every frame and re-renders the overlay whenever it
# changes, so the player can hold Space and slide the mouse across the grid to flick through cards
# — and hovering empty space correctly shows nothing. The old design snapshotted the card on
# key-down and cached it in last_zoomed_card, which meant a later Space press over nothing
# re-showed a stale card (possibly from a different set or menu entirely).
var space_held : bool = false
# The card the overlay is currently showing, so _process only rebuilds it when the hover changes
var zoomed_card : TextureRect = null

# RichTextLabel showing the per-set deck breakdown (created in _ready).
var set_breakdown_label : RichTextLabel = null

# ─── Card search state ───────────────────────────────────────────────────────

# The search / filter screen, while it is open (freed on confirm or cancel)
var search_overlay : CardSearchOverlay = null

# True once a search has been run and the grid is showing results instead of a single set.
# While true the set name and the < > set-switch buttons stay hidden and the search button
# reads "CLEAR SEARCH".
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
# Opens the card search screen — doubles as "CLEAR SEARCH" while results are showing
@onready var search_btn        : Button = $search_button

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# Start background music — loops until scene changes
	SoundManagerScript.play_bgm("res://Audio/BGM/coin_mode (TCG GB Water Club).ogg", true)
	
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
	_wrap_grid_in_scroll_container()

	# Load the player's current deck
	_load_deck(current_deck_name)

	# ── Energy icon setup ──
	# Build the convenience dictionaries that map type name → node.
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
	_create_set_breakdown_label()
	_update_set_breakdown_label()

	# Display the starting set
	await get_tree().process_frame
	_display_current_set()


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
	grey_sb.set_corner_radius_all(5)
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
				_card_metadata_cache[cid] = {
					"name": card.get("name", ""),
					"supertype": card.get("supertype", ""),
					"subtypes": card.get("subtypes", []),
					"types": card.get("types", []),
					"evolvesFrom": card.get("evolvesFrom", ""),
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
	# TEMP TESTING: ignore group/ownership limits so any number of any card is allowed.
	if TESTING_UNLIMITED_DECKS:
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
	for style_name in ENERGY_STYLES.keys():
		var card_ids : Array = ENERGY_STYLES[style_name]
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


## Updates the 6 energy icon TextureRects to show images from the
## currently selected energy style.  Each icon loads the "Small" version
## of its card image from the Image_Assets/Card_Image_Library folder.
func _update_energy_icons() -> void:
	if not ENERGY_STYLES.has(current_energy_style):
		current_energy_style = "Base1"

	var card_ids : Array = ENERGY_STYLES[current_energy_style]
	# card_ids is ordered: grass, fire, water, lightning, psychic, fighting
	# ENERGY_TYPES is in the same order, so index i lines up
	for i in range(ENERGY_TYPES.size()):
		var energy_type : String = ENERGY_TYPES[i]
		var card_id     : String = card_ids[i]
		var card_set := card_id.split("-")[0]
		var image_path := "res://Image_Assets/Card_Image_Library/" + card_set + "/Small/" + card_id + ".png"
		var tex = load(image_path)
		if tex != null:
			energy_icons[energy_type].texture = tex


## Refreshes the count labels and glow animations on all 6 energy icons
## based on the current deck contents.  Called at startup and whenever the
## deck changes (load, empty, etc.).
func _refresh_energy_icons_from_deck() -> void:
	if not ENERGY_STYLES.has(current_energy_style):
		return

	var card_ids : Array = ENERGY_STYLES[current_energy_style]
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
	var card_id : String = ENERGY_STYLES[current_energy_style][type_index]
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

	# ── Semi-transparent backdrop ──
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.z_index = 55   # above the border so the dimming covers everything
	energy_picker_overlay.add_child(backdrop)

	# ── Title label ──
	var title := Label.new()
	var kenney_theme = load("res://UI_Themes/kenneyUI.tres")
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
	picker_scroll.z_index = 0
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
	var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
	if green_theme:
		picker_save_btn.theme = green_theme
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
	var red_theme = load("res://UI_Themes/kenneyUI-red.tres")
	if red_theme:
		picker_cancel_btn.theme = red_theme
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
	for style_name in ENERGY_STYLES.keys():
		var is_unlocked : bool = style_name in available_styles
		var card_ids : Array = ENERGY_STYLES[style_name]

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


## Reads player_progress.json and returns the array of unlocked energy style
## names.  This determines which rows appear in the picker.
func _get_unlocked_energy_styles() -> Array:
	var file := FileAccess.open(PLAYER_PROGRESS_PATH, FileAccess.READ)
	if file == null:
		return ["Base1"]
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary and data.has("energy_styles"):
		return data["energy_styles"]
	return ["Base1"]


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
	if old_style != new_style and ENERGY_STYLES.has(old_style) and ENERGY_STYLES.has(new_style):
		var old_ids : Array = ENERGY_STYLES[old_style]
		var new_ids : Array = ENERGY_STYLES[new_style]
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

## Returns a stage integer for sorting: Stage 2 = 2, Stage 1 = 1, Basic = 0, Baby = -1.
func _get_card_stage(card_id: String) -> int:
	var meta = _get_card_meta(card_id)
	if meta == null:
		return 0
	var subtypes : Array = meta.get("subtypes", [])
	if "Stage 2" in subtypes:
		return 2
	if "Stage 1" in subtypes:
		return 1
	if "Baby" in subtypes:
		return -1
	return 0


## Returns sort priority for a Trainer subtype: 0 = Normal, 1 = Stadium, 2 = Tool.
func _get_trainer_subtype_priority(card_id: String) -> int:
	var meta = _get_card_meta(card_id)
	if meta == null:
		return 0
	var subtypes : Array = meta.get("subtypes", [])
	if "Stadium" in subtypes:
		return 1
	if "Tool" in subtypes or "Pokémon Tool" in subtypes:
		return 2
	return 0


## Sorts energy card_ids: Special Energy first, then Basic, alphabetically within each.
func _sort_energy_viewer(energy_ids: Array) -> Array:
	var special : Array = []
	var basic   : Array = []
	for cid in energy_ids:
		var meta = _get_card_meta(cid)
		if meta != null and "Special" in meta.get("subtypes", []):
			special.append(cid)
		else:
			basic.append(cid)
	var name_sort := func(a: String, b: String) -> bool:
		var ma = _get_card_meta(a)
		var mb = _get_card_meta(b)
		var na : String = ma.get("name", a) if ma != null else a
		var nb : String = mb.get("name", b) if mb != null else b
		return na < nb
	special.sort_custom(name_sort)
	basic.sort_custom(name_sort)
	return special + basic


## Sorts trainer card_ids: Normal → Stadium → Tool, alphabetically within each group.
func _sort_trainers_viewer(trainer_ids: Array) -> Array:
	trainer_ids.sort_custom(func(a: String, b: String) -> bool:
		var pa : int = _get_trainer_subtype_priority(a)
		var pb : int = _get_trainer_subtype_priority(b)
		if pa != pb:
			return pa < pb
		var ma = _get_card_meta(a)
		var mb = _get_card_meta(b)
		var na : String = ma.get("name", a) if ma != null else a
		var nb : String = mb.get("name", b) if mb != null else b
		return na < nb
	)
	return trainer_ids


## Groups Pokémon in one type bucket into evolution families, then sorts:
##   Segments ordered by max_stage DESC; standalones before families of same max_stage.
##   Within a family: Stage 2 → Stage 1 → Basic → Baby.
func _sort_type_group_pokemon(type_ids: Array) -> Array:
	if type_ids.is_empty():
		return type_ids

	# name → [card_ids] for cards in this group
	var name_to_ids : Dictionary = {}
	for cid in type_ids:
		var meta = _get_card_meta(cid)
		var cname : String = meta.get("name", cid) if meta != null else cid
		if not name_to_ids.has(cname):
			name_to_ids[cname] = []
		(name_to_ids[cname] as Array).append(cid)

	# Union-find: group_of[cid] = representative id
	var group_of : Dictionary = {}
	for cid in type_ids:
		group_of[cid] = cid

	# Three passes handles Stage 2 chains (Basic→Stage1→Stage2)
	for _pass in range(3):
		for cid in type_ids:
			var meta = _get_card_meta(cid)
			if meta == null:
				continue
			var from_name : String = meta.get("evolvesFrom", "")
			if from_name == "" or not name_to_ids.has(from_name):
				continue
			# Path-compress my root
			var my_root : String = group_of[cid]
			while group_of[my_root] != my_root:
				my_root = group_of[my_root]
			# Union with each "from" card's root
			for from_cid in (name_to_ids[from_name] as Array):
				var from_root : String = group_of[from_cid]
				while group_of[from_root] != from_root:
					from_root = group_of[from_root]
				if my_root != from_root:
					group_of[from_root] = my_root

	# Path-compress all
	for cid in type_ids:
		var root : String = group_of[cid]
		while group_of[root] != root:
			root = group_of[root]
		group_of[cid] = root

	# Build segments keyed by root
	var segments : Dictionary = {}
	for cid in type_ids:
		var root : String = group_of[cid]
		if not segments.has(root):
			segments[root] = []
		(segments[root] as Array).append(cid)

	# Build segment metadata and sort cards within each segment by stage DESC
	var segment_list : Array = []
	for root in segments:
		var seg_cards : Array = segments[root]
		var max_stage : int = -99
		for cid in seg_cards:
			var s : int = _get_card_stage(cid)
			if s > max_stage:
				max_stage = s
		seg_cards.sort_custom(func(a: String, b: String) -> bool:
			return _get_card_stage(a) > _get_card_stage(b)
		)
		segment_list.append({
			"cards":       seg_cards,
			"max_stage":   max_stage,
			"standalone":  seg_cards.size() == 1,
			"first_name":  (_get_card_meta(seg_cards[0]).get("name", "") if _get_card_meta(seg_cards[0]) != null else ""),
		})

	# Sort segments: max_stage DESC → standalone first (true > false) → name ASC
	segment_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["max_stage"] != b["max_stage"]:
			return a["max_stage"] > b["max_stage"]
		if a["standalone"] != b["standalone"]:
			return a["standalone"]  # true sorts before false
		return a["first_name"] < b["first_name"]
	)

	var result : Array = []
	for seg in segment_list:
		result.append_array(seg["cards"])
	return result


## Returns the full sorted card_id list for the current deck, ready for the viewer.
## Order: Pokémon by type → Trainers (Normal/Stadium/Tool) → Energy (Special/Basic).
func _sort_deck_for_viewer() -> Array:
	var pokemon_by_type : Dictionary = {}
	var trainer_ids     : Array      = []
	var energy_ids      : Array      = []

	for card_id in deck_cards:
		_ensure_set_metadata_loaded(card_id.split("-")[0])
		var meta = _get_card_meta(card_id)
		if meta == null:
			continue
		var supertype : String = meta.get("supertype", "")
		if supertype == "Pokémon":
			var types  : Array  = meta.get("types", [])
			var ptype  : String = types[0] if types.size() > 0 else "Colorless"
			if not pokemon_by_type.has(ptype):
				pokemon_by_type[ptype] = []
			(pokemon_by_type[ptype] as Array).append(card_id)
		elif supertype == "Trainer":
			trainer_ids.append(card_id)
		elif supertype == "Energy":
			energy_ids.append(card_id)

	var result : Array = []
	for ptype in POKEMON_TYPE_DISPLAY_ORDER:
		if pokemon_by_type.has(ptype):
			result.append_array(_sort_type_group_pokemon(pokemon_by_type[ptype]))
	result.append_array(_sort_trainers_viewer(trainer_ids))
	result.append_array(_sort_energy_viewer(energy_ids))
	return result


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
	add_child(deck_viewer_overlay)

	var backdrop := ColorRect.new()
	backdrop.color          = Color(0, 0, 0, 0.55)
	backdrop.anchor_right   = 1.0
	backdrop.anchor_bottom  = 1.0
	backdrop.z_index        = 55
	deck_viewer_overlay.add_child(backdrop)

	var kenney_theme = load("res://UI_Themes/kenneyUI.tres")

	var title := Label.new()
	if kenney_theme:
		title.theme = kenney_theme
	var _viewer_deck_name : String = current_deck_name if current_deck_name != "" else "DECK"
	title.text                    = _viewer_deck_name + "  (" + str(total_deck_count) + " cards)"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	title.position                = Vector2(200, 35)
	title.size                    = Vector2(1200, 50)
	title.z_index                 = 55
	deck_viewer_overlay.add_child(title)

	var viewer_scroll := ScrollContainer.new()
	viewer_scroll.position              = Vector2(5, 110)
	viewer_scroll.size                  = Vector2(1676, 969)
	viewer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	viewer_scroll.vertical_scroll_mode  = ScrollContainer.SCROLL_MODE_AUTO
	viewer_scroll.z_index               = 0
	viewer_scroll.clip_contents         = true
	deck_viewer_overlay.add_child(viewer_scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",   0)
	margin.add_theme_constant_override("margin_right",  0)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	viewer_scroll.add_child(margin)

	var viewer_grid := GridContainer.new()
	viewer_grid.columns                 = COLUMNS
	viewer_grid.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	viewer_grid.add_theme_constant_override("h_separation", CARD_H_SEP)
	viewer_grid.add_theme_constant_override("v_separation", CARD_V_SEP)
	margin.add_child(viewer_grid)

	var close_btn := Button.new()
	close_btn.text                = "close"
	close_btn.custom_minimum_size = Vector2(226, 63)
	close_btn.position            = Vector2(1689, 1003)
	close_btn.z_index             = 55
	var red_theme = load("res://UI_Themes/kenneyUI-red.tres")
	if red_theme:
		close_btn.theme = red_theme
	close_btn.add_theme_font_size_override("font_size", 23)
	close_btn.pressed.connect(_close_deck_viewer)
	deck_viewer_overlay.add_child(close_btn)

	await get_tree().process_frame

	var sorted_ids : Array = _sort_deck_for_viewer()

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
			card_rect.mouse_filter              = Control.MOUSE_FILTER_IGNORE
			viewer_grid.add_child(card_rect)
			if not is_inside_tree():   # ISSUE #32 FIX: bail if freed mid-load
				return
			await get_tree().process_frame


## Closes and frees the deck viewer overlay, restoring normal UI.
## Always freed (not hidden) because the deck may have changed since it was built.
func _close_deck_viewer() -> void:
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
		# No image — just a black placeholder rectangle the exact card size.
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.08, 0.08, 0.08, 1.0)
		card_rect = placeholder
	else:
		var tex_rect := TextureRect.new()
		var card_set := card_id.split("-")[0]
		var image_path := "res://Image_Assets/Card_Image_Library/" + card_set + "/Small/" + card_id + ".png"
		var card_texture = load(image_path)
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
	label_bg.position = Vector2(0, CARD_SIZE.y - 22)
	label_bg.size = Vector2(CARD_SIZE.x, 22)
	label_bg.z_index = 10
	label_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var count_label := Label.new()
	var kenney_theme = load("res://UI_Themes/kenneyUI.tres")
	if kenney_theme:
		count_label.theme = kenney_theme
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	count_label.text = str(in_deck) + "/" + str(owned)
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.position = Vector2.ZERO
	count_label.size = Vector2(CARD_SIZE.x, 22)
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
	label.text = str(in_deck) + "/" + str(owned)
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
# The search button has two jobs depending on what the grid is showing:
#   normal set view  -> "SEARCH"       opens the filter screen
#   search results   -> "CLEAR SEARCH" throws the results away and goes back to set browsing
#
# Filter semantics: OR within a category, AND between categories, with the name box always ANDed
# on top as a case-insensitive substring. Only cards the player actually owns are ever returned —
# the blacked-out unowned placeholders that appear in the per-set view are skipped entirely.

func _on_search_pressed() -> void:
	if search_active:
		_clear_search()
		return
	_open_search_overlay()


func _open_search_overlay() -> void:
	if search_overlay != null:
		return
	if energy_picker_active or deck_viewer_active or load_popup != null:
		return

	# Hide the deck UI behind the search screen, the same way the energy picker does
	_set_ui_visibility(false)

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


## CANCEL / Escape on the search screen — throw the filters away and go back to whatever the deck
## builder was showing before (a normal set, or the previous results if a search was already active).
func _on_search_cancelled() -> void:
	_close_search_overlay()
	_set_ui_visibility(true)


## SEARCH pressed with at least one filter set. Runs the filter, and only switches the grid over to
## results mode if something actually matched — a search that finds nothing keeps the player on the
## filter screen with their selections intact so they can adjust them.
func _on_search_confirmed(criteria: Dictionary) -> void:
	var results := await _run_search(criteria)

	if results.is_empty():
		# The overlay may have been cancelled while the search was running
		if search_overlay != null:
			_show_deck_message("No cards found")
		return

	search_results = results
	search_active  = true
	search_btn.text = "CLEAR SEARCH"

	_close_search_overlay()
	_set_ui_visibility(true)
	await _display_search_results()


## Drops out of results mode and goes back to browsing the set the player was last on.
func _clear_search() -> void:
	if not search_active:
		return
	search_active = false
	search_results.clear()
	_search_load_token += 1        # abort any results build still in flight
	search_btn.text = "SEARCH"

	set_label.visible = true
	next_btn.visible  = true
	prev_btn.visible  = true

	_display_current_set()
	_reset_scroll_position()


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

	# ── Name (always AND, case-insensitive substring) ──
	var wanted_name : String = criteria.get("name", "")
	if wanted_name != "" and not (wanted_name in card_name.to_lower()):
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
		if not _card_matches_pokemon_sub(card_name, subtypes_lower, wanted_pokemon_subs):
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


## The three Pokemon sub types aren't all plain subtype lookups:
##   ex      — a real "ex" subtype
##   shining — the Neo "Shining <name>" cards AND the later gold Star cards, which the search
##             screen deliberately groups under one icon
##   delta   — the delta symbol in the printed name, matching card_object.is_delta()
func _card_matches_pokemon_sub(card_name: String, subtypes_lower: Array, wanted: Array) -> bool:
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
	return false


## RESERVED: card-effect matching for the effect filter row. Returns true for now so a criteria
## dictionary carrying effect keys can't silently filter everything out. Implement alongside
## CardSearchOverlay.EFFECT_FILTERS — the keys here are the same "key" values from that table.
func _card_matches_effect(_card_id: String, _wanted_effects: Array) -> bool:
	return true


## "set"  — release order, then card number within each set (what browsing a set already looks like)
## "name" — grouped by card name, then release order and card number within each name
func _sort_search_results(results: Array, sort_mode: String) -> void:
	# Position of each set in the dictionary's release order, so sorting never has to search the list
	var set_order : Dictionary = {}
	for i in range(set_list.size()):
		set_order[set_list[i]["set_id"]] = i

	if sort_mode == "name":
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


# ─── Empty deck ──────────────────────────────────────────────────────────────

## Asks the player to confirm before wiping the entire deck.
## Emptying a full 60-card deck by an accidental click is painful, so we gate
## the destructive action behind a Yes/No popup (styled like the load popup).
func _on_empty_deck_pressed() -> void:
	# Nothing to clear, and don't stack popups
	if total_deck_count == 0 or empty_confirm_popup != null:
		return

	var kenney_theme = load("res://UI_Themes/kenneyUI.tres")

	# CanvasLayer ensures the popup renders above everything else.
	empty_confirm_popup = CanvasLayer.new()
	empty_confirm_popup.layer = 100
	add_child(empty_confirm_popup)

	# Dim the screen behind the popup
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	empty_confirm_popup.add_child(overlay)

	# Centered panel
	var panel := PanelContainer.new()
	if kenney_theme:
		panel.theme = kenney_theme
	panel.custom_minimum_size = Vector2(460, 220)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -230
	panel.offset_top    = -110
	panel.offset_right  = 230
	panel.offset_bottom = 110
	empty_confirm_popup.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var msg := Label.new()
	msg.text = "Empty the entire deck?\nThis cannot be undone."
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 24)
	vbox.add_child(msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var yes_btn := Button.new()
	yes_btn.text = "Empty"
	yes_btn.custom_minimum_size = Vector2(130, 45)
	var red_theme = load("res://UI_Themes/kenneyUI-red.tres")
	if red_theme:
		yes_btn.theme = red_theme
	yes_btn.pressed.connect(
		func():
			_close_empty_confirm_popup()
			_do_empty_deck()
	)
	btn_row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "Cancel"
	no_btn.custom_minimum_size = Vector2(130, 45)
	var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
	if green_theme:
		no_btn.theme = green_theme
	no_btn.pressed.connect(_close_empty_confirm_popup)
	btn_row.add_child(no_btn)


func _close_empty_confirm_popup() -> void:
	if empty_confirm_popup != null:
		empty_confirm_popup.queue_free()
		empty_confirm_popup = null


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
	# != DECK_SIZE, ignoring TESTING_UNLIMITED_DECKS) — they all live in _deck_save_blocker() now.
	var blocker := _deck_save_blocker()
	if blocker != "":
		print("ISSUE #84 FIX ACTIVE: save refused — ", blocker)
		_show_deck_message(blocker)
		return

	if not _is_deck_dirty():
		print("ISSUE #84 FIX ACTIVE: save refused — no changes since the last save")
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

## Returns to the main menu. The last set viewed is saved so the player
## returns to the same set next time they open the deck builder.
func _on_cancel_pressed() -> void:
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


# ─── Input handling (Escape + Spacebar zoom) ────────────────────────────────

## Handles global keyboard input for the deck build screen.
## - Escape: closes zoom if active, otherwise returns to main menu
## - Spacebar press: zooms into the hovered card's large image
## - Spacebar release: closes the zoom overlay and restores UI
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_update_set_breakdown_label()

	if not event is InputEventKey:
		return

	# ── Escape key ──
	if event.pressed and event.keycode == KEY_ESCAPE:
		# If zoomed in, close the zoom instead of leaving the scene
		if is_zoomed:
			# Drop the hold too, or _process would immediately re-open the preview (ISSUE #13)
			space_held = false
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
		# If the search screen is open, close it without searching
		if search_overlay != null:
			_on_search_cancelled()
			return
		# Showing search results — the first Escape drops back to normal set browsing,
		# a second one then leaves the deck builder as usual
		if search_active:
			_clear_search()
			return
		_on_cancel_pressed()

	# ── Spacebar hold-to-preview ──
	if event.keycode == KEY_SPACE:
		if event.pressed and not event.is_echo():
			# Key just went down (not a held-key repeat) — start following the mouse
			# Don't preview if a popup or picker is open, or the deck name field has focus
			if load_popup != null:
				return
			if energy_picker_active:
				return
			if deck_viewer_active:
				return
			if search_overlay != null:
				return          # typing in the search name box must not trigger the preview
			if deck_name_edit.has_focus():
				return
			# Space is also the default "ui_accept" action, so an unhandled key here would
			# fall through to whichever button last had focus (e.g. "Empty Deck") and press
			# it too. Consume the event so hovering a card to preview it never re-triggers
			# the last-focused button.
			get_viewport().set_input_as_handled()
			space_held = true
			print("ISSUE #13 FIX ACTIVE (deck view spacebar): preview now follows the mouse while Space is held")
			_refresh_hover_preview()
		elif not event.pressed:
			# Key released — stop following and close the preview
			get_viewport().set_input_as_handled()
			space_held = false
			_hide_zoom()


## ISSUE #13: while Space is held, keep the preview locked to whatever card the mouse is over.
func _process(_delta: float) -> void:
	if space_held:
		_refresh_hover_preview()


## Shows the hovered card (swapping the overlay if the hover moved to a different card), or hides
## the preview entirely when the mouse isn't over a card.
func _refresh_hover_preview() -> void:
	var card := _get_hovered_card()
	if card == zoomed_card:
		return
	_hide_zoom()
	if card != null:
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


## Shows a zoomed-in view of the given card.
## Creates a CanvasLayer overlay (layer 150, above everything including the
## load popup at layer 100) with a dimmed background and the large card image
## displayed at 600×825. Also hides all UI elements except the borders and
## background scroller so the card is the sole focus.
func _show_zoom(card_rect: TextureRect) -> void:
	if is_zoomed:
		return

	var card_id : String = card_rect.get_meta("card_id")
	var card_set := card_id.split("-")[0]
	# Build path to the LARGE version of the card image
	var large_path := "res://Image_Assets/Card_Image_Library/" + card_set + "/Large/" + card_id + ".png"
	var large_texture : Texture2D = load(large_path)
	if large_texture == null:
		push_error("DeckBuild: missing large card image " + large_path)
		return

	is_zoomed = true
	zoomed_card = card_rect

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

	# The large card image, sized to fill most of vertical space (~50px margin top/bottom)
	var tex_size  := large_texture.get_size()
	var target    := Vector2(1000.0, 980.0)
	var s         := minf(target.x / tex_size.x, target.y / tex_size.y)
	var disp_size := Vector2(tex_size.x * s, tex_size.y * s)

	var zoom_card := TextureRect.new()
	zoom_card.texture      = large_texture
	zoom_card.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	zoom_card.stretch_mode = TextureRect.STRETCH_SCALE
	zoom_card.size         = disp_size
	zoom_card.position     = Vector2((1920.0 - disp_size.x) / 2.0, (1080.0 - disp_size.y) / 2.0)
	zoom_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.add_child(zoom_card)


## Removes the zoom overlay and restores all UI elements.
func _hide_zoom() -> void:
	if not is_zoomed:
		return

	is_zoomed = false
	zoomed_card = null

	if zoom_overlay != null:
		zoom_overlay.queue_free()
		zoom_overlay = null



# ─── UI helpers ──────────────────────────────────────────────────────────────

## Updates the "XX/60" label in the top bar.
func _update_deck_count_label() -> void:
	deck_count_label.text = str(total_deck_count) + "/" + str(DECK_SIZE)
	_update_set_breakdown_label()


## Creates the RichTextLabel used for the per-set deck breakdown.
## Positioned just below the energy count labels (y≈700) and above the save
## button (y=902), spanning the full right-panel width.
func _create_set_breakdown_label() -> void:
	set_breakdown_label = RichTextLabel.new()
	set_breakdown_label.bbcode_enabled = true
	set_breakdown_label.scroll_active  = false
	set_breakdown_label.fit_content    = true
	set_breakdown_label.position       = Vector2(1690.0, 544.0)
	set_breakdown_label.size           = Vector2(230.0, 112.0)
	set_breakdown_label.z_index        = 200
	set_breakdown_label.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	var kenney_theme = load("res://UI_Themes/kenneyUI.tres")
	if kenney_theme:
		set_breakdown_label.theme = kenney_theme
	set_breakdown_label.add_theme_font_size_override("normal_font_size", 14)
	set_breakdown_label.add_theme_constant_override("outline_size", 2)
	set_breakdown_label.add_theme_color_override("font_outline_color", Color(0.85, 0.85, 0.85, 0.75))
	set_breakdown_label.add_theme_constant_override("paragraph_separation", 1)
	add_child(set_breakdown_label)


## Returns a display-friendly version of a set name for the breakdown label.
## Strips a leading "EX " prefix (any case) and shortens "Team" to "Tm".
func _format_set_name_for_breakdown(raw_name: String) -> String:
	var name := raw_name
	if name.length() > 3 and name.substr(0, 3).to_lower() == "ex ":
		name = name.substr(3)
	name = name.replace("Team ", "Tm ")
	return name.strip_edges()


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
		deck_count_label,
		change_energy_btn,
		view_deck_btn,
		search_btn,
	]

	for energy_type in ENERGY_TYPES:
		nodes_to_toggle.append(energy_icons[energy_type])
		nodes_to_toggle.append(energy_labels[energy_type])

	if set_breakdown_label != null:
		nodes_to_toggle.append(set_breakdown_label)

	for node in nodes_to_toggle:
		if node != null and is_instance_valid(node):
			node.visible = visible_flag

	# In search-results mode the grid isn't showing a single set, so the set name and the < >
	# switch buttons must stay hidden even when the rest of the UI is being restored.
	if visible_flag and search_active:
		set_label.visible = false
		next_btn.visible  = false
		prev_btn.visible  = false


## Rebuilds the per-set type breakdown from deck_cards.
## Layout per set: set name on its own line (header), then all coloured count
## tokens on the line below.  A 5 px spacer separates each set block.
##   - Pokémon grouped by first type, in that type's colour
##   - Trainers + Special Energies combined in light grey
##   - Basic Energies omitted (shown by the energy icon section)
## Safe to call before the label is created — exits silently.
func _update_set_breakdown_label() -> void:
	if set_breakdown_label == null:
		return

	# Accumulate counts: set_id → { type_category → count }
	var set_type_counts : Dictionary = {}

	for card_id in deck_cards:
		var count : int = deck_cards[card_id]
		var set_id : String = card_id.split("-")[0]
		var meta = _get_card_meta(card_id)
		if meta == null:
			continue

		var supertype : String = meta["supertype"]
		var subtypes  : Array  = meta["subtypes"]
		var types     : Array  = meta.get("types", [])

		var category : String
		if supertype == "Pokémon":
			category = types[0] if types.size() > 0 else "Colorless"
		elif supertype == "Trainer":
			category = "__trainer__"
		elif supertype == "Energy":
			if "Special" in subtypes:
				category = "__trainer__"
			else:
				continue  # basic energy shown via energy icon counts
		else:
			continue

		if not set_type_counts.has(set_id):
			set_type_counts[set_id] = {}
		var tgt : Dictionary = set_type_counts[set_id]
		tgt[category] = tgt.get(category, 0) + count

	# Fixed type order: alphabetical Pokémon types, then Trainer/Special last
	var type_order : Array = [
		"Colorless", "Darkness", "Fighting", "Fire", "Grass",
		"Lightning", "Metal", "Psychic", "Water", "__trainer__"
	]

	# Each set is its own [p align=center] paragraph — paragraph_separation
	# (set as a theme constant in _create_set_breakdown_label) controls the
	# inter-set gap in real pixels, while the \n inside the paragraph keeps
	# the set name and its counts tight together.
	var bbcode := ""
	for entry in set_list:
		var set_id : String = entry["set_id"]
		if not set_type_counts.has(set_id):
			continue
		var counts       : Dictionary = set_type_counts[set_id]
		var display_name : String     = _format_set_name_for_breakdown(entry["set_name"])

		var count_line := ""
		for type_key in type_order:
			if counts.has(type_key):
				var hex : String = TYPE_COLOR_HEX.get(type_key, "#ffffff")
				if count_line != "":
					count_line += " "
				count_line += "[color=" + hex + "]" + str(counts[type_key]) + "[/color]"

		bbcode += "[p align=center][color=#ffffff]" + display_name + "[/color]\n"
		bbcode += "[font_size=18]" + count_line + "[/font_size][/p]"

	set_breakdown_label.text = bbcode


## Called every time the player types or deletes in the deck name field.
## text_changed passes the new text as an argument but we just need to
## re-evaluate whether the save button should be enabled or disabled.
func _on_deck_name_changed(_new_text: String) -> void:
	_refresh_save_button()


# ─── Floating message (ISSUE #84) ────────────────────────────────────────────
# TWEAKABLE VALUES for the floating message shown when a save is refused.
const MSG_ANCHOR_Y       := 0.82    # vertical screen position, as a fraction of screen height
const MSG_HEIGHT         := 60.0    # strip height the text is centred in
const MSG_FONT_SIZE      := 34
const MSG_RISE_PIXELS    := 120.0   # how far it drifts upward
const MSG_RISE_SECONDS   := 2.0     # drift duration
const MSG_FADE_SECONDS   := 1.6     # fade duration (starts with the drift)
const MSG_COLOUR         := Color(1.0, 0.45, 0.45)

var _deck_message_label: Label = null

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
	lbl.z_index = 100
	var kenney_theme = load("res://UI_Themes/kenneyUI.tres")
	if kenney_theme:
		lbl.theme = kenney_theme
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
##   1) card count — must be exactly 60 (relaxed to "at least 1" while TESTING_UNLIMITED_DECKS is on)
##   2) at least one Basic Pokemon — enforced even in testing mode, because a deck with no Basic
##      cannot be set up at the start of a match at all, so saving one is never useful
##   3) a deck name has been entered
func _deck_save_blocker() -> String:
	if TESTING_UNLIMITED_DECKS:
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
	if can_save:
		var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
		if green_theme:
			save_btn.theme = green_theme
	else:
		save_btn.theme = load("res://UI_Themes/kenneyUI.tres")


# ─── Load deck popup ────────────────────────────────────────────────────────

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
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	load_popup.add_child(overlay)

	# Main panel — centered on screen
	var panel := PanelContainer.new()
	var kenney_theme = load("res://UI_Themes/kenneyUI.tres")
	if kenney_theme:
		panel.theme = kenney_theme
	panel.custom_minimum_size = Vector2(500, 600)
	panel.anchor_left   = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -250
	panel.offset_top    = -300
	panel.offset_right  = 250
	panel.offset_bottom = 300
	load_popup.add_child(panel)

	# Vertical layout inside the panel
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title_label := Label.new()
	title_label.text = "Load a Deck"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title_label)

	# Scrollable list of decks
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 5)
	scroll.add_child(list_vbox)

	# Track which deck is currently highlighted.
	# Using a Dictionary because GDScript lambdas capture objects by reference
	# but Strings by value — so a plain String variable updated in one lambda
	# would not be visible to another lambda. The Dictionary acts as a shared
	# mutable container that both lambdas can read and write.
	var selection := {"deck_name": "", "button": null}

	# Create a button for each deck file
	for deck_name in deck_files:
		var btn := Button.new()
		btn.text = deck_name.replace("_", " ")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if kenney_theme:
			btn.theme = kenney_theme
		btn.custom_minimum_size = Vector2(440, 40)
		# When clicked, highlight this button and store the deck name
		btn.pressed.connect(
			func():
				# Un-highlight previous selection
				if selection["button"] != null and is_instance_valid(selection["button"]):
					selection["button"].theme = kenney_theme
				# Highlight new selection
				var blue_theme = load("res://UI_Themes/kenneyUI-blue.tres")
				if blue_theme:
					btn.theme = blue_theme
				selection["button"] = btn
				selection["deck_name"] = deck_name
		)
		list_vbox.add_child(btn)

	# Bottom row: Load + Cancel buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	var load_confirm_btn := Button.new()
	load_confirm_btn.text = "Load"
	load_confirm_btn.custom_minimum_size = Vector2(120, 45)
	var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
	if green_theme:
		load_confirm_btn.theme = green_theme
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
	cancel_popup_btn.custom_minimum_size = Vector2(120, 45)
	var red_theme = load("res://UI_Themes/kenneyUI-red.tres")
	if red_theme:
		cancel_popup_btn.theme = red_theme
	cancel_popup_btn.pressed.connect(_close_load_popup)
	btn_row.add_child(cancel_popup_btn)


## Removes the load-deck popup from the scene tree.
func _close_load_popup() -> void:
	if load_popup != null:
		load_popup.queue_free()
		load_popup = null
