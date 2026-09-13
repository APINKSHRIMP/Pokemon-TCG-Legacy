class_name PhoneCall
extends CanvasLayer

# ============================================================
# PHONE CALL — the video-call cutscene
# ============================================================
# A phone rises from the bottom of the screen, connects, and somebody talks to the player through
# it. Three swappable pieces and nothing else:
#
#   PHONE        the handset art. Expected to stay the same, but it is a config field so a
#                character can call from a different model later.
#   TALKING HEAD the caller. One base sprite plus its numbered frames (`_2`, `_3`, ...), which are
#                discovered automatically — the mouth animation is built from however many exist.
#                Swapping a costume is swapping this one name.
#   BACKGROUND   whatever is behind them. Also one name.
#
# Every call is a Dictionary (or an entry in Phone_Calls.json), so a new call is data, not code:
#
#     var call := PhoneCall.play_from_data(self, "ellie_intro")
#     await call.finished
#
# ── THE SCREEN IS A HOLE IN THE PHONE ────────────────────────
# The phone art has a TRANSPARENT rectangle where its screen is, and the caller and background are
# drawn BEHIND it through that hole. The hole is FOUND, not hardcoded: _find_screen_rect() scans the
# phone texture for the transparent region inside its opaque body. That is what makes a new phone
# sprite a drop-in — no measuring, no per-phone constants. A phone whose screen is not transparent
# can still say so with a "screen_rect" field in its config.
#
# Layering, back to front: background, caller, phone, the connecting cover (inside the screen only),
# and the message box over everything.
#
# ── THE MOUTH ────────────────────────────────────────────────
# The frames cycle 1-2-3-2-1-2-3-2... (a ping-pong, so the loop never jumps) and ONLY while the
# message box is actually typing letters. The moment the text stops appearing the caller drops back
# to frame 1 with their mouth shut. That is why this reads as speech rather than as an idle loop —
# see DynamicMessageBox.is_typing(), which is the single thing driving it.
#
# ── AUTO-ADVANCING CALLS ─────────────────────────────────────
# `auto_advance` is for a call that plays over a cutscene the player is not driving — the taxi
# intro. Lines advance on a timer and clicks are swallowed. Every other call is a normal message
# box: click or Space to advance, and the first press finishes the line being typed.
# ============================================================

signal finished

const SPRITE_DIR := "res://Image_Assets/Character_Sprites/Talking_Sprites/"
const DATA_PATH  := "res://NPC_and_Opponent_Data/Phone_Calls.json"

# Reference screen. Every figure below is an absolute pixel in this space, as everywhere else.
const SCREEN_W : float = 1920.0
const SCREEN_H : float = 1080.0

# ─── TWEAKABLE: the phone on screen ──────────────────────────────────────────
# The art is 39x62 pixel art, so this is a big multiplier. Keep it a WHOLE number: the project
# renders textures nearest-neighbour and a fractional scale gives the phone uneven pixel edges.
const PHONE_SCALE    : float = 7.0
const PHONE_CENTRE_X : float = 290.0    # left of centre, clear of the road the taxi drives down
# Where the phone rests is MEASURED, not fixed: its bottom edge sits PHONE_BOTTOM_GAP above the
# message box's top edge. The box grows with its text, so the figure is taken from the TALLEST line
# the call will speak - see _compute_rest_y(). The clamp stops a maximum-height box from pushing the
# phone off the top of the screen.
const PHONE_BOTTOM_GAP : float = 5.0
const PHONE_TOP_Y_MIN  : float = 20.0
# How far below the bottom of the screen it starts and returns to. The phone's own height is added
# to this, so it is fully off-screen either way.
const PHONE_OFFSCREEN_PAD : float = 60.0

# ─── TWEAKABLE: the caller inside the screen ─────────────────────────────────
# The sprite is fitted by its OPAQUE BOUNDS, not by its texture size — the art is a 1024x913 canvas
# with a lot of empty space around the character, and fitting the canvas would leave them tiny and
# off-centre.
#
# A video call frames the HEAD, so the caller is deliberately scaled larger than the screen and
# anchored from the TOP: 1.0 would fit all of them in and leave a face the size of a thumbnail.
# 1.45 crops them at about the chest, which is the framing in the reference mock-up.
const SPRITE_FILL       : float = 1.45  # the caller's full height, as a multiple of the screen's
const SPRITE_TOP_INSET  : float = 0.04  # headroom above them, as a fraction of the screen's height
# What counts as "the head" when centring them - the top of the visible picture, as a fraction of
# its height. See _head_centre_x().
const SPRITE_HEAD_BAND  : float = 0.333

# ─── TWEAKABLE: the mouth ────────────────────────────────────────────────────
const MOUTH_FRAME_TIME : float = 0.085  # seconds per frame while talking

# ─── TWEAKABLE: the sequence ─────────────────────────────────────────────────
# The phone FLIES in and out: short, and with an overshoot at each end - it sails a little past its
# resting place and settles back, and it dips upward before dropping away. That anticipation is most
# of what reads as "thrown on screen"; shortening the time alone just looks rushed.
#
# The overshoot is an explicit PIXEL figure rather than Tween.TRANS_BACK, whose overshoot is a
# fraction of the DISTANCE TRAVELLED - and this phone travels 830px, which came out as an 83px
# bounce: a pogo stick rather than a flourish.
const PHONE_OVERSHOOT   : float = 18.0   # px past the resting place at each end of the flight
const SLIDE_IN_TIME     : float = 0.45   # phone flies in from the bottom
const CONNECT_HOLD      : float = 0.21   # spinner sits on the screen before it connects
const SPINNER_FADE      : float = 0.30   # spinner + word fade out, then the screen drops
const SCREEN_DROP_TIME  : float = 0.70   # the cover slides DOWN out of the screen, revealing them
const FIRST_FRAME_HOLD  : float = 0.40   # the caller sits there before the first line
# Hanging up mirrors the two above: the cover slides back up at the phone's own arrival speed and
# "Disconnecting…" holds for as long as "Connecting…" did. Nobody waits to be hung up on.
const HANGUP_RISE_TIME  : float = 0.43   # the cover slides back UP over them at the end
const HANGUP_HOLD       : float = 0.25   # "Disconnecting…" sits there
const SLIDE_OUT_TIME    : float = 0.38   # phone flies off the bottom

# Auto-advance pacing. The hold starts once the line has finished TYPING, so a slow text speed does
# not eat into the reading time. Per-character, clamped at both ends.
#
# PER_CHAR is the reading rate: 0.036 is about 28 characters a second, brisk but comfortable for
# conversational dialogue. THE CAP IS THE FIGURE THAT MATTERS for a call with long lines - at the
# old 3.0s a 227-character line got the same time as a 100-character one and flashed past. Raise the
# cap, not the rate, when a call reads too fast.
const AUTO_HOLD_PER_CHAR : float = 0.036
const AUTO_HOLD_MIN      : float = 1.60
const AUTO_HOLD_MAX      : float = 9.00

# ─── TWEAKABLE: the connecting cover ─────────────────────────────────────────
# A slight vertical gradient rather than flat black, so a switched-off screen still reads as glass.
const COVER_TOP_COLOUR : Color = Color(0.16, 0.16, 0.18, 1.0)
const COVER_BOT_COLOUR : Color = Color(0.04, 0.04, 0.05, 1.0)
const SPINNER_SIZE     : float = 0.20    # fraction of the screen's WIDTH
const SPINNER_SPIN_TIME: float = 1.0     # one full turn, matching MenuLoadingOverlay
const COVER_LABEL_SIZE : int   = 16
const COVER_LABEL_GAP  : float = 0.055   # fraction of the screen's height, spinner to word
const CONNECT_WORD     : String = "Connecting…"
const HANGUP_WORD      : String = "Disconnecting…"
# How long the connecting/disconnecting screen takes to appear over the black, and how long the
# screen sits BLACK - switched off - before the phone flies away at the end. That black moment plus
# SPINNER_FADE and SLIDE_OUT_TIME is the roughly one second of dead screen on the way out.
const CONNECT_FADE_IN  : float = 0.22
const SCREEN_BLACK_HOLD: float = 0.30

# ─── TWEAKABLE: the caller's name pill, in the corner of the screen ─────────────────────
# The translucent chip a video-call app puts over the picture. It sits INSIDE the screen, so the
# connecting cover hides it and it appears with the caller rather than before them.
# The pill is the CALLER'S OWN COLOUR - the same one their message box wears - rather than black,
# so the two read as one person speaking. Translucent enough to show the picture through it.
const NAME_PILL_ALPHA  : float = 0.72
const NAME_PILL_SIZE   : int   = 12
const NAME_PILL_PAD_X  : float = 10.0
const NAME_PILL_PAD_Y  : float = 4.0
const NAME_PILL_INSET  : float = 8.0     # from the screen's bottom-right corner
const NAME_PILL_RADIUS : int   = 8

# The four steps the screen-finding flood fill walks. A typed const so the loop variable is a
# Vector2i rather than a Variant.
const FILL_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

# The call's layer. Above the map and its UI, below nothing in particular — a call owns the screen.
const CALL_LAYER : int = 180

# ─── Config, with the defaults every call inherits ───────────────────────────
var _speaker: String = ""
var _speaker_sprite: String = ""     # overworld sprite name for the name pill's portrait, optional
var _colour: String = ""             # message-box theme key
var _phone_name: String = "iPhone4"
var _caller_name: String = ""
var _background_name: String = ""
var _lines: Array = []
var _auto_advance: bool = false
var _screen_name: String = ""        # the pill over the picture; "" hides it

# ─── Nodes ───────────────────────────────────────────────────────────────────
var _blocker: Control = null
var _rig: Control = null             # the phone assembly; this is what slides
var _screen: Control = null          # clipped to the hole in the phone
var _bg: TextureRect = null
var _caller: TextureRect = null
var _picture: Control = null         # the caller + their background, faded in as one
var _cover: Control = null           # the phone's own screen, a child of _screen so it clips too
var _connect_ui: Control = null      # the gradient + spinner + word, faded in over the black
var _spinner: ColorRect = null
var _cover_label: Label = null
var _name_pill: PanelContainer = null
var _spinner_tween: Tween = null
var _box: DynamicMessageBox = null

# ─── State ───────────────────────────────────────────────────────────────────
var _frames: Array[Texture2D] = []          # the set currently being cycled
var _default_frames: Array[Texture2D] = []  # the caller's neutral set, returned to between emotions
var _emotion_frames: Dictionary = {}        # emotion -> Array[Texture2D], looked up once each
var _screen_size: Vector2 = Vector2.ZERO    # the hole, kept so a new frame set can re-fit itself
var _frame_order: PackedInt32Array = PackedInt32Array()
var _frame_step: int = 0
var _mouth_timer: float = 0.0
var _screen_rect: Rect2 = Rect2()    # the hole, in RIG-LOCAL pixels
var _phone_size: Vector2 = Vector2.ZERO
var _rest_y: float = 0.0             # where the rig comes to rest, measured off the message box
var _advance_pressed: bool = false   # set by _input, consumed by the line loop
var _playing: bool = false
var _finished: bool = false


## True once the call is over. A caller that means to `await call.finished` MUST check this first:
## the call frees itself the moment it emits, so awaiting a call that has already ended would wait
## for a signal that never comes again.
func is_finished() -> bool:
	return _finished


# ============================================================
# ENTRY POINTS
# ============================================================

## Plays a call defined inline. Returns the node so the caller can `await call.finished` — the call
## is NOT awaited here, so a cutscene can carry on running underneath it.
static func play_call(host: Node, config: Dictionary) -> PhoneCall:
	var call := PhoneCall.new()
	call.configure(config)
	host.add_child(call)
	call.play()
	return call


## Plays a call by its id in Phone_Calls.json. An unknown id is a data typo rather than a crash:
## it warns and returns null, and the caller's `if call != null` path carries on without it.
static func play_from_data(host: Node, call_id: String) -> PhoneCall:
	var config := load_call_data(call_id)
	if config.is_empty():
		push_warning("PhoneCall: no call '%s' in %s" % [call_id, DATA_PATH])
		return null
	return play_call(host, config)


## One entry out of Phone_Calls.json. Read fresh rather than cached — calls are a handful of lines
## of text and this runs once per cutscene.
static func load_call_data(call_id: String) -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("PhoneCall: %s is missing" % DATA_PATH)
		return {}
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PhoneCall: %s is not a JSON object" % DATA_PATH)
		return {}
	var entry = parsed.get(call_id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	return entry


## Every field is optional except `lines` and `caller`.
##
##   speaker      name on the message box's pill. "" gives the system box instead.
##   sprite       the caller's talking-head base name, WITHOUT its _2 / _3 suffixes
##   background   what is behind them
##   phone        the handset art, default iPhone4
##   colour       message_colour key, as an NPC carries
##   pill_sprite  overworld sprite name for the pill's portrait, if they have one yet
##   auto_advance true = timed, input-proof. Default false = an ordinary click-to-advance box.
##   screen_rect  [x, y, w, h] in the PHONE ART's own pixels, for a phone with an opaque screen
func configure(config: Dictionary) -> void:
	_speaker         = String(config.get("speaker", ""))
	_speaker_sprite  = String(config.get("pill_sprite", ""))
	_colour          = String(config.get("colour", ""))
	_phone_name      = String(config.get("phone", "iPhone4"))
	_caller_name     = String(config.get("sprite", ""))
	_background_name = String(config.get("background", ""))
	_lines           = config.get("lines", [])
	_auto_advance    = bool(config.get("auto_advance", false))
	# Defaults to the speaker's name: the pill in the corner of the picture is how a video call says
	# who is on it, so a call that names a speaker gets one without asking. "" switches it off.
	_screen_name     = String(config.get("screen_name", _speaker))
	if config.has("screen_rect"):
		var r: Array = config["screen_rect"]
		if r.size() == 4:
			_screen_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


# ============================================================
# BUILD
# ============================================================

func _ready() -> void:
	layer = CALL_LAYER
	_build()


func _build() -> void:
	# The blocker only eats input on an auto-advancing call; a normal call wants its clicks.
	_blocker = Control.new()
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP if _auto_advance else Control.MOUSE_FILTER_IGNORE
	add_child(_blocker)

	var phone_tex: Texture2D = _load_art(_phone_name)
	if phone_tex == null:
		push_warning("PhoneCall: phone art '%s' not found" % _phone_name)
		return
	_phone_size = Vector2(phone_tex.get_width(), phone_tex.get_height()) * PHONE_SCALE

	# The hole in the handset, in the art's own pixels, scaled up to rig-local pixels.
	if _screen_rect.size == Vector2.ZERO:
		_screen_rect = _find_screen_rect(phone_tex)
	var hole := Rect2(_screen_rect.position * PHONE_SCALE, _screen_rect.size * PHONE_SCALE)

	_rig = Control.new()
	_rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rig.size = _phone_size
	_rig.position = Vector2(PHONE_CENTRE_X - _phone_size.x * 0.5, _offscreen_y())
	add_child(_rig)

	# ── The screen: everything inside it is clipped to the hole ──
	_screen = Control.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.clip_contents = true
	_screen.position = hole.position
	_screen.size = hole.size
	_rig.add_child(_screen)

	# BLACK ALL THE WAY DOWN, behind everything and never moved. The cover that hides the caller
	# SLIDES AWAY, so without this the screen it uncovers would be the transparent hole in the
	# handset - i.e. the map showing through the phone - and the caller would have nothing to fade
	# up from. This is the "switched off" the screen falls back to at both ends of the call.
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.position = Vector2.ZERO
	backdrop.size = hole.size
	_screen.add_child(backdrop)

	# One wrapper for the caller, their background and their name pill, so a single alpha fades the
	# whole picture up from that black as the screen slides away - rather than three nodes to keep
	# in step, and rather than the picture snapping on the instant it is uncovered.
	_picture = Control.new()
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.position = Vector2.ZERO
	_picture.size = hole.size
	_picture.modulate.a = 0.0
	_screen.add_child(_picture)

	_build_background(hole.size)
	_build_caller(hole.size)
	_build_name_pill(hole.size)
	_build_cover(hole.size)

	# ── The handset itself, over the screen ──
	var phone_rect := TextureRect.new()
	phone_rect.texture = phone_tex
	phone_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	phone_rect.stretch_mode = TextureRect.STRETCH_SCALE
	phone_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone_rect.position = Vector2.ZERO
	phone_rect.size = _phone_size
	_rig.add_child(phone_rect)

	_build_message_box()
	_compute_rest_y()


## Where the phone comes to rest: its bottom edge PHONE_BOTTOM_GAP above the top of the message box.
##
## The box's height is not fixed - it grows with the text and is recomputed on every line - so a
## single resting place has to be measured against the TALLEST box the call will ever put up, or a
## long line would grow up behind the phone. measure_panel_height() answers that without showing
## anything, and the emotion tag is stripped first so what is measured is what will be typed.
func _compute_rest_y() -> void:
	if _box == null or _rig == null:
		return
	var tallest: float = 0.0
	for line in _lines:
		var spoken := _split_emotion(String(line))
		tallest = maxf(tallest, _box.measure_panel_height(String(spoken["text"])))
	var box_top: float = DynamicMessageBox.PANEL_BOTTOM_Y - tallest
	_rest_y = maxf(PHONE_TOP_Y_MIN, box_top - PHONE_BOTTOM_GAP - _phone_size.y)


## Cover-fits the background into the screen: scaled until it fills both axes, then centred. A
## background of any shape can be dropped in without letterboxing.
func _build_background(screen_size: Vector2) -> void:
	var tex: Texture2D = _load_art(_background_name)
	if tex == null:
		return
	_bg = TextureRect.new()
	_bg.texture = tex
	# EXPAND_IGNORE_SIZE or the layout clamps the rect back up to the texture's own size - see the
	# note on _build_caller(), where that bug was visible.
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var src := Vector2(tex.get_width(), tex.get_height())
	var scale: float = maxf(screen_size.x / src.x, screen_size.y / src.y)
	_bg.size = src * scale
	_bg.position = (screen_size - _bg.size) * 0.5
	_picture.add_child(_bg)


## The caller, fitted by their OPAQUE BOUNDS rather than by the texture rect — see SPRITE_FILL.
## Every frame shares the same canvas and the same bounds, so the rect is measured once from frame 1
## and the later frames only swap the texture. Anything else would make the head jump as they talk.
func _build_caller(screen_size: Vector2) -> void:
	_screen_size = screen_size
	_default_frames = _load_frames(_caller_name)
	if _default_frames.is_empty():
		push_warning("PhoneCall: caller sprite '%s' not found" % _caller_name)
		return

	_caller = TextureRect.new()
	# EXPAND_IGNORE_SIZE IS LOAD-BEARING. A TextureRect's minimum size is its TEXTURE's size unless
	# this is set, and a Control can never be smaller than its minimum - so the size computed in
	# _fit_caller() was silently clamped back up to the full 1024x913 canvas and the caller was drawn
	# at native size, which inside a 261px screen is a close-up of her hair. Setting the size is not
	# enough on its own; the two go together.
	_caller.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_caller.stretch_mode = TextureRect.STRETCH_SCALE
	_caller.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.add_child(_caller)

	_use_frames(_default_frames)


## Switches the caller to a frame set and restarts the cycle on its first frame.
##
## The rect is re-fitted from the new set's own art rather than kept, so an emotion drawn on a
## different canvas, or with the head somewhere else, still lands framed and centred. For art that
## matches the neutral set - which is the normal case - it computes the same numbers again.
func _use_frames(frames: Array[Texture2D]) -> void:
	if frames.is_empty() or _caller == null:
		return
	_frames = frames
	_frame_order = _ping_pong_order(frames.size())
	_frame_step = 0
	_mouth_timer = 0.0
	_caller.texture = frames[0]
	_fit_caller(frames[0])


## Sizes and places the caller inside the screen. See _head_centre_x() for the horizontal rule and
## SPRITE_FILL / SPRITE_TOP_INSET for the vertical one.
func _fit_caller(tex: Texture2D) -> void:
	var src := Vector2(tex.get_width(), tex.get_height())
	var bounds := _opaque_bounds(tex)
	var scale: float = _screen_size.y * SPRITE_FILL / maxf(1.0, bounds.size.y)
	var centre_x := _head_centre_x(tex, bounds, scale, _screen_size.y)
	_caller.size = src * scale
	# Their HEAD goes in the middle of the screen, near its top edge, and the texture rect is placed
	# so that lands there. Anchored from the top because the caller is taller than the screen:
	# whatever does not fit is cropped off their feet, never their face.
	var bounds_top: float = bounds.position.y * scale
	_caller.position = Vector2(
		_screen_size.x * 0.5 - centre_x * scale,
		_screen_size.y * SPRITE_TOP_INSET - bounds_top)


## The caller's name, over the bottom-right of the picture. Added BEFORE the cover, so it is both
## clipped by the screen and hidden by it while the call is connecting.
func _build_name_pill(screen_size: Vector2) -> void:
	if _screen_name == "":
		return
	_name_pill = PanelContainer.new()
	_name_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = _pill_colour()
	sb.set_corner_radius_all(NAME_PILL_RADIUS)
	sb.content_margin_left   = NAME_PILL_PAD_X
	sb.content_margin_right  = NAME_PILL_PAD_X
	sb.content_margin_top    = NAME_PILL_PAD_Y
	sb.content_margin_bottom = NAME_PILL_PAD_Y
	_name_pill.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	# The "name" role, not "small_label": it is the project's BOLD uppercase face, which is what a
	# name plate wants. White on top of the colour rather than a theme foreground - the pill sits
	# over a photograph, so it cannot borrow the field's contrast.
	UIKit.set_label(lbl, "name", _screen_name, "field_fg", NAME_PILL_SIZE)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_pill.add_child(lbl)
	_picture.add_child(_name_pill)

	# Sized from the TEXT rather than by waiting for the container to lay itself out: this runs
	# during _ready(), before the first frame, and a PanelContainer reports a zero minimum size until
	# it has been through one. Measuring the string is one call and is right immediately.
	var font: Font = lbl.get_theme_font("font")
	var text_w: float = float(NAME_PILL_SIZE)
	var text_h: float = float(NAME_PILL_SIZE)
	if font != null:
		var m := font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_PILL_SIZE)
		text_w = m.x
		text_h = font.get_height(NAME_PILL_SIZE)
	var pill_size := Vector2(text_w + NAME_PILL_PAD_X * 2.0, text_h + NAME_PILL_PAD_Y * 2.0)
	_name_pill.size = pill_size
	_name_pill.position = screen_size - pill_size - Vector2(NAME_PILL_INSET, NAME_PILL_INSET)


## Where the caller's HEAD sits across the art, in the art's own pixels.
##
## NOT the centre of their opaque bounds. A swept ponytail, a bag strap or an outstretched arm drags
## that centre away from the face - Ellie's silhouette centres at x 488 while her head centres at
## 540 - and the face is the one thing the player is looking at, so centring the silhouette leaves
## her visibly off to one side.
##
## In any head-and-shoulders framing the top slice of the PICTURE is the head, so that is what gets
## measured: take the band of art the screen will actually show down to SPRITE_HEAD_BAND of its
## height, and centre on whatever is opaque in it. No per-sprite numbers, so a new caller in a new
## pose frames itself.
##
## get_region().get_used_rect() rather than a GDScript pixel loop: both are C++, and scanning a
## 1024px-wide band by hand is a visible hitch.
func _head_centre_x(tex: Texture2D, bounds: Rect2, scale: float, screen_h: float) -> float:
	var fallback: float = bounds.position.x + bounds.size.x * 0.5
	var img := _readable_image(tex)
	if img == null or scale <= 0.0:
		return fallback

	# The art the screen shows, in art pixels, starting above their head by the top inset.
	var top: int = int(bounds.position.y - screen_h * SPRITE_TOP_INSET / scale)
	var band_h: int = int(screen_h / scale * SPRITE_HEAD_BAND)
	top = clampi(top, 0, img.get_height() - 1)
	band_h = clampi(band_h, 1, img.get_height() - top)

	var head := img.get_region(Rect2i(0, top, img.get_width(), band_h)).get_used_rect()
	if head.size.x <= 0:
		return fallback
	return float(head.position.x) + float(head.size.x) * 0.5


## The caller's colour at pill strength. Their message_colour, which is the same colour their box
## wears; a call with no colour falls back to the default theme's, never to a flat black.
func _pill_colour() -> Color:
	var col := MessageBoxTheme.chip_color(_colour if MessageBoxTheme.has_theme(_colour) else
		MessageBoxTheme.DEFAULT_THEME, 0)
	col.a = NAME_PILL_ALPHA
	return col


## The connecting screen. A child of _screen, so when it slides down it is clipped away by the
## phone's own bezel rather than sliding out across the map.
func _build_cover(screen_size: Vector2) -> void:
	_cover = Control.new()
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.position = Vector2.ZERO
	_cover.size = screen_size
	_screen.add_child(_cover)

	# THE SCREEN IS BLACK WHEN IT IS OFF. This layer is opaque for the whole call and never fades:
	# it is what makes the phone read as a switched-off handset while it flies in and out, rather
	# than as a window with something dimly behind it.
	var off := ColorRect.new()
	off.color = Color.BLACK
	off.mouse_filter = Control.MOUSE_FILTER_IGNORE
	off.position = Vector2.ZERO
	off.size = screen_size
	_cover.add_child(off)

	# Everything that says "connecting" lives in one wrapper so a single alpha turns the whole
	# display on and off over that black - the glass gradient included, since a lit gradient is part
	# of what makes the screen look powered.
	_connect_ui = Control.new()
	_connect_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_ui.position = Vector2.ZERO
	_connect_ui.size = screen_size
	_connect_ui.modulate.a = 0.0
	_cover.add_child(_connect_ui)

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
	_connect_ui.add_child(glass)

	# The same spinning accent square the asset-loading overlays use (MenuLoadingOverlay), sized to
	# the phone screen rather than to a menu box.
	var spin_px: float = screen_size.x * SPINNER_SIZE
	_spinner = ColorRect.new()
	_spinner.color = UITheme.col_a("accent", 0.9)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.size = Vector2(spin_px, spin_px)
	_spinner.pivot_offset = _spinner.size * 0.5
	_spinner.position = Vector2(
		(screen_size.x - spin_px) * 0.5,
		screen_size.y * 0.5 - spin_px * 0.75)
	_connect_ui.add_child(_spinner)

	_cover_label = Label.new()
	UIKit.set_label(_cover_label, "small_label", CONNECT_WORD, "field_fg", COVER_LABEL_SIZE)
	_cover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover_label.size = Vector2(screen_size.x, 0.0)
	_cover_label.position = Vector2(
		0.0, _spinner.position.y + spin_px + screen_size.y * COVER_LABEL_GAP)
	_connect_ui.add_child(_cover_label)


## Fades the whole picture - caller, background and name pill - up from the black behind it, or back
## down into it. One alpha on their shared wrapper.
##
## It is never a snap, and it is never left half-way: the picture is only ever brought up while the
## screen is sliding away to reveal it, and only ever taken down while the screen is sliding back
## over it, so the fade rides the movement instead of being a second thing to notice.
##
## Fading is also the only honest way to do this. `modulate` applies to each child SEPARATELY, so
## while the rig fades in at, say, 50%, the cover over the caller is 50% transparent too and the
## caller shows straight through it - which is precisely what an unconnected phone must not do. At
## alpha 0 the picture is gone whatever the rig is doing.
func _fade_picture(to: float, seconds: float) -> Tween:
	var t := create_tween()
	t.tween_property(_picture, "modulate:a", to, seconds)
	return t


## The call's own message box. A normal character box wearing the caller's colour, so a phone call
## looks like every other conversation in the game — the phone above it is what makes it a call.
func _build_message_box() -> void:
	var built := MessageBoxHelper.build(138.0, -1, false)
	_box = built["root"]
	if _speaker == "":
		_box.show_as_plain()
	else:
		# The caller's COLOUR but not their name: a call already says who is speaking, in the pill
		# over the picture, and a second name pill on the box repeats it a foot lower. The character
		# variant keeps the coloured spine and glow, which is the half that is worth having.
		_box.apply_theme(_colour)
		if _screen_name == "":
			_box.set_name_pill(_speaker, _speaker_sprite)
		# Outside the name-pill branch on purpose: a call that shows its caller's name
		# over the picture instead of on the box is still that caller speaking, and the
		# voice follows the speaker, not the pill.
		#
		# pill_sprite is OPTIONAL and most calls leave it out - a video call already says
		# who is on it with the pill over the picture, so it has no overworld portrait to
		# name. Falling back to the talking-head costume is what keeps those calls voiced:
		# SpeechVoice's alias table maps a costume name onto the character's own voice.
		_box.set_voice(_speaker_sprite if _speaker_sprite != "" else _caller_name)
	_box.set_mode("ok")
	# A timed call cannot be advanced, so it must not show the caret that says it can.
	if _auto_advance:
		_box.show_advance_caret(false)
	_box.visible = false
	add_child(_box)


# ============================================================
# THE SEQUENCE
# ============================================================

## Rings, connects, talks, hangs up, leaves. Frees itself at the end, so a caller that does not care
## when it finishes can simply let it run.
func play() -> void:
	# One frame before anything happens. play_call() starts the call in the same breath as creating
	# it, so without this a caller doing `await call.finished` would not have reached its await yet -
	# and on the art-missing path below, which finishes immediately, it would wait for ever.
	await get_tree().process_frame
	if _rig == null:
		# The art failed to load; do not leave a caller awaiting a signal that will never come.
		_finished = true
		finished.emit()
		queue_free()
		return
	_playing = true
	_spin_spinner()
	# The phone fades in as it rises: a call can start over a scene that is itself still fading up
	# from black - the taxi intro does exactly that - and this layer sits above that fade.
	_rig.modulate.a = 0.0

	# ── Rise from the bottom with the screen OFF ──
	# Two tweens rather than one parallel one: the flight is a SEQUENCE (sail past the resting
	# place, settle back onto it) and the fade has to run across both halves of it.
	var fade_in := create_tween()
	fade_in.tween_property(_rig, "modulate:a", 1.0, SLIDE_IN_TIME * 0.6)
	var rise := create_tween()
	rise.tween_property(_rig, "position:y", _rest_y - PHONE_OVERSHOOT, SLIDE_IN_TIME * 0.78) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	rise.tween_property(_rig, "position:y", _rest_y, SLIDE_IN_TIME * 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await rise.finished

	# ── The screen wakes up: the display fades on over the black, then it connects ──
	# Nothing of the call is lit until this point. The phone arrives switched off, which is what
	# makes it read as a phone rather than as a picture frame that flew in.
	var wake := create_tween()
	wake.tween_property(_connect_ui, "modulate:a", 1.0, CONNECT_FADE_IN)
	await wake.finished

	await get_tree().create_timer(CONNECT_HOLD).timeout

	# ── Connected: the display goes dark again, then the screen slides away ──
	# The whole connecting display fades out together - gradient, spinner and word - leaving the
	# screen black, so what slides down is a dead screen rather than a lit one.
	var fade := create_tween()
	fade.tween_property(_connect_ui, "modulate:a", 0.0, SPINNER_FADE)
	await fade.finished
	_stop_spinner()

	# The picture comes up from black IN STEP with the screen sliding away, so the caller does not
	# snap into existence behind a moving edge - the two together read as one transition.
	_fade_picture(1.0, SCREEN_DROP_TIME)
	var drop := create_tween()
	drop.tween_property(_cover, "position:y", _screen.size.y, SCREEN_DROP_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await drop.finished

	# ── Hold on their closed-mouth frame before they start talking ──
	await get_tree().create_timer(FIRST_FRAME_HOLD).timeout

	await _speak_lines()

	# ── Hang up: the screen slides back up over them, then the phone leaves ──
	_box.visible = false
	_cover_label.text = UITheme.cased("small_label", HANGUP_WORD)
	_spin_spinner()
	# Down into the black as the screen comes back over them, the mirror of the reveal.
	_fade_picture(0.0, HANGUP_RISE_TIME)
	var back := create_tween()
	back.set_parallel(true)
	back.tween_property(_cover, "position:y", 0.0, HANGUP_RISE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	back.tween_property(_connect_ui, "modulate:a", 1.0, HANGUP_RISE_TIME)
	await back.finished

	await get_tree().create_timer(HANGUP_HOLD).timeout

	# ── Hung up: the display switches off, and the phone leaves on a dead black screen ──
	# 'Disconnecting' is gone before the flight starts, so the last thing on screen is a phone
	# that has been put down rather than one still mid-message.
	var sleep_screen := create_tween()
	sleep_screen.tween_property(_connect_ui, "modulate:a", 0.0, SPINNER_FADE)
	await sleep_screen.finished
	_stop_spinner()
	await get_tree().create_timer(SCREEN_BLACK_HOLD).timeout

	# A short dip upward before it drops - the wind-up that makes the exit read as thrown rather
	# than simply dropped - and it fades as it goes, so it is GONE rather than merely off-screen by
	# the time `finished` fires. A cutscene waiting on that signal can carry on with nothing of the
	# call left on screen.
	var fade_out := create_tween()
	fade_out.tween_property(_rig, "modulate:a", 0.0, SLIDE_OUT_TIME)
	var leave := create_tween()
	leave.tween_property(_rig, "position:y", _rest_y - PHONE_OVERSHOOT, SLIDE_OUT_TIME * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	leave.tween_property(_rig, "position:y", _offscreen_y(), SLIDE_OUT_TIME * 0.75) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	await leave.finished

	_stop_spinner()
	_playing = false
	_finished = true
	finished.emit()
	queue_free()


## One line at a time. The mouth animation is not driven from here — it follows the box's own
## is_typing() in _process(), so it stays in step however the player has set their text speed.
func _speak_lines() -> void:
	for line in _lines:
		# The emotion is read off the front of the line and the face is changed BEFORE the box says
		# anything, so the expression is already right as the first letter lands. A line with no tag
		# puts the neutral set back - an expression lasts exactly one message.
		var spoken := _split_emotion(String(line))
		_set_emotion(String(spoken["emotion"]))
		var text := String(spoken["text"])
		_box.set_body_text(text)
		_box.visible = true

		if _auto_advance:
			# Wait for the typing to FINISH before the reading hold starts, so a slow text speed
			# does not eat the time the line is readable for.
			while _box.is_typing():
				await get_tree().process_frame
			await get_tree().create_timer(_auto_hold_for(text)).timeout
		else:
			_advance_pressed = false
			while not _advance_pressed:
				await get_tree().process_frame
			_advance_pressed = false


## How long an auto-advancing line stays up once it has finished typing.
func _auto_hold_for(text: String) -> float:
	return clampf(float(text.length()) * AUTO_HOLD_PER_CHAR, AUTO_HOLD_MIN, AUTO_HOLD_MAX)


func _offscreen_y() -> float:
	return SCREEN_H + PHONE_OFFSCREEN_PAD


# ============================================================
# THE MOUTH
# ============================================================

# Frames step ONLY while letters are landing. When the box is not typing — between lines, during the
# reading hold, before the first line — the caller resets to frame 1 with their mouth closed.
func _process(delta: float) -> void:
	if _caller == null or _frames.size() < 2:
		return
	if _box != null and _box.visible and _box.is_typing():
		_mouth_timer -= delta
		if _mouth_timer <= 0.0:
			_mouth_timer = MOUTH_FRAME_TIME
			_frame_step = (_frame_step + 1) % _frame_order.size()
			_caller.texture = _frames[_frame_order[_frame_step]]
	elif _frame_step != 0:
		_frame_step = 0
		_mouth_timer = 0.0
		_caller.texture = _frames[0]


# ============================================================
# EXPRESSIONS
# ============================================================
# A line may open with an emotion tag, and that emotion applies to THAT LINE ONLY:
#
#     "[HAPPY]Oh hey! So you're just coming round the corner then?"
#     "I just saw the movers come and go..."          <- back to the neutral face
#
# The tag names a whole frame set, not a still: the mouth animates through it exactly as it does
# through the neutral set, so an expression talks. Files are the caller's sprite name, the emotion,
# then the frame number:
#
#     Rival_Ellie_Call_Dress_Clutch_Happy_1.png
#     Rival_Ellie_Call_Dress_Clutch_Happy_2.png   ...
#
# Numbering from _1 is the emotion convention; the neutral set's "no suffix, then _2, _3" shape is
# accepted too, so either naming works. Casing is forgiving - [HAPPY] finds Happy, HAPPY or happy.
#
# Missing art is a warning and the neutral face, never a broken call: an emotion nobody has drawn
# yet simply does not change the expression, and the tag is still stripped out of the dialogue.

## Tags that are NOT expressions. [TIME] and [NAME] are dialogue tokens the message box substitutes
## (see DynamicMessageBox._resolve_tokens), and anything in lower case is bbcode - [center], [b] -
## which is why an expression is written in capitals.
const RESERVED_TAGS := ["TIME", "NAME"]


## Splits "[HAPPY]Oh hey!" into its emotion and the words actually spoken. Returns
## { "emotion": "HAPPY", "text": "Oh hey!" }, with an empty emotion when the line has no tag.
func _split_emotion(line: String) -> Dictionary:
	var plain := line.strip_edges()
	if not plain.begins_with("["):
		return { "emotion": "", "text": line }
	var close := plain.find("]")
	if close < 2:
		return { "emotion": "", "text": line }
	var tag := plain.substr(1, close - 1)
	if not _is_emotion_tag(tag):
		return { "emotion": "", "text": line }
	return { "emotion": tag, "text": plain.substr(close + 1).strip_edges() }


func _is_emotion_tag(tag: String) -> bool:
	if tag == "" or tag.to_upper() in RESERVED_TAGS:
		return false
	# Lower case means bbcode. Expressions are capitals, which is what keeps [center] and [b] out.
	if tag == tag.to_lower():
		return false
	# Letters, digits and underscores only - anything else is punctuation, so it was never a tag.
	for i in tag.length():
		var c := tag[i]
		var is_letter := c.to_lower() != c.to_upper()
		var is_digit := c >= "0" and c <= "9"
		if not (is_letter or is_digit or c == "_"):
			return false
	return true


## Puts the named expression on the caller for the line about to be spoken. "" restores the neutral
## set, which is what a line with no tag gets.
func _set_emotion(emotion: String) -> void:
	if _caller == null:
		return
	if emotion == "":
		_use_frames(_default_frames)
		return
	var frames := _frames_for_emotion(emotion)
	_use_frames(frames if not frames.is_empty() else _default_frames)


## The frame set for an emotion, loaded once and remembered - a call that swings between two moods
## does not go back to the filesystem every line. A set that cannot be found is remembered as empty,
## so the warning is printed once rather than per line.
func _frames_for_emotion(emotion: String) -> Array[Texture2D]:
	if _emotion_frames.has(emotion):
		return _emotion_frames[emotion]

	var frames: Array[Texture2D] = []
	for spelling in _emotion_spellings(emotion):
		var base := "%s_%s" % [_caller_name, spelling]
		# _1, _2, _3 ... the emotion convention, then the neutral set's shape as a fallback.
		frames = _load_numbered_frames(base)
		if frames.is_empty():
			frames = _load_frames(base)
		if not frames.is_empty():
			break

	if frames.is_empty():
		push_warning("PhoneCall: no art for expression '%s' on '%s' - wanted %s_%s_1.png. Using the neutral face."
			% [emotion, _caller_name, _caller_name, _emotion_spellings(emotion)[0]])
	_emotion_frames[emotion] = frames
	return frames


## How an emotion tag might be spelled in a filename, best guess first: Happy, then HAPPY as typed,
## then happy. Sprite names in this project are CamelCase, so the capitalised form is tried first.
func _emotion_spellings(emotion: String) -> Array:
	var parts := emotion.split("_", false)
	var camel := ""
	for part in parts:
		camel += "_" if camel != "" else ""
		camel += String(part).substr(0, 1).to_upper() + String(part).substr(1).to_lower()
	var out := [camel]
	for spelling in [emotion, emotion.to_lower(), emotion.to_upper()]:
		if not spelling in out:
			out.append(spelling)
	return out


## 1-2-3-2 for three frames, 1-2-3-4-3-2 for four, and so on — a ping-pong, so looping it plays
## 1 2 3 2 1 2 3 2 1 ... with no jump back to the start.
func _ping_pong_order(count: int) -> PackedInt32Array:
	var order := PackedInt32Array()
	for i in range(count):
		order.append(i)
	for i in range(count - 2, 0, -1):
		order.append(i)
	return order


# ============================================================
# INPUT
# ============================================================

# A normal call advances on a click or Space/Enter, and the FIRST press finishes the line being
# typed rather than skipping past it — the same contract every other message box in the game has.
# An auto-advancing call swallows both instead: it plays over a cutscene the player is not driving.
func _input(event: InputEvent) -> void:
	if not _playing:
		return
	if not (UIInput.is_advance(event) or UIInput.is_click(event)):
		return
	# An auto call eats the input for its whole run - connecting and hanging up included - so a
	# stray click during the cutscene cannot reach the map underneath.
	if _auto_advance:
		get_viewport().set_input_as_handled()
		return
	if _box == null or not _box.visible:
		return
	get_viewport().set_input_as_handled()
	if _box.advance_consumed():
		return
	_advance_pressed = true


# ============================================================
# HELPERS
# ============================================================

func _spin_spinner() -> void:
	_stop_spinner()
	if _spinner == null:
		return
	_spinner_tween = create_tween().set_loops()
	_spinner_tween.tween_property(_spinner, "rotation_degrees", 360.0, SPINNER_SPIN_TIME).from(0.0)


func _stop_spinner() -> void:
	if _spinner_tween != null and _spinner_tween.is_valid():
		_spinner_tween.kill()
	_spinner_tween = null


func _load_art(art_name: String) -> Texture2D:
	if art_name == "":
		return null
	var path := SPRITE_DIR + art_name + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The base sprite plus every numbered frame after it: `Name.png`, `Name_2.png`, `Name_3.png` ...
## Stops at the first gap, so adding a fourth mouth frame to a costume is dropping `_4.png` next to
## the others — no code and no data change.
func _load_frames(base_name: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var first := _load_art(base_name)
	if first == null:
		return out
	out.append(first)
	var n := 2
	while true:
		var tex := _load_art("%s_%d" % [base_name, n])
		if tex == null:
			break
		out.append(tex)
		n += 1
	return out


## Frames numbered from ONE: `Name_1.png`, `Name_2.png` ... the expression convention. Empty when
## there is no `_1`, which is how the caller tells an expression apart from a missing one.
func _load_numbered_frames(base: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var n := 1
	while true:
		var tex := _load_art("%s_%d" % [base, n])
		if tex == null:
			break
		out.append(tex)
		n += 1
	return out


## The opaque part of a texture, in its own pixels. Used to frame the caller by the character rather
## than by the empty canvas around them.
func _opaque_bounds(tex: Texture2D) -> Rect2:
	var img := _readable_image(tex)
	if img == null:
		return Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height()))
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height()))
	return Rect2(used.position, used.size)


## FINDS the phone's screen: the transparent rectangle INSIDE its opaque body.
##
## Not simply "the bounds of every transparent pixel" - the handset has rounded corners, and those
## are transparent too, so that test returns the whole image. The screen is the transparency that
## the OUTSIDE cannot reach: flood-fill the transparent pixels inward from the four edges, and
## whatever transparency is left over is a hole punched through the middle of the art. That is the
## screen, and it is why a new phone sprite is a drop-in - no measuring, no per-phone constants.
##
## A phone with no transparent screen falls back to a centred rectangle over most of the body, which
## is wrong-looking but harmless, and says so; that art should pass "screen_rect" in its config.
func _find_screen_rect(tex: Texture2D) -> Rect2:
	var img := _readable_image(tex)
	if img == null:
		return _fallback_screen_rect(tex)
	var w := img.get_width()
	var h := img.get_height()
	if w <= 2 or h <= 2:
		return _fallback_screen_rect(tex)

	# Flood fill the OUTSIDE. An explicit stack rather than recursion: a phone-sized image is a few
	# hundred thousand pixels and GDScript has no tail calls.
	var outside := {}
	var stack: Array[Vector2i] = []
	for x in range(w):
		_seed_outside(img, outside, stack, Vector2i(x, 0))
		_seed_outside(img, outside, stack, Vector2i(x, h - 1))
	for y in range(h):
		_seed_outside(img, outside, stack, Vector2i(0, y))
		_seed_outside(img, outside, stack, Vector2i(w - 1, y))
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		for step: Vector2i in FILL_NEIGHBOURS:
			var next := at + step
			if next.x < 0 or next.y < 0 or next.x >= w or next.y >= h:
				continue
			_seed_outside(img, outside, stack, next)

	# What is left transparent is the hole.
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.0 or outside.has(Vector2i(x, y)):
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)

	if max_x < min_x or max_y < min_y:
		push_warning("PhoneCall: '%s' has no transparent screen; pass a screen_rect." % _phone_name)
		return _fallback_screen_rect(tex)
	return Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Marks one pixel as reachable from outside the handset, if it is transparent and not marked yet.
func _seed_outside(img: Image, outside: Dictionary, stack: Array[Vector2i], at: Vector2i) -> void:
	if outside.has(at) or img.get_pixel(at.x, at.y).a > 0.0:
		return
	outside[at] = true
	stack.push_back(at)


## An Image whose pixels can actually be read. A texture imported with VRAM compression hands back
## a compressed Image, and get_pixel() / get_used_rect() on one of those is meaningless.
func _readable_image(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		# A duplicate, so decompressing never touches the cached texture everyone else is drawing.
		img = img.duplicate()
		if img.decompress() != OK:
			return null
	return img


func _fallback_screen_rect(tex: Texture2D) -> Rect2:
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	return Rect2(w * 0.1, h * 0.15, w * 0.8, h * 0.7)
