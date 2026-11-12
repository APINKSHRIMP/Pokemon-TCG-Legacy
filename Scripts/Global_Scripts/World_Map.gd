class_name WorldMap
extends CanvasLayer

## The overworld map, shown on the phone. Press OPEN_KEY anywhere in a map scene.
##
## One stitched picture (WorldMap1.png) holds all three outdoor areas. Each area was traced over a
## screenshot of its own map, so each has its OWN world->picture scale and offset (AREAS below) -
## the areas are not one continuous coordinate space in the game, only on the picture. An area the
## player has never set foot in is covered (note_visit() records visits as story flags).
##
## Blips are a snapshot taken when the phone opens - nothing on the map moves while it is up:
##   - the current map uses its LIVE actors, where they are standing right now;
##   - every other outdoor map resolves its cast for this day and time from the character files;
##   - anyone inside a building is drawn at that building's icon, in a centred grid of rows of
##     CLUSTER_PER_ROW: the player, Olly / Ellie / Alexander, and every opponent battleable there
##     right now (in their own shade of red), exactly as outdoors.

const MAP_TEXTURE := "res://Image_Assets/Map_Maps/WorldMap1.png"
const PHONE_ART   := "res://Image_Assets/Character_Sprites/Talking_Sprites/Phones/iPhone4.png"
const SCENE_DIR   := "res://Scenes/Map_Scenes/"
const CONSTANTS_PATH := "res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json"
const VISIT_FLAG_PREFIX := "map_visited_"

## The key that opens and closes the map. Escape closes it too.
const OPEN_KEY := KEY_M
const ControllerDiagram := preload("res://Scripts/Menu_Scripts/Controller_Diagram.gd")

const SCREEN_W : float = 1920.0
const SCREEN_H : float = 1080.0

# ─── TWEAKABLE: the phone ─────────────────────────────────────────────────────
# The art is 39x62; 12x makes it 468x744, about two thirds of the screen's height. Keep it a WHOLE
# number (nearest-neighbour pixel art). It is centred on screen both ways.
const PHONE_SCALE        : float = 12.0
const PHONE_OVERSHOOT    : float = 18.0
const SLIDE_IN_TIME      : float = 0.225  # half a phone call's 0.45
const SLIDE_OUT_TIME     : float = 0.19   # half a phone call's 0.38
const PHONE_OFFSCREEN_PAD: float = 60.0
const DIM_ALPHA          : float = 0.6    # the overworld behind the phone, same as the main menu
const MAP_FADE_IN        : float = 0.25   # the map fading up once the phone has landed
const MAP_FADE_OUT       : float = 0.10

# ─── TWEAKABLE: the "Loading Maps" screen while the phone flies in ────────────
const COVER_TOP_COLOUR : Color = Color(0.16, 0.16, 0.18, 1.0)
const COVER_BOT_COLOUR : Color = Color(0.04, 0.04, 0.05, 1.0)
const SPINNER_SIZE     : float = 0.20     # fraction of the screen's width
const SPINNER_SPIN_TIME: float = 1.0
const COVER_LABEL_SIZE : int   = 16
const COVER_LABEL_GAP  : float = 0.055
const LOADING_WORD     : String = "Loading Maps"

# ─── TWEAKABLE: moving about ──────────────────────────────────────────────────
# Zoom is screen px per picture px. The picture is 1280 wide and the phone's screen 348, so 0.6
# shows about half the width - zoomed out "a little", never the whole map at once.
const ZOOM_DEFAULT : float = 1.25
const ZOOM_MIN     : float = 0.6
const ZOOM_MAX     : float = 3.0
const ZOOM_STEP    : float = 1.15    # per mouse-wheel notch
const PAN_SPEED    : float = 420.0   # screen px per second with WASD / arrows

# ─── TWEAKABLE: blips ─────────────────────────────────────────────────────────
# Radii are SCREEN px, so a blip stays the same size however far in you zoom.
const PLAYER_RADIUS : float = 6.0
const STORY_RADIUS  : float = 5.0
const DOT_RADIUS    : float = 3.5
const OUTLINE_PX    : float = 1.5    # dark rim so a white blip still shows on a pale path
const PULSE_TIME    : float = 1.2    # seconds per grow-shrink / colour cycle
const PULSE_GROW    : float = 0.15   # +-15% radius
const GLOW_SCALE    : float = 2.0    # soft halo radius, as a multiple of the blip's
const GLOW_ALPHA    : float = 0.30
const RING_TIME     : float = 1.6    # seconds for one radar ring to spread and fade
const RING_REACH    : float = 3.5    # how far a ring spreads, as a multiple of the blip's radius
const RING_WIDTH    : float = 1.5
const CLUSTER_GAP   : float = 4.0    # screen px between blips sharing a building
const CLUSTER_PER_ROW : int = 5      # a building's dots wrap into rows of this many

const COL_PLAYER     := Color(1.0, 1.0, 1.0)
# Olly / Ellie / Alexander, two states (user spec 2026-11-11). Each dot cycles BASE -> PEAK like an
# opponent's. READY = battleable right now, or waiting to be (the café trio before their cutscene
# matches): saturated, glowing towards black. DONE = already battled under that name, or standing as
# an NPC / shopkeeper: a little lighter and less saturated, glowing towards white.
const COL_OLLY            := Color(0.05, 0.16, 0.72)   # deep blue...
const COL_ELLIE           := Color(0.82, 0.06, 0.48)   # deep pink...
const COL_ALEXANDER       := Color(0.85, 0.62, 0.0)    # deep yellow / gold...
const COL_OLLY_PEAK       := Color(0.01, 0.03, 0.22)   # ...glowing to near-black
const COL_ELLIE_PEAK      := Color(0.26, 0.01, 0.14)
const COL_ALEXANDER_PEAK  := Color(0.27, 0.18, 0.0)
const COL_OLLY_DONE       := Color(0.36, 0.48, 0.86)   # lighter, softer blue...
const COL_ELLIE_DONE      := Color(0.90, 0.42, 0.68)   # lighter, softer pink...
const COL_ALEXANDER_DONE  := Color(0.93, 0.76, 0.32)   # lighter, softer gold...
const COL_STORY_DONE_PEAK := Color(1.0, 1.0, 1.0)      # ...all glowing to white
# Opponents, three states (user spec 2026-11-07). Each dot cycles between its BASE colour and its
# PEAK as it glows: never battled goes DARKER, battled-but-unbeaten goes LIGHTER, beaten goes paler
# still, towards white/grey. "Battled" = any finished match on their head-to-head record.
const COL_OPP_NEW_BASE    := Color(0.78, 0.08, 0.08)   # never battled: a slightly darker red...
const COL_OPP_NEW_PEAK    := Color(0.38, 0.01, 0.01)   # ...glowing darker
const COL_OPP_MET_BASE    := Color(1.0, 0.36, 0.36)    # battled, not beaten: a slightly lighter red...
const COL_OPP_MET_PEAK    := Color(1.0, 0.62, 0.62)    # ...glowing lighter
const COL_OPP_BEATEN_BASE := Color(1.0, 0.80, 0.80)    # beaten: a much paler red...
const COL_OPP_BEATEN_PEAK := Color(0.93, 0.91, 0.91)   # ...glowing towards white/grey
const COL_OUTLINE    := Color(0.05, 0.05, 0.08, 0.9)
const COL_FOG        := Color(0.03, 0.04, 0.07, 1.0)

## Story characters, matched on their message-box name (friendly_name), falling back to the
## tracking name - so "Fish Shop Alexander" and "Ellie 2" both count.
const STORY_COLOURS := {"Olly": COL_OLLY, "Ellie": COL_ELLIE, "Alexander": COL_ALEXANDER}
const STORY_PEAKS := {"Olly": COL_OLLY_PEAK, "Ellie": COL_ELLIE_PEAK, "Alexander": COL_ALEXANDER_PEAK}
const STORY_DONE_COLOURS := {"Olly": COL_OLLY_DONE, "Ellie": COL_ELLIE_DONE, "Alexander": COL_ALEXANDER_DONE}

## Blips never sit on these picture colours (trees, then water). The traces are a hair off the real
## maps in places, so an outdoor blip landing on one is nudged to the nearest other pixel, up to
## SNAP_MAX picture px away. The picture is lossless pixel art, so these are its exact palette entries.
const BLOCKED_COLOURS := [
	Color8(72, 160, 64), Color8(24, 80, 24), Color8(48, 120, 48), Color8(40, 88, 40),
	Color8(72, 128, 208), Color8(96, 152, 224), Color8(136, 192, 240),
]
const SNAP_MAX : int = 40

## Story-character matcher: "Olly", "Ellie" or "Alexander" as a WHOLE WORD anywhere in the
## message-box name or the tracking name, any case - so "Olly 2", "Fish Shop Alexander" and
## "Ellie's Mum" all count, but "Holly" or "Kellie" never do. First word found wins.
static var _story_regex: RegEx = null

# ─── THE PICTURE ──────────────────────────────────────────────────────────────
## Per outdoor area: picture_px = world_px * scale + offset, and the horizontal band of the
## picture that area occupies (covered until visited). Fitted against each map's tiles and doors.
const AREAS := {
	"Celeste_Harbour": {"scale": 0.1755, "offset": Vector2(462.3, 924.0),
		"band": Rect2(0, 948, 1280, 582), "always": true},
	"Verdant_Forest":  {"scale": 0.2166, "offset": Vector2(235.9, 476.3),
		"band": Rect2(0, 400, 1280, 548), "always": false},
	"Gym_Plaza":       {"scale": 0.2176, "offset": Vector2(245.4, -46.6),
		"band": Rect2(0, 0, 1280, 400), "always": false},
}

## Indoor maps -> [the outdoor area they belong to, the centre of their icon on the picture].
const INTERIORS := {
	"Player_House_Downstairs":    ["Celeste_Harbour", Vector2(300, 1168)],
	"Player_House_Upstairs":      ["Celeste_Harbour", Vector2(300, 1168)],
	"Ellie_House_Downstairs":     ["Celeste_Harbour", Vector2(378, 1168)],
	"Ellie_House_Upstairs":       ["Celeste_Harbour", Vector2(378, 1168)],
	"Alexander_House_Downstairs": ["Celeste_Harbour", Vector2(542, 1010)],
	"Alexander_House_Upstairs":   ["Celeste_Harbour", Vector2(542, 1010)],
	"Card_Mart":                  ["Celeste_Harbour", Vector2(538, 1168)],
	"Fish_Shop":                  ["Celeste_Harbour", Vector2(167, 1010)],
	"Fish_Shop_Downstairs":       ["Celeste_Harbour", Vector2(167, 1010)],
	"DeepOceanFishing":           ["Celeste_Harbour", Vector2(50, 1120)],
	"TownHall":                   ["Celeste_Harbour", Vector2(708, 1092)],
	"TownHall_Upstairs":          ["Celeste_Harbour", Vector2(708, 1092)],
	"Cafe":                       ["Celeste_Harbour", Vector2(816, 1093)],
	"TrainStation":               ["Celeste_Harbour", Vector2(1002, 1043)],
	"Hotel":                      ["Celeste_Harbour", Vector2(1072, 1045)],
	"Rocket_Mart":                ["Verdant_Forest", Vector2(288, 690)],
	"Windmill":                   ["Verdant_Forest", Vector2(1010, 422)],
	"Gym_Challenge_Reception":    ["Gym_Plaza", Vector2(625, 213)],
	"Gym_Challenge_Hall":         ["Gym_Plaza", Vector2(625, 213)],
}

# ─── TWEAKABLE: the controls + legend panels either side of the phone ─────────
# Shown every time the map opens. Controls follow the device in use: keyboard + mouse, or a pad
# (Xbox / PlayStation names).
const HINT_GAP          : float = 48.0   # screen px between the phone and each panel
const HINT_PAD          : int   = 22     # inner margin of a panel
const HINT_ROW_GAP      : int   = 12
const HINT_COL_GAP      : int   = 18
const HINT_TITLE_SIZE   : int   = 18
const HINT_KEY_SIZE     : int   = 14
const HINT_TEXT_SIZE    : int   = 17
const LEGEND_DOT_RADIUS : float = 7.0    # bigger than a map dot (DOT_RADIUS) so it reads at a glance
const LEGEND_DOT_BOX    : float = 30.0

# ─── TWEAKABLE: pad zoom (the triggers; the mouse wheel does it on K&M) ──────
const PAD_ZOOM_RATE      : float = 2.2   # zoom multiplies by this per second at a full pull
const PAD_TRIGGER_DEADZONE : float = 0.15

const LAYER : int = 175

static var _open: WorldMap = null
## map name -> its actor container's offset; scene files do not change while the game runs.
static var _offset_cache: Dictionary = {}

# ─── Nodes ───────────────────────────────────────────────────────────────────
var _dim: ColorRect = null
var _rig: Control = null
var _screen: Control = null
var _content: Control = null
var _blips: Control = null
var _cover: Control = null
var _spinner: ColorRect = null
var _spinner_tween: Tween = null
var _player: Node = null
var _hints: Control = null           # the controls + legend panels beside the phone
var _controls_panel: PanelContainer = null
var _legend_panel: PanelContainer = null
var _legend_dots: Array[Control] = []
var _hints_pad: bool = false         # which control set the panel is showing

# ─── State ───────────────────────────────────────────────────────────────────
var _phone_size := Vector2.ZERO
var _screen_size := Vector2.ZERO
var _rest_y: float = 0.0
var _zoom: float = ZOOM_DEFAULT
var _centre := Vector2.ZERO          # picture px at the middle of the phone's screen
var _bounds := Rect2()               # the unlocked part of the picture
var _dragging := false
var _ready_for_input := false
var _closing := false
var _held := false                   # see hold_for_message()
var _time: float = 0.0
## Each blip: {"pos": Vector2 picture px, "colour": Color, "radius": float, "kind": String,
## "phase": float}. "offset" (screen px) spreads a building's occupants side by side.
var _blip_list: Array[Dictionary] = []
var _pic_image: Image = null         # the picture's pixels, for keeping blips off trees and water
var _blocked: Dictionary = {}        # BLOCKED_COLOURS as RGBA ints, for a quick lookup


# ============================================================
# ENTRY POINTS
# ============================================================

static func is_open() -> bool:
	return _open != null and is_instance_valid(_open)


## Opens the map over `host` (the current map scene). `player` is locked for as long as it is up.
static func open(host: Node, player: Node) -> WorldMap:
	if is_open():
		return _open
	var m := WorldMap.new()
	m._player = player
	_open = m
	host.add_child(m)
	return m


## Records that the player has stood in `scene_path`'s area, so it stops being covered.
static func note_visit(scene_path: String) -> void:
	var area := area_for(scene_path.get_file().get_basename())
	if area != "" and not GameState.has_flag(VISIT_FLAG_PREFIX + area):
		GameState.set_flag(VISIT_FLAG_PREFIX + area)


## The outdoor area a map belongs to - itself for an outdoor map. "" when it is on no area.
static func area_for(map_name: String) -> String:
	if AREAS.has(map_name):
		return map_name
	if INTERIORS.has(map_name):
		return INTERIORS[map_name][0]
	return ""


static func is_area_unlocked(area: String) -> bool:
	if not AREAS.has(area):
		return false
	return bool(AREAS[area]["always"]) or GameState.has_flag(VISIT_FLAG_PREFIX + area)


# ============================================================
# BUILD
# ============================================================

func _ready() -> void:
	layer = LAYER
	if _player != null and _player.has_method("lock_movement"):
		_player.lock_movement()
	MapManager.set_overworld_paused(true)
	_build()
	if _rig != null:
		_build_hints()
	_collect_blips()
	_start_view()
	_play_open()


func _exit_tree() -> void:
	if _open == self:
		_open = null


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, DIM_ALPHA)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.modulate.a = 0.0
	add_child(_dim)

	var phone_tex: Texture2D = load(PHONE_ART) if ResourceLoader.exists(PHONE_ART) else null
	if phone_tex == null:
		push_warning("WorldMap: phone art missing at %s" % PHONE_ART)
		return
	_phone_size = Vector2(phone_tex.get_width(), phone_tex.get_height()) * PHONE_SCALE
	var hole_art := PhoneCall._find_screen_rect(phone_tex)   # the transparent screen, found by flood fill
	var hole := Rect2(hole_art.position * PHONE_SCALE, hole_art.size * PHONE_SCALE)
	_screen_size = hole.size
	_rest_y = (UIKit.screen_h() - _phone_size.y) * 0.5

	_rig = Control.new()
	_rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rig.size = _phone_size
	_rig.position = Vector2((UIKit.screen_w() - _phone_size.x) * 0.5, _offscreen_y())
	add_child(_rig)

	_screen = Control.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.clip_contents = true
	_screen.position = hole.position
	_screen.size = hole.size
	_rig.add_child(_screen)

	var backdrop := ColorRect.new()
	backdrop.color = COL_FOG
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.size = hole.size
	_screen.add_child(backdrop)

	# The picture and its fog, moved and scaled as one.
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.modulate.a = 0.0
	_screen.add_child(_content)
	var tex: Texture2D = load(MAP_TEXTURE) if ResourceLoader.exists(MAP_TEXTURE) else null
	if tex == null:
		push_warning("WorldMap: map picture missing at %s (needs importing?)" % MAP_TEXTURE)
	else:
		var pic := TextureRect.new()
		pic.texture = tex
		_pic_image = PhoneCall._readable_image(tex)
		for c: Color in BLOCKED_COLOURS:
			_blocked[c.to_rgba32()] = true
		# EXPAND_IGNORE_SIZE + an explicit size, or the rect clamps to its texture (feedback_sprite_sizing).
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.size = Vector2(tex.get_width(), tex.get_height())
		_content.add_child(pic)
	_build_fog()

	# Blips are drawn in SCREEN px over the picture, so they keep their size at any zoom.
	_blips = Control.new()
	_blips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blips.size = hole.size
	_blips.modulate.a = 0.0
	_blips.draw.connect(_draw_blips)
	_screen.add_child(_blips)

	_build_cover(hole.size)

	var phone_rect := TextureRect.new()
	phone_rect.texture = phone_tex
	phone_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	phone_rect.stretch_mode = TextureRect.STRETCH_SCALE
	phone_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	phone_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone_rect.size = _phone_size
	_rig.add_child(phone_rect)


## Covers every area not yet visited, and works out the unlocked rect the view is kept inside.
func _build_fog() -> void:
	_bounds = Rect2()
	for area in AREAS:
		var band: Rect2 = AREAS[area]["band"]
		if is_area_unlocked(area):
			_bounds = band if _bounds.size == Vector2.ZERO else _bounds.merge(band)
			continue
		var fog := ColorRect.new()
		fog.color = COL_FOG
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fog.position = band.position
		fog.size = band.size
		_content.add_child(fog)
	if _bounds.size == Vector2.ZERO:
		_bounds = AREAS["Celeste_Harbour"]["band"]


## The "Loading Maps" screen: the phone call's connecting cover with a different word.
func _build_cover(screen_size: Vector2) -> void:
	_cover = Control.new()
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.size = screen_size
	_screen.add_child(_cover)

	var grad := Gradient.new()
	grad.set_color(0, COVER_TOP_COLOUR)
	grad.set_color(1, COVER_BOT_COLOUR)
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0.0, 0.0)
	grad_tex.fill_to   = Vector2(0.0, 1.0)
	grad_tex.width  = int(screen_size.x)
	grad_tex.height = int(screen_size.y)
	var glass := TextureRect.new()
	glass.texture = grad_tex
	glass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glass.stretch_mode = TextureRect.STRETCH_SCALE
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.size = screen_size
	_cover.add_child(glass)

	var spin_px: float = screen_size.x * SPINNER_SIZE
	_spinner = ColorRect.new()
	_spinner.color = UITheme.col_a("accent", 0.9)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.size = Vector2(spin_px, spin_px)
	_spinner.pivot_offset = _spinner.size * 0.5
	_spinner.position = Vector2((screen_size.x - spin_px) * 0.5, screen_size.y * 0.5 - spin_px * 0.75)
	_cover.add_child(_spinner)

	var label := Label.new()
	UIKit.set_label(label, "small_label", LOADING_WORD, "field_fg", COVER_LABEL_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(screen_size.x, 0.0)
	label.position = Vector2(0.0, _spinner.position.y + spin_px + screen_size.y * COVER_LABEL_GAP)
	_cover.add_child(label)


# ============================================================
# CONTROLS + LEGEND (every opening)
# ============================================================

## Two panels beside the phone: the controls for the device in use on the left, what the three
## opponent dots mean on the right. They fade up with the map and follow a device switch live.
func _build_hints() -> void:
	_hints = Control.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hints.modulate.a = 0.0
	add_child(_hints)

	_controls_panel = _hint_panel()
	_hints.add_child(_controls_panel)
	_controls_panel.resized.connect(_place_hints)
	_fill_controls()

	_legend_panel = _hint_panel()
	_hints.add_child(_legend_panel)
	_legend_panel.resized.connect(_place_hints)
	# Each row: [base colour, peak colour (null = just lighten as it glows), text]. Rows in a
	# section pulse one after another (phase steps of a third).
	var body := _hint_body(_legend_panel, "Favourites")
	_legend_rows(_hint_grid(body), [
		[COL_OLLY, COL_OLLY_PEAK, "Olly"],
		[COL_ELLIE, COL_ELLIE_PEAK, "Ellie"],
		[COL_ALEXANDER, COL_ALEXANDER_PEAK, "Alexander"],
	])
	body.add_child(_hint_heading("Opponents"))
	_legend_rows(_hint_grid(body), [
		[COL_OPP_NEW_BASE, COL_OPP_NEW_PEAK, "Not battled yet"],
		[COL_OPP_MET_BASE, COL_OPP_MET_PEAK, "Battled, not beaten"],
		[COL_OPP_BEATEN_BASE, COL_OPP_BEATEN_PEAK, "Beaten"],
	])

	InputDevice.device_changed.connect(_on_device_changed)
	_place_hints()


## One pulsing dot + its text per row, drawn exactly as the map draws that kind of blip.
func _legend_rows(grid: GridContainer, rows: Array) -> void:
	for i in rows.size():
		var dot := Control.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.custom_minimum_size = Vector2(LEGEND_DOT_BOX, LEGEND_DOT_BOX)
		var base: Color = rows[i][0]
		var peak = rows[i][1]
		var phase: float = i / 3.0
		dot.draw.connect(func():
			var wave: float = sin(_time * TAU / PULSE_TIME + phase * TAU)
			var r: float = LEGEND_DOT_RADIUS * (1.0 + PULSE_GROW * wave)
			var glow_t: float = wave * 0.5 + 0.5
			var c: Color = base.lightened(0.18 * glow_t) if peak == null else base.lerp(peak, glow_t)
			_draw_dot(dot, dot.size * 0.5, r, c))
		grid.add_child(dot)
		_legend_dots.append(dot)
		grid.add_child(_hint_text(String(rows[i][2])))


func _on_device_changed(_device: int) -> void:
	if _controls_panel != null and InputDevice.using_pad() != _hints_pad:
		_fill_controls()


## (Re)writes the controls list for the device in use. Keep in step with _input / _process.
func _fill_controls() -> void:
	_hints_pad = InputDevice.using_pad()
	for c in _controls_panel.get_children():
		_controls_panel.remove_child(c)
		c.queue_free()
	var rows: Array
	if _hints_pad:
		var fam: String = InputDevice.pad_family()
		var n := func(id: String) -> String: return ControllerDiagram.button_name(id, fam)
		rows = [
			["%s / %s" % [n.call("lstick"), n.call("dpad")], "Move the map"],
			[n.call("rt"), "Zoom in"],
			[n.call("lt"), "Zoom out"],
			["%s / %s" % [n.call("view"), n.call("b")], "Close"],
		]
	else:
		rows = [
			["WASD / Arrows", "Move the map"],
			["Left-click + drag", "Move the map"],
			["Mouse wheel", "Zoom in / out"],
			["M / Esc", "Close"],
		]
	var grid := _hint_grid(_hint_body(_controls_panel, "Controls"))
	for r in rows:
		var key := Label.new()
		UIKit.set_label(key, "small_label", String(r[0]), "accent", HINT_KEY_SIZE)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(key)
		grid.add_child(_hint_text(String(r[1])))


## Left panel's right edge HINT_GAP short of the phone, right panel's left edge HINT_GAP past it,
## both centred on the phone's resting height.
func _place_hints() -> void:
	if _rig == null:
		return
	var left_x: float = _rig.position.x
	var mid_y: float = _rest_y + _phone_size.y * 0.5
	if _controls_panel != null:
		_controls_panel.size = Vector2.ZERO   # shrink to content
		_controls_panel.position = Vector2(left_x - HINT_GAP - _controls_panel.size.x,
			mid_y - _controls_panel.size.y * 0.5)
	if _legend_panel != null:
		_legend_panel.size = Vector2.ZERO
		_legend_panel.position = Vector2(left_x + _phone_size.x + HINT_GAP,
			mid_y - _legend_panel.size.y * 0.5)


func _hint_panel() -> PanelContainer:
	var p := UIKit.make_panel()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Margin + a title inside `panel`; returns the column the rows go in.
func _hint_body(panel: PanelContainer, title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, HINT_PAD)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", HINT_ROW_GAP + 4)
	margin.add_child(col)
	col.add_child(_hint_heading(title))
	return col


func _hint_heading(title: String) -> Label:
	var head := Label.new()
	UIKit.set_label(head, "subtitle", title, "field_fg", HINT_TITLE_SIZE)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return head


func _hint_grid(col: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", HINT_COL_GAP)
	grid.add_theme_constant_override("v_separation", HINT_ROW_GAP)
	col.add_child(grid)
	return grid


func _hint_text(text: String) -> Label:
	var l := Label.new()
	UIKit.set_label(l, "chip", text, "field_fg", HINT_TEXT_SIZE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


# ============================================================
# OPEN / CLOSE
# ============================================================

func _play_open() -> void:
	if _rig == null:
		close()
		return
	_spinner_tween = create_tween().set_loops()
	_spinner_tween.tween_property(_spinner, "rotation_degrees", 360.0, SPINNER_SPIN_TIME).from(0.0)
	_rig.modulate.a = 0.0
	create_tween().tween_property(_dim, "modulate:a", 1.0, SLIDE_IN_TIME)
	create_tween().tween_property(_rig, "modulate:a", 1.0, SLIDE_IN_TIME * 0.6)
	var rise := create_tween()
	rise.tween_property(_rig, "position:y", _rest_y - PHONE_OVERSHOOT, SLIDE_IN_TIME * 0.78) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	rise.tween_property(_rig, "position:y", _rest_y, SLIDE_IN_TIME * 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await rise.finished
	if _closing:
		return
	# Landed: the loading screen goes and the map fades up in its place.
	_stop_spinner()
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(_cover, "modulate:a", 0.0, MAP_FADE_IN)
	reveal.tween_property(_content, "modulate:a", 1.0, MAP_FADE_IN)
	reveal.tween_property(_blips, "modulate:a", 1.0, MAP_FADE_IN)
	if _hints != null:
		reveal.tween_property(_hints, "modulate:a", 1.0, MAP_FADE_IN)
	_ready_for_input = true


func close() -> void:
	if _closing:
		return
	_closing = true
	_ready_for_input = false
	_dragging = false
	_stop_spinner()
	if _rig != null:
		var fade := create_tween().set_parallel(true)
		fade.tween_property(_content, "modulate:a", 0.0, MAP_FADE_OUT)
		fade.tween_property(_blips, "modulate:a", 0.0, MAP_FADE_OUT)
		if _hints != null:
			fade.tween_property(_hints, "modulate:a", 0.0, MAP_FADE_OUT)
		await fade.finished
		create_tween().tween_property(_dim, "modulate:a", 0.0, SLIDE_OUT_TIME)
		create_tween().tween_property(_rig, "modulate:a", 0.0, SLIDE_OUT_TIME)
		var leave := create_tween()
		leave.tween_property(_rig, "position:y", _rest_y - PHONE_OVERSHOOT, SLIDE_OUT_TIME * 0.25) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		leave.tween_property(_rig, "position:y", _offscreen_y(), SLIDE_OUT_TIME * 0.75) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		await leave.finished
	MapManager.set_overworld_paused(false)
	if _player != null and is_instance_valid(_player) and _player.has_method("unlock_movement"):
		_player.unlock_movement()
	queue_free()


func _stop_spinner() -> void:
	if _spinner_tween != null and _spinner_tween.is_valid():
		_spinner_tween.kill()
	_spinner_tween = null


func _offscreen_y() -> float:
	return UIKit.screen_h() + PHONE_OFFSCREEN_PAD


# ============================================================
# INPUT
# ============================================================

## Opened as the Town Hall's gift (MapManager._reveal_tracker_app): the "You received" notice sits
## over the phone and owns every press until it is cleared, so the map lets input straight past
## (and its dim stops catching clicks) until release_hold().
func hold_for_message() -> void:
	_held = true
	_dragging = false
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE


func release_hold() -> void:
	_held = false
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP


## Everything is eaten while the map is up, so nothing reaches the world or the main-menu shortcut.
func _input(event: InputEvent) -> void:
	if _held:
		return
	get_viewport().set_input_as_handled()
	if not _ready_for_input:
		return
	# M / pad Back toggles it shut; Escape, Backspace and pad B back out of it.
	if UIInput.is_world_map(event) or UIInput.is_cancel(event):
		close()
		return
	if event is InputEventKey:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(ZOOM_STEP, _screen.get_local_mouse_position())
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(1.0 / ZOOM_STEP, _screen.get_local_mouse_position())
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
		return
	if event is InputEventMouseMotion and _dragging:
		_centre -= (event as InputEventMouseMotion).relative / _zoom
		_apply_view()


func _process(delta: float) -> void:
	_time += delta
	if _ready_for_input and not _held:
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):  dir.x -= 1.0   # arrows, D-pad, stick
		if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"): dir.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):    dir.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):  dir.y += 1.0
		if dir != Vector2.ZERO:
			_centre += dir.normalized() * PAN_SPEED * delta / _zoom
			_apply_view()
		# Pad zoom: RT in, LT out, about the middle of the screen.
		var pull: float = 0.0
		for id in Input.get_connected_joypads():
			pull += Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT)
		if absf(pull) > PAD_TRIGGER_DEADZONE:
			_zoom_at(pow(PAD_ZOOM_RATE, clampf(pull, -1.0, 1.0) * delta), _screen_size * 0.5)
	if _blips != null:
		_blips.queue_redraw()
	for d in _legend_dots:
		d.queue_redraw()


# ============================================================
# THE VIEW
# ============================================================

## Opens centred on the player (or the middle of what is unlocked, if they are on no area).
func _start_view() -> void:
	_zoom = ZOOM_DEFAULT
	_centre = _bounds.get_center()
	for b in _blip_list:
		if b["kind"] == "player":
			_centre = b["pos"]
			break
	_apply_view()


## Zooms by `factor`, keeping the picture point under `screen_point` where it is.
func _zoom_at(factor: float, screen_point: Vector2) -> void:
	var new_zoom := clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, _zoom):
		return
	var half := _screen_size * 0.5
	var under := _centre + (screen_point - half) / _zoom
	_zoom = new_zoom
	_centre = under - (screen_point - half) / _zoom
	_apply_view()


## Keeps the view inside the unlocked part of the picture and moves the content to match.
func _apply_view() -> void:
	if _content == null:
		return
	var half := _screen_size * 0.5 / _zoom
	for axis in 2:
		var lo: float = _bounds.position[axis] + half[axis]
		var hi: float = _bounds.end[axis] - half[axis]
		if lo > hi:
			_centre[axis] = (_bounds.position[axis] + _bounds.end[axis]) * 0.5
		else:
			_centre[axis] = clampf(_centre[axis], lo, hi)
	_content.scale = Vector2(_zoom, _zoom)
	_content.position = _screen_size * 0.5 - _centre * _zoom


func _to_screen(picture_pos: Vector2) -> Vector2:
	return _screen_size * 0.5 + (picture_pos - _centre) * _zoom


# ============================================================
# BLIPS - who is where
# ============================================================

func _collect_blips() -> void:
	_blip_list.clear()
	var current := ""
	var scene := get_tree().current_scene
	if scene != null:
		current = String(scene.scene_file_path).get_file().get_basename()

	var constants := _load_constants()
	var date: int = GameState.get_date()
	var time: String = GameState.get_time()
	var indoors: Dictionary = {}   # icon Vector2 -> Array of blips, laid out side by side at the end

	var maps: Array = AREAS.keys() + INTERIORS.keys()
	for map_name: String in maps:
		var area := area_for(map_name)
		if not is_area_unlocked(area):
			continue
		var is_interior := INTERIORS.has(map_name)
		var actors: Array[Dictionary] = _live_actors() if map_name == current \
			else _scheduled_actors(map_name, date, time, constants)
		for a in actors:
			var blip := _blip_for(a, is_interior)
			if blip.is_empty():
				continue
			if is_interior:
				var icon: Vector2 = INTERIORS[map_name][1]
				if not indoors.has(icon):
					indoors[icon] = []
				indoors[icon].append(blip)
			else:
				blip["pos"] = _off_blocked(Vector2(a["pos"]) * float(AREAS[map_name]["scale"])
					+ Vector2(AREAS[map_name]["offset"]))
				_blip_list.append(blip)

	# The player, last so they draw over everyone.
	var me := {"kind": "player", "colour": COL_PLAYER, "radius": PLAYER_RADIUS, "phase": 0.0}
	if AREAS.has(current) and _player != null and is_instance_valid(_player):
		me["pos"] = _off_blocked((_player as Node2D).global_position * float(AREAS[current]["scale"])
			+ Vector2(AREAS[current]["offset"]))
		_blip_list.append(me)
	elif INTERIORS.has(current):
		var icon: Vector2 = INTERIORS[current][1]
		if not indoors.has(icon):
			indoors[icon] = []
		indoors[icon].append(me)

	# Each building's dots in a centred grid, CLUSTER_PER_ROW to a row: the player first, then
	# Olly / Ellie / Alexander, then the opponents (stable within each kind).
	var order := {"player": 0, "story": 1, "opponent": 2}
	for icon: Vector2 in indoors:
		var group: Array = indoors[icon]
		var keyed: Array = []
		for i in group.size():
			keyed.append([int(order.get(group[i]["kind"], 3)), i, group[i]])
		keyed.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
		group = keyed.map(func(k): return k[2])
		var n: int = group.size()
		var rows: int = int(ceil(float(n) / CLUSTER_PER_ROW))
		var step: float = STORY_RADIUS * 2.0 + CLUSTER_GAP
		for i in n:
			var row: int = floori(float(i) / CLUSTER_PER_ROW)
			var in_row: int = mini(CLUSTER_PER_ROW, n - row * CLUSTER_PER_ROW)
			var col: int = i % CLUSTER_PER_ROW
			var b: Dictionary = group[i]
			b["pos"] = icon
			b["offset"] = Vector2((col - (in_row - 1) * 0.5) * step, (row - (rows - 1) * 0.5) * step)
			_blip_list.append(b)

	# Draw order: opponents under story characters under the player.
	var rank := {"opponent": 1, "story": 3, "player": 4}
	_blip_list.sort_custom(func(x, y): return rank.get(x["kind"], 0) < rank.get(y["kind"], 0))


## {"kind", "colour", "radius", "phase"} for one actor, or {} when it is not drawn.
func _blip_for(a: Dictionary, _is_interior: bool) -> Dictionary:
	var story := _story_name(String(a["name"]), String(a.get("friendly", "")))
	var phase := randf()
	if story != "":
		# Dark while they are an opponent you have not played yet under this name (Olly, Olly 2,
		# Ellie 3, Alexander 3...); pale once played, or when they are an NPC / shopkeeper.
		var ready: bool = a["is_opponent"] and not _has_played(String(a["name"]))
		var col: Color = STORY_COLOURS[story] if ready else STORY_DONE_COLOURS[story]
		var peak_col: Color = STORY_PEAKS[story] if ready else COL_STORY_DONE_PEAK
		return {"kind": "story", "colour": col, "peak": peak_col, "radius": STORY_RADIUS, "phase": phase}
	# Only opponents and the three story characters are shown, indoors and out: no NPC or
	# shopkeeper dots. An opponent who is not battleable right now (an Elder busy as an NPC, a
	# beaten "Defeated" stand-in) is an NPC in the cast, so it never reaches this point.
	if not a["is_opponent"]:
		return {}
	var opp := String(a["name"])
	var base := COL_OPP_NEW_BASE
	var peak := COL_OPP_NEW_PEAK
	if GameState.has_beaten_opponent(opp):
		base = COL_OPP_BEATEN_BASE
		peak = COL_OPP_BEATEN_PEAK
	elif _has_played(opp):
		base = COL_OPP_MET_BASE
		peak = COL_OPP_MET_PEAK
	return {"kind": "opponent", "colour": base, "peak": peak, "radius": DOT_RADIUS, "phase": phase}


## Any finished match against this opponent name: beaten, or on their head-to-head record.
func _has_played(opp: String) -> bool:
	if GameState.has_beaten_opponent(opp):
		return true
	var record: Array = GameState.get_opponent_record(opp)
	return int(record[0]) + int(record[1]) > 0


func _story_name(tracking: String, friendly: String) -> String:
	if _story_regex == null:
		_story_regex = RegEx.new()
		_story_regex.compile("(?i)\\b(" + "|".join(PackedStringArray(STORY_COLOURS.keys())) + ")\\b")
	for n in [friendly, tracking]:
		var m := _story_regex.search(n)
		if m != null:
			var word := m.get_string(1).to_lower()
			for key: String in STORY_COLOURS:
				if key.to_lower() == word:
					return key
	return ""


## The current map's actors, where they stand right now. Positions are global = world px.
func _live_actors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("opponents"):
		if node is Node2D and "opponent_name" in node:
			out.append({"name": String(node.opponent_name), "is_opponent": true,
				"pos": (node as Node2D).global_position})
	for node in get_tree().get_nodes_in_group("npcs"):
		if node is Node2D and "npc_name" in node:
			out.append({"name": String(node.npc_name), "friendly": String(node.friendly_name),
				"npc_type": String(node.npc_type), "is_opponent": false,
				"pos": (node as Node2D).global_position})
	return out


## Another map's cast for this slot, filtered exactly as MapManager filters a spawn.
func _scheduled_actors(map_name: String, date: int, time: String, constants: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cast: Dictionary = CharacterSchedule.cast_for(map_name, date, time, MapManager.evaluate_condition)
	# The Town Hall's busy Elders are NPCs this slot -- no battle dot for them.
	if map_name == TownHallCrowd.MAP_NAME:
		cast = TownHallCrowd.apply(cast, date, time, null)
	var origin := _container_offset(map_name)
	for section in ["opponents", "npcs"]:
		var pool: Dictionary = constants.get(section, {})
		for entry: Dictionary in cast.get(section, []):
			var name := String(entry.get("name", ""))
			var consts: Dictionary = pool.get(name, {})
			for key in consts:
				if not entry.has(key):
					entry[key] = consts[key]
			if not MapManager.evaluate_condition(entry.get("condition", {})):
				continue
			if entry.get("placeholder", false) or not entry.has("position"):
				continue
			var p: Dictionary = entry["position"]
			out.append({"name": name, "friendly": String(entry.get("friendly_name", name)),
				"npc_type": String(entry.get("npc_type", "")), "is_opponent": section == "opponents",
				"pos": origin + Vector2(float(p["x"]), float(p["y"]))})
	return out


## Actor positions in the character files are relative to the map's OPPONENTS/NPCS container, so
## its offset is read off the packed scene (nothing is instanced).
func _container_offset(map_name: String) -> Vector2:
	if not _offset_cache.has(map_name):
		_offset_cache[map_name] = _read_container_offset(map_name)
	return _offset_cache[map_name]


func _read_container_offset(map_name: String) -> Vector2:
	var path := SCENE_DIR + map_name + ".tscn"
	var packed: PackedScene = SceneCache.get_packed_scene(path)
	if packed == null and ResourceLoader.exists(path):
		packed = load(path)
	if packed == null:
		return Vector2.ZERO
	var state := packed.get_state()
	for i in state.get_node_count():
		var node_path := String(state.get_node_path(i))
		if node_path == "./OPPONENTS" or node_path == "./NPCS":
			for j in state.get_node_property_count(i):
				if state.get_node_property_name(i, j) == &"position":
					return state.get_node_property_value(i, j)
			return Vector2.ZERO
	return Vector2.ZERO


## `pos` if it is not on a tree or water pixel, else the nearest pixel that is not, searched in
## growing square rings out to SNAP_MAX. Left where it was if nothing clear is that close.
func _off_blocked(pos: Vector2) -> Vector2:
	if _pic_image == null or not _is_blocked(Vector2i(pos.round())):
		return pos
	var at := Vector2i(pos.round())
	for r in range(1, SNAP_MAX + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			# Only the ring's edge: the full rows at top and bottom, the two end pixels elsewhere.
			var step: int = 1 if absi(dy) == r else 2 * r
			for dx in range(-r, r + 1, step):
				var p := at + Vector2i(dx, dy)
				if _is_blocked(p):
					continue
				var d := Vector2(dx, dy).length_squared()
				if d < best_d:
					best_d = d
					best = p
		if best_d < INF:
			return Vector2(best)
	return pos


func _is_blocked(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= _pic_image.get_width() or p.y >= _pic_image.get_height():
		return true
	return _blocked.has(_pic_image.get_pixelv(p).to_rgba32())


func _load_constants() -> Dictionary:
	var f := FileAccess.open(CONSTANTS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


# ============================================================
# DRAWING
# ============================================================

func _draw_blips() -> void:
	var pulse_t: float = _time * TAU / PULSE_TIME
	for b in _blip_list:
		var at: Vector2 = _to_screen(b["pos"]) + Vector2(b.get("offset", Vector2.ZERO))
		var phase: float = float(b["phase"])
		var wave: float = sin(pulse_t + phase * TAU)                 # -1..1
		var r: float = float(b["radius"]) * (1.0 + PULSE_GROW * wave)
		if at.x < -r * RING_REACH or at.y < -r * RING_REACH \
				or at.x > _screen_size.x + r * RING_REACH or at.y > _screen_size.y + r * RING_REACH:
			continue
		var colour: Color = b["colour"]
		match String(b["kind"]):
			"opponent", "story":
				colour = colour.lerp(Color(b["peak"]), wave * 0.5 + 0.5)
			_:
				colour = colour.lightened(0.18 * (wave * 0.5 + 0.5))
		# Radar rings on the player and the story characters.
		if b["kind"] == "player" or b["kind"] == "story":
			for k in 2:
				var p: float = fposmod(_time / RING_TIME + phase + k * 0.5, 1.0)
				var ring_col := colour
				ring_col.a = (1.0 - p) * 0.7
				_blips.draw_arc(at, float(b["radius"]) * (1.0 + p * (RING_REACH - 1.0)), 0.0, TAU,
					32, ring_col, RING_WIDTH, true)
		_draw_dot(_blips, at, r, colour)


## One blip's body: soft halo, dark rim, fill. Shared with the legend so they match exactly.
func _draw_dot(canvas: CanvasItem, at: Vector2, r: float, colour: Color) -> void:
	var glow := colour
	glow.a = GLOW_ALPHA
	canvas.draw_circle(at, r * GLOW_SCALE, glow, true, -1.0, true)
	canvas.draw_circle(at, r + OUTLINE_PX, COL_OUTLINE, true, -1.0, true)
	canvas.draw_circle(at, r, colour, true, -1.0, true)
