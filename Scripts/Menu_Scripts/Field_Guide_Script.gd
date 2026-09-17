extends Control

## THE FIELD GUIDE — every Pokémon in the game, and which of them the player has met.
##
## Built as a sibling of the costume grid (Costume_Script.gd): same square-cell
## pattern, same Show-all / Show-met filter, same hold-Shift preview, same loading
## overlay. It differs in three ways, and all three are why it is its own screen
## rather than a mode of that one:
##
##   * nothing is selectable and nothing is saved — it is a record, not a picker,
##     so there is no Save button and no selection pulse;
##   * each cell carries TWO sprites, the big Field Guide portrait in the middle
##     and the species' own overworld walk-cycle frame small in the bottom-right;
##   * the entries come from GameState's Nature guide rather than from progress.
##
## "Met" is only ever set by fishing today (Fishing_Minigame._on_catch_message_ok);
## anything else that meets a Pokémon calls GameState.record_pokemon_met() and this
## screen picks it up with no changes.

# ─── Constants ───────────────────────────────────────────────────────────────

## EIGHT columns, not the costume grid's nine: a cell has to hold "019 RATTATA
## (ALOLAN)" across its foot, and at 200px that caption clips on half the dex.
##   8 * 228 + 7 * 12 = 1908, inside the 1920 band with room for the scrollbar.
const COLUMNS            := 8
const CELL_SIZE          := Vector2(228.0, 228.0)
const SPRITE_SEPARATION  := 12

## TWEAKABLE. How much of the cell the portrait is drawn at, and how far up it is
## nudged so the caption across the foot is not sitting on its feet.
const PORTRAIT_FIT       := 0.80
const PORTRAIT_LIFT      := 12.0

## TWEAKABLE. The overworld sprite in the bottom-right, as a fraction of the
## portrait — the brief asks for "about 5x smaller", and it is inset from the
## cell's corner by MINI_INSET so it sits inside the box's rounded edge.
const MINI_FRACTION      := 0.20
const MINI_INSET         := Vector2(10.0, 26.0)
## Row 2 of a 4x4 overworld sheet is idle_right (OverworldPokemon.ROWS).
const MINI_ROW           := 2

## TWEAKABLE. The caption band across the foot of the cell.
const CAPTION_H          := 30.0
const CAPTION_FONT       := 16
const CAPTION_BOTTOM     := 8.0

const GRID_INSET_X       := 0.0
const GRID_INSET_Y       := 18.0
const FILTER_BTN_W       := 340.0

# ─── State ───────────────────────────────────────────────────────────────────

## species basename -> met count. Read once on entry; nothing on this screen
## writes to it.
var _met                 : Dictionary = {}
var _total_species       : int = 0

## The screen opens on the met list, the same way the costume grid opens on the
## owned wardrobe: building 350 blacked-out silhouettes to show a player who has
## caught two fish is a second of loading for nothing. Deliberately not persisted.
var _hide_unmet          : bool = true
var _is_rebuilding       : bool = false

var _count_chip_holder   : Control = null
var _loading_overlay     : MenuLoadingOverlay = MenuLoadingOverlay.new()

# ─── Zoom state (hold Shift, as on every other card/grid screen) ─────────────
var zoom_overlay         : CanvasLayer = null
var is_zoomed            : bool = false
var zoom_held            : bool = false
var zoomed_entry         : Control = null
var zoom_image           : TextureRect = null
var zoom_caption         : Label = null

# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid        : GridContainer = $"guide_grid_container"
@onready var cancel_btn  : Button        = $"guide_cancel_button"
@onready var hide_btn    : Button        = $"hide_button"
@onready var audio_player = AudioStreamPlayer.new()

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	add_child(audio_player)
	var audio_stream = load(SoundManagerScript.BGM_COIN_MODE)
	if audio_stream != null:
		audio_player.stream = audio_stream
		audio_player.bus = SoundManagerScript.MUSIC_BUS
		audio_player.stream.loop = true
		audio_player.play()

	_met = GameState.get_met_pokemon()

	cancel_btn.pressed.connect(_on_cancel_pressed)
	hide_btn.pressed.connect(_on_hide_pressed)
	_refresh_hide_button()

	_build_chrome()
	_wrap_grid_in_scroll_container()

	# Same contract as the costume grid: the filter lives in the strip the loading
	# blocker leaves clickable, so it has to be disabled by hand while a build runs.
	hide_btn.disabled = true
	_loading_overlay.show_for_library(self)
	await get_tree().process_frame
	await _load_entries()
	_loading_overlay.hide()
	if not is_inside_tree():
		return
	hide_btn.disabled = false


# ─── Chrome ──────────────────────────────────────────────────────────────────

func _build_chrome() -> void:
	var bars := UIKit.convert_legacy_screen(self, "Field guide")

	_count_chip_holder = bars["header"].left
	_refresh_count_chip()

	UIKit.adopt_button(hide_btn, bars["header"].right, "secondary", false)
	hide_btn.custom_minimum_size.x = FILTER_BTN_W

	UIKit.adopt_button(cancel_btn, bars["footer"].centre, "secondary")

	grid.position = Vector2(GRID_INSET_X, UIKit.CONTENT_TOP + GRID_INSET_Y)
	grid.size = Vector2(1920.0 - GRID_INSET_X * 2.0, UIKit.CONTENT_H - GRID_INSET_Y * 2.0)


## "n / N" met. The MET COUNT PER SPECIES IS DELIBERATELY NOT SHOWN anywhere on
## this screen — it is recorded so it can be surfaced later, and until there is a
## reason for the player to see it, an entry is simply met or not.
func _refresh_count_chip() -> void:
	if _count_chip_holder == null or not is_instance_valid(_count_chip_holder):
		return
	for c in _count_chip_holder.get_children():
		c.queue_free()
	_count_chip_holder.add_child(
		UIKit.make_chip("%d / %d" % [_met.size(), _total_species], "on_chrome"))


func _wrap_grid_in_scroll_container() -> void:
	var parent = grid.get_parent()

	var scroll := ScrollContainer.new()
	scroll.name = "guide_scroll_container"
	scroll.position = grid.position
	scroll.size = grid.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO

	parent.remove_child(grid)
	parent.add_child(scroll)
	scroll.add_child(grid)

	grid.position = Vector2.ZERO
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", SPRITE_SEPARATION)
	grid.add_theme_constant_override("v_separation", SPRITE_SEPARATION)


# ─── Entry loading ───────────────────────────────────────────────────────────

func _load_entries() -> void:
	# all_species() is the Overworld_Sprites listing, and Field_Guide_Sprites is
	# keyed by exactly the same basenames — one species, one name, two folders.
	var species_list: Array = OverworldPokemonData.all_species()
	species_list.sort_custom(func(a, b):
		var da := OverworldPokemonData.dex_number(a)
		var db := OverworldPokemonData.dex_number(b)
		if da != db:
			return da < db
		return str(a).naturalnocasecmp_to(str(b)) < 0)

	_total_species = species_list.size()
	_refresh_count_chip()

	for species in species_list:
		if not is_inside_tree():
			return
		# Met-only mode skips the rest BEFORE the per-entry frame yield below, which
		# is the whole of the speed-up — the yield is what makes a full build slow.
		if _hide_unmet and not _met.has(species):
			continue
		_add_entry_to_grid(String(species))
		await get_tree().process_frame


## One square cell. The grid child is a WRAPPER Control, never a TextureRect: the
## box, the portrait, the overworld sprite and the caption are four things and
## only the wrapper is allowed to be the cell.
func _add_entry_to_grid(species: String) -> void:
	var portrait := load(OverworldPokemonData.field_guide_path(species)) as Texture2D
	if portrait == null:
		return

	var is_met: bool = _met.has(species)

	var cell := Control.new()
	cell.custom_minimum_size = CELL_SIZE
	cell.size                = CELL_SIZE
	cell.clip_contents       = false
	cell.pivot_offset        = CELL_SIZE / 2.0
	cell.set_meta("species", species)
	cell.set_meta("is_met",  is_met)
	cell.set_meta("portrait", portrait)

	# The box, behind everything, sized in real pixels — an anchored slot would
	# still be 0x0 on this frame.
	var slot := UIKit.make_slot(CELL_SIZE)
	slot.position = Vector2.ZERO
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(slot)

	# The portrait: explicit fit maths, never the layout engine. minf, not maxf —
	# a Pokémon must be wholly visible, not cropped to fill.
	var tex_size := portrait.get_size()
	var fit : float = minf(CELL_SIZE.x / tex_size.x, CELL_SIZE.y / tex_size.y) * PORTRAIT_FIT
	var disp := Vector2(tex_size.x * fit, tex_size.y * fit)

	var art := TextureRect.new()
	art.texture      = portrait
	art.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.size         = disp
	art.custom_minimum_size = disp
	art.position     = Vector2((CELL_SIZE.x - disp.x) / 2.0,
			(CELL_SIZE.y - disp.y) / 2.0 - PORTRAIT_LIFT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(art)

	# The overworld walk-cycle frame, ~5x smaller, pinned bottom-right. It is
	# allowed to overlap a big portrait: on a Wailord there is no clear corner to
	# sit in, and the alternative is shrinking every portrait to make room for it.
	var mini := _make_mini_sprite(species, disp.x * MINI_FRACTION)
	if mini != null:
		mini.position = Vector2(CELL_SIZE.x - mini.size.x - MINI_INSET.x,
				CELL_SIZE.y - mini.size.y - MINI_INSET.y)
		cell.add_child(mini)

	# Caption LAST so it draws in front of both sprites — sibling order is z-order.
	var caption := Label.new()
	UIKit.set_label(caption, "small_label", OverworldPokemonData.guide_label(species),
			"field_fg", CAPTION_FONT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	caption.clip_text            = true
	caption.position = Vector2(4.0, CELL_SIZE.y - CAPTION_H - CAPTION_BOTTOM)
	caption.size     = Vector2(CELL_SIZE.x - 8.0, CAPTION_H)
	cell.add_child(caption)

	if is_met:
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		# Keep the real texture but zero out all RGB channels — that turns the
		# sprite into a solid silhouette with no texture swap. It is each SPRITE
		# that is blacked out, never the cell: modulate propagates to children and
		# would take the box outline and the caption down with it.
		art.self_modulate = Color(0, 0, 0, 1)
		if mini != null:
			mini.self_modulate = Color(0, 0, 0, 1)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

	grid.add_child(cell)


## Frame 0 of the idle_right row of the species' overworld sheet, drawn `target`
## pixels tall. Null when the species has no overworld sheet, which cannot happen
## today (the list comes from that folder) but would if the two ever diverged.
func _make_mini_sprite(species: String, target: float) -> TextureRect:
	var path := OverworldPokemonData.sheet_path(species)
	if not ResourceLoader.exists(path):
		return null
	var sheet := load(path) as Texture2D
	if sheet == null:
		return null

	# Every sheet is sliced by quarters — four of them are not 256x256, so the cell
	# size has to be derived rather than hardcoded to 64.
	var frame := Vector2(sheet.get_width() / 4.0, sheet.get_height() / 4.0)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0.0, MINI_ROW * frame.y, frame.x, frame.y)
	atlas.filter_clip = true

	var scale_to : float = target / maxf(frame.x, frame.y)
	var disp := frame * scale_to

	var rect := TextureRect.new()
	rect.texture      = atlas
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size         = disp
	rect.custom_minimum_size = disp
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


# ─── Met-only filter ─────────────────────────────────────────────────────────

func _refresh_hide_button() -> void:
	hide_btn.text = "Show all Pokemon" if _hide_unmet else "Show met only"
	UIKit.style_button(hide_btn, "secondary")


func _on_hide_pressed() -> void:
	if _is_rebuilding:
		return
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)
	_hide_unmet = not _hide_unmet
	_refresh_hide_button()
	await _rebuild_grid()


func _rebuild_grid() -> void:
	_is_rebuilding    = true
	hide_btn.disabled = true

	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	var scroll := grid.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0

	_loading_overlay.show_for_library(self)
	await get_tree().process_frame
	await _load_entries()
	_loading_overlay.hide()
	if not is_inside_tree():
		return

	hide_btn.disabled = false
	_is_rebuilding    = false


# ─── Leaving ─────────────────────────────────────────────────────────────────

func _on_cancel_pressed() -> void:
	if GameState.close_sub_menu(): return   # map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Input / hold-to-preview ─────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if UIInput.is_zoom_start(event):
		zoom_held = true
		_refresh_hover_preview()
		return
	if UIInput.is_zoom_end(event):
		zoom_held = false
		_hide_zoom()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_zoomed:
			zoom_held = false   # drop the hold too, or _process re-opens the preview
			_hide_zoom()
			return
		_on_cancel_pressed()


func _process(_delta: float) -> void:
	if not zoom_held:
		return
	if not UIInput.is_zoom_held():
		zoom_held = false
		_hide_zoom()
		return
	_refresh_hover_preview()


func _refresh_hover_preview() -> void:
	var entry := _get_hovered_entry()
	if entry == zoomed_entry:
		return
	if entry == null:
		return   # gap between cells — hold the current preview rather than flashing it off
	_show_zoom(entry)


func _get_hovered_entry() -> Control:
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return null
	var node = hovered
	for i in range(5):
		if node == null:
			return null
		if node.has_meta("species") and node.get_meta("is_met", false):
			return node as Control
		node = node.get_parent()
	return null


func _show_zoom(entry: Control) -> void:
	var art: Texture2D = entry.get_meta("portrait", null)
	if art == null:
		return

	zoomed_entry = entry

	# Overlay already up — swap the image in place rather than rebuilding the
	# CanvasLayer, which flashes the bright grid through for a frame on every
	# hover change.
	if is_zoomed and zoom_image != null and is_instance_valid(zoom_image):
		_apply_zoom_texture(art, String(entry.get_meta("species", "")))
		return

	is_zoomed = true

	zoom_overlay = CanvasLayer.new()
	zoom_overlay.layer = 150
	add_child(zoom_overlay)

	var backdrop := ColorRect.new()
	backdrop.color         = Color(0, 0, 0, 0.95)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	# Must not absorb hover or gui_get_hovered_control() would report the backdrop.
	backdrop.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.add_child(backdrop)

	zoom_image = TextureRect.new()
	zoom_image.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	zoom_image.stretch_mode = TextureRect.STRETCH_SCALE
	zoom_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	zoom_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.add_child(zoom_image)

	zoom_caption = Label.new()
	zoom_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zoom_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.add_child(zoom_caption)

	_apply_zoom_texture(art, String(entry.get_meta("species", "")))


func _apply_zoom_texture(tex: Texture2D, species: String) -> void:
	var tex_size  := tex.get_size()
	var target    := Vector2(760.0, 760.0)
	var s         := minf(target.x / tex_size.x, target.y / tex_size.y)
	var disp_size := Vector2(tex_size.x * s, tex_size.y * s)

	zoom_image.texture  = tex
	zoom_image.size     = disp_size
	zoom_image.position = Vector2((1920.0 - disp_size.x) / 2.0, (1080.0 - disp_size.y) / 2.0 - 40.0)

	UIKit.set_label(zoom_caption, "title", OverworldPokemonData.guide_label(species), "chrome_fg", 44)
	zoom_caption.size     = Vector2(1920.0, 60.0)
	zoom_caption.position = Vector2(0.0, zoom_image.position.y + disp_size.y + 20.0)


func _hide_zoom() -> void:
	if not is_zoomed:
		return
	is_zoomed    = false
	zoomed_entry = null
	zoom_image   = null
	zoom_caption = null
	if zoom_overlay != null:
		zoom_overlay.queue_free()
		zoom_overlay = null
