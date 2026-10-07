extends Control

## THE BAG — the player's key items, opened from the Trainer card's "View Bag" button.
##
## A plain record, like the Field Guide: a grid of square cells, nothing selectable,
## nothing saved. Each cell shows the item's name; once its art exists in
## Image_Assets/Assorted_Extras (same name as the item, .png) the picture shows above
## the name instead of the name alone.
##
## What counts as a key item is KEY_ITEMS below, in the order they are listed:
##   * fishing rods and fishing permits -- items in progress["items"] (FishingRods)
##   * the Starting Box from upstairs and the Card Mart's Starter Set -- these are the
##     two save flags that record them, shown so a save can be checked at a glance.
## Add a new key item by adding a row here.

## TWEAKABLE — grid shape and text.
const COLUMNS     := 6
const CELL_SIZE   := Vector2(280.0, 300.0)
const CELL_SEP    := 24
const ART_BOX     := 200.0   ## the most room the art gets, above the caption
const NAME_FONT   := 26
const GRID_INSET_Y := 30.0
const EMPTY_TEXT  := "Your bag is empty."

## Each row: {"label", and either "item" (an item name) or "flag" (a progress key)}.
## Rods and permits are filled in from FishingRods so their names live in one place.
const FLAG_ITEMS := [
	{"label": "Starting Box", "flag": "player_collected_starter_box", "art": "Starting_Box"},
	{"label": "Starter Set", "flag": "player_collected_shop_starter_set", "art": "Starter_Set"},
]

@onready var grid        : GridContainer = $"bag_grid_container"
@onready var cancel_btn  : Button        = $"bag_cancel_button"
@onready var audio_player = AudioStreamPlayer.new()

var _count_chip_holder : Control = null


func _ready() -> void:
	add_child(audio_player)
	var audio_stream = load(SoundManagerScript.BGM_COIN_MODE)
	if audio_stream != null:
		audio_player.stream = audio_stream
		audio_player.bus = SoundManagerScript.MUSIC_BUS
		audio_player.stream.loop = true
		audio_player.play()

	cancel_btn.pressed.connect(_on_cancel_pressed)
	var bars := UIKit.convert_legacy_screen(self, "Bag")
	_count_chip_holder = bars["header"].left
	UIKit.adopt_button(cancel_btn, bars["footer"].centre, "secondary")

	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", CELL_SEP)
	grid.add_theme_constant_override("v_separation", CELL_SEP)
	_build()


## Every key item the player has, in display order.
func _owned_entries() -> Array:
	var out: Array = []
	for rod in FishingRods.ROD_ORDER:
		if GameState.has_item(rod):
			out.append({"label": FishingRods.label(rod), "art": rod})
	for permit in FishingRods.PERMIT_LABELS:
		if GameState.has_item(permit):
			out.append({"label": FishingRods.label(permit), "art": permit})
	for row in FLAG_ITEMS:
		if bool(GameState.progress.get(row["flag"], false)):
			out.append({"label": row["label"], "art": row["art"]})
	return out


func _build() -> void:
	var entries := _owned_entries()
	if _count_chip_holder != null:
		_count_chip_holder.add_child(UIKit.make_chip("%d items" % entries.size(), "on_chrome"))

	if entries.is_empty():
		var empty := Label.new()
		UIKit.set_label(empty, "body", EMPTY_TEXT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.position = Vector2(0.0, UIKit.CONTENT_TOP + UIKit.CONTENT_H * 0.4)
		empty.size = Vector2(UIKit.SCREEN_W, 60.0)
		add_child(empty)
		return

	for entry in entries:
		grid.add_child(_make_cell(entry))

	# Centre the block in the content band: a GridContainer only lays out from its
	# own top-left, so the size is worked out from the cells.
	var cols: int = mini(entries.size(), COLUMNS)
	var rows: int = int(ceil(float(entries.size()) / float(COLUMNS)))
	var content := Vector2(cols * CELL_SIZE.x + (cols - 1) * CELL_SEP,
			rows * CELL_SIZE.y + (rows - 1) * CELL_SEP)
	grid.size = content
	grid.position = Vector2((UIKit.SCREEN_W - content.x) * 0.5, UIKit.CONTENT_TOP + GRID_INSET_Y)


func _make_cell(entry: Dictionary) -> Control:
	var cell := UIKit.make_panel()
	cell.custom_minimum_size = CELL_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(box)

	var art_path := "res://Image_Assets/Assorted_Extras/%s.png" % str(entry.get("art", ""))
	if ResourceLoader.exists(art_path):
		var tex: Texture2D = load(art_path)
		# Pixel art: a whole-number enlargement (24px rods x8), or a plain fit when the
		# art is bigger than the box (the 200px permits fit at 1x).
		var tex_size := tex.get_size()
		var fit := minf(ART_BOX / tex_size.x, ART_BOX / tex_size.y)
		if fit >= 1.0:
			fit = floorf(fit)
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.custom_minimum_size = tex_size * fit
		rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rect)

	var name_label := Label.new()
	UIKit.set_label(name_label, "body", str(entry["label"]), "field_fg", NAME_FONT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(CELL_SIZE.x - 30.0, 0.0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	return cell


func _on_cancel_pressed() -> void:
	if GameState.close_sub_menu(): return   # map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()
