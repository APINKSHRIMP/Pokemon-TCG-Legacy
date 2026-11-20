extends Control

## THE MEDALS CHART - opened from the Trainer card's "View Medals" button.
##
## A read-only trophy case: one tile per medal (MedalData.all(), from Medals.json), grouped Sets /
## Milestones / Type Mastery / Gym Leaders / Feats. A medal not yet earned is a blacked-out
## silhouette of its art (the shape shows, the art does not); a tiered medal shows the grade the
## player has reached. The big panel on the right describes whichever tile the mouse is over, the
## cursor is on, or was clicked last. Nothing is saved or equipped here.
##
## Everything is derived live from the save (MedalData). Controls: D-pad / arrows move the cursor,
## the preview follows it; B / Esc / Cancel leaves.

const INFO_SCENE := "res://Scenes/Main_Menu_Scenes/Info_Scene.tscn"

## TWEAKABLE - design (1920x1080) sizes; they grow with UIKit.item_scale().
const TILE_BASE := Vector2(116.0, 116.0)
const TILE_GAP_BASE := 16.0
const INSET := 28.0
const PANEL_W_BASE := 640.0
## Inner margin of the preview panel, so text and the progress bar never touch its edge.
const PANEL_MARGIN := 30
const PREVIEW_BASE := 300.0
const GROUP_GAP := 22.0
## A locked slot: the art run through this - greyscale, darkened, so only the SHAPE shows (a gold coin
## must not read as gold when it is not earned).
const LOCKED_SHADER := "shader_type canvas_item; void fragment() { vec4 c = texture(TEXTURE, UV); float l = dot(c.rgb, vec3(0.3, 0.59, 0.11)); COLOR = vec4(vec3(l * 0.16) + vec3(0.02, 0.022, 0.03), c.a); }"
var _locked_mat: ShaderMaterial = null
const FRAME_COLOUR := Color(1.0, 0.86, 0.3, 1.0)

var _ctx: Dictionary = {}
var _tiles: Array = []              # [{tile, art, frame, def, tier}]
var _selected: Dictionary = {}      # the _tiles entry on show
var _scroll: ScrollContainer = null
var _stack: VBoxContainer = null
var _grids: Array = []
var _count_holder: Control = null

var _p_group: Label
var _p_name: Label
var _p_sparkle: CPUParticles2D = null
## TWEAKABLE: the big preview's glitter, as a share of a tile's count for the same grade (lighter than the chart).
const PREVIEW_GLITTER := 0.35
var _p_art: MedalCoin3D   # the preview: a 3D coin that spins in on every selection, like the gift reveal
var _p_grade: Label
var _p_desc: Label
var _p_meter_holder: VBoxContainer
var _p_progress: Label
var _panel: PanelContainer
var _audio := AudioStreamPlayer.new()
var _tex_cache: Dictionary = {}


func _ready() -> void:
	add_child(_audio)
	var stream = load(SoundManagerScript.menu_bgm())
	if stream != null:
		_audio.stream = stream
		_audio.bus = SoundManagerScript.MUSIC_BUS
		_audio.stream.loop = true
		if not SoundManagerScript.play_menu_family_bgm():
			_audio.play()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.base_theme()
	UIKit.add_field(self)
	var header := UIKit.add_header(self)
	var footer := UIKit.add_footer(self)
	var title := Label.new()
	UIKit.set_label(title, "title", "Medals", "chrome_fg")
	header.centre.add_child(title)
	_count_holder = header.left
	var cancel := UIKit.make_footer_button("Cancel", "negative")
	cancel.pressed.connect(_on_cancel_pressed)
	footer.centre.add_child(cancel)

	_ctx = MedalData.make_context()
	_refresh_count_chip()
	_build_body()
	_layout()
	UIKit.on_screen_resized(_layout)
	_select_first_owned_or_first()


# ── Build ────────────────────────────────────────────────────────────────────────────────────

func _build_body() -> void:
	var band := Control.new()
	band.name = "band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	_scroll = ScrollContainer.new()
	_scroll.name = "medal_scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	band.add_child(_scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 10)   # room for the selected tile's pulse
	_scroll.add_child(pad)
	_stack = VBoxContainer.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.add_theme_constant_override("separation", int(GROUP_GAP))
	pad.add_child(_stack)

	var groups: Array = []
	var by_group := {}
	for def in MedalData.all():
		if not MedalData.is_visible(def, _ctx):
			continue   # a set not unlocked yet / Gym Leaders before a Gym set: not on the chart
		var g := String(def.get("group", ""))
		if not by_group.has(g):
			by_group[g] = []
			groups.append(g)
		(by_group[g] as Array).append(def)
	for g in groups:
		var holder := VBoxContainer.new()
		holder.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		var defs: Array = by_group[g]
		var got := 0
		for d in defs:
			if MedalData.earned_tier(d, _ctx) >= 0:
				got += 1
		UIKit.set_label(lbl, "small_label", "%s   %d / %d" % [g, got, defs.size()], "field_fg")
		holder.add_child(lbl)
		var grid := GridContainer.new()
		grid.name = "grid_" + String(g).to_lower().replace(" ", "_")
		holder.add_child(grid)
		_grids.append(grid)
		for d in defs:
			_add_tile(grid, d)
		_stack.add_child(holder)

	_panel = UIKit.make_panel()
	_panel.name = "preview_panel"
	band.add_child(_panel)
	var inset := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inset.add_theme_constant_override(side, PANEL_MARGIN)
	_panel.add_child(inset)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	inset.add_child(col)
	_p_group = Label.new()
	col.add_child(_p_group)
	_p_name = Label.new()
	_p_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_p_name)
	_p_art = MedalCoin3D.new()
	_p_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_p_art.continuous = true   # slow turn in place; the angle carries over between medals
	_p_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_p_art)
	_p_grade = Label.new()
	_p_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_p_grade)
	_p_desc = Label.new()
	_p_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_p_desc)
	_p_meter_holder = VBoxContainer.new()
	col.add_child(_p_meter_holder)
	_p_progress = Label.new()
	col.add_child(_p_progress)


func _add_tile(grid: GridContainer, def: Dictionary) -> void:
	var tier := MedalData.earned_tier(def, _ctx)
	var tile := Control.new()
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.name = "medal_" + String(def["id"])
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = _tex(MedalData.art_path(def, maxi(tier, 0)))
	if tier < 0:
		art.material = _locked_material()
	tile.add_child(art)
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(3)
	sb.border_color = FRAME_COLOUR
	sb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", sb)
	frame.visible = false
	tile.add_child(frame)
	grid.add_child(tile)
	var entry := {"tile": tile, "art": art, "frame": frame, "def": def, "tier": tier}
	_tiles.append(entry)
	UIKit.make_nav_tile(tile)
	tile.gui_input.connect(func(event: InputEvent) -> void:
		if UIInput.is_click(event):
			_select(entry))
	tile.mouse_entered.connect(func() -> void: _select(entry))
	# Hover feels instant: pick on the first motion over the tile too (mouse_entered lands a frame later).
	tile.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			_select(entry))


func _locked_material() -> ShaderMaterial:
	if _locked_mat == null:
		var sh := Shader.new()
		sh.code = LOCKED_SHADER
		_locked_mat = ShaderMaterial.new()
		_locked_mat.shader = sh
	return _locked_mat


## Imported PNG, else (a hand-drawn file dropped in before the editor re-imported) straight off disk.
func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			t = ImageTexture.create_from_image(img)
	_tex_cache[path] = t
	return t


# ── Layout ───────────────────────────────────────────────────────────────────────────────────

func _layout() -> void:
	var band := get_node_or_null("band") as Control
	if band == null:
		return
	var s := UIKit.item_scale()
	band.position = Vector2(INSET, UIKit.CONTENT_TOP + INSET * 0.6)
	band.size = Vector2(UIKit.screen_w() - INSET * 2.0, UIKit.content_h() - INSET * 1.2)
	var panel_w := PANEL_W_BASE * s
	var gap := 24.0
	_panel.position = Vector2(band.size.x - panel_w, 0.0)
	_panel.size = Vector2(panel_w, band.size.y)
	_scroll.position = Vector2.ZERO
	_scroll.size = Vector2(band.size.x - panel_w - gap, band.size.y)
	var area := Vector2(_scroll.size.x - 20.0, 400.0)
	var fit := UIKit.fit_grid(area, TILE_BASE, Vector2(TILE_GAP_BASE, TILE_GAP_BASE))
	var cell: Vector2 = (fit["cell"] as Vector2).floor()
	for grid in _grids:
		(grid as GridContainer).columns = int(fit["columns"])
		(grid as GridContainer).add_theme_constant_override("h_separation", int((fit["gap"] as Vector2).x))
		(grid as GridContainer).add_theme_constant_override("v_separation", int(TILE_GAP_BASE * s))
	for e in _tiles:
		var tile := e["tile"] as Control
		tile.custom_minimum_size = cell
		tile.size = cell
		tile.pivot_offset = cell / 2.0
		_place_sparkle(e, cell)
	var side := PREVIEW_BASE * s
	_p_art.custom_minimum_size = Vector2(side, side) * 1.12
	_p_art.full_diameter = side
	var inner_w := panel_w - PANEL_MARGIN * 2.0 - 4.0
	_p_desc.custom_minimum_size.x = inner_w
	_p_name.custom_minimum_size.x = inner_w
	if not _selected.is_empty():
		_show(_selected)


## Glitter on an earned medal, in its metal's colours (more pixels the higher the grade).
func _place_sparkle(e: Dictionary, cell: Vector2) -> void:
	if int(e["tier"]) < 0:
		return
	var tile := e["tile"] as Control
	var old = e.get("sparkle")
	if old != null and is_instance_valid(old):
		old.free()
	var metal := MedalData.metal_of(e["def"], int(e["tier"]))
	e["sparkle"] = MedalSparkle.attach(tile, metal, cell.x / TILE_BASE.x, cell * 0.36, cell.x / TILE_BASE.x)


func _refresh_count_chip() -> void:
	for c in _count_holder.get_children():
		c.queue_free()
	var shown := 0
	for def in MedalData.all():
		if MedalData.is_visible(def, _ctx):
			shown += 1
	_count_holder.add_child(UIKit.make_chip("%d / %d" % [MedalData.count_earned(_ctx), shown], "on_chrome"))


# ── Selection / preview ──────────────────────────────────────────────────────────────────────

func _select_first_owned_or_first() -> void:
	var pick: Dictionary = {}
	for e in _tiles:
		if int(e["tier"]) >= 0:
			pick = e
			break
	if pick.is_empty() and not _tiles.is_empty():
		pick = _tiles[0]
	if not pick.is_empty():
		_select(pick)


func _select(entry: Dictionary) -> void:
	if _selected == entry:
		return
	if not _selected.is_empty():
		(_selected["frame"] as Control).visible = false
		_grow(_selected["tile"] as Control, 1.0)
	_selected = entry
	(entry["frame"] as Control).visible = true
	_grow(entry["tile"] as Control, SELECT_SCALE)
	_show(entry)


## TWEAKABLE: the selected tile's size-up and how fast it gets there (kept short so the cursor feels instant).
const SELECT_SCALE := 1.12
const SELECT_TIME := 0.06

func _grow(tile: Control, to: float) -> void:
	var tw := tile.create_tween()
	tw.tween_property(tile, "scale", Vector2(to, to), SELECT_TIME)


func _show(entry: Dictionary) -> void:
	var def: Dictionary = entry["def"]
	var tier: int = int(entry["tier"])
	UIKit.set_label(_p_group, "small_label", String(def.get("group", "")), "field_fg")
	UIKit.set_label(_p_name, "title", String(def.get("name", "")), "field_fg")
	# the coin keeps its slow turn between medals (MedalCoin3D.continuous)
	var metal := MedalData.metal_of(def, maxi(tier, 0))
	_p_art.begin(_tex(MedalData.art_path(def, maxi(tier, 0))), metal, tier < 0)
	# ONE emitter, freed before the next (a queue_free'd node still holds its name, so the new one was renamed
	# and the old glitter piled up for good)
	if _p_sparkle != null and is_instance_valid(_p_sparkle):
		_p_sparkle.free()
	_p_sparkle = null
	if tier >= 0:
		_p_sparkle = MedalSparkle.attach(_p_art, metal, PREVIEW_GLITTER, Vector2.ONE * _p_art.full_diameter * 0.4, 2.2)
	var grade := ""
	if tier < 0:
		grade = "Not earned yet"
	elif MedalData.is_tiered(def):
		grade = MedalData.grade_name(def, tier)
	else:
		grade = "Earned"
	UIKit.set_label(_p_grade, "name", grade, "field_fg")
	UIKit.set_label(_p_desc, "body", MedalData.describe(def, tier, _ctx), "field_fg")
	for c in _p_meter_holder.get_children():
		c.queue_free()
	var line := MedalData.progress_line(def, _ctx)
	_p_progress.text = ""
	if line != "":
		var th := MedalData.thresholds(def, _ctx)
		var next_i := mini(tier + 1, th.size() - 1)
		var v := MedalData.value_of(def, _ctx)
		_p_meter_holder.add_child(UIKit.make_meter(float(v), float(int(th[next_i])), _p_desc.custom_minimum_size.x))
		UIKit.set_label(_p_progress, "small_label", line, "field_fg")


# ── Leaving ──────────────────────────────────────────────────────────────────────────────────

func _on_cancel_pressed() -> void:
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	if GameState.close_sub_menu():
		return
	SceneCache.change_scene(INFO_SCENE)


func _input(event: InputEvent) -> void:
	if UIInput.is_cancel(event):
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()
