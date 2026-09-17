class_name FishingArt
extends RefCounted

## Every sprite the fishing minigame draws, plus the anchor pixels it hangs things off.
##
## Frames are AtlasTexture regions of Fishing.png, so the sheet must have a real alpha
## channel (it shipped fully opaque on a black background and was re-exported).
##
## Anchors (the rod's red tip, the bobber's top orange pixel, the fish's head) are found
## by SCANNING the image, never hardcoded, so re-exporting the art self-corrects.
## Everything is cached statically -- the scans run once per frame-region per run.

const SHEET_PATH := "res://Image_Assets/Assorted_Extras/Fishing.png"
const ROD_VERTICAL_PATH := "res://Image_Assets/Assorted_Extras/FishingRodVertical.png"
const ROD_HORIZONTAL_PATH := "res://Image_Assets/Assorted_Extras/FishingRodHorizontal.png"

## Bobber table: 14 frames in two rows of 7, at x = 256 + 16 * column.
##
##   frames 0-6   (the user's sprites 1-7)  the top row: the bobber sinking to nothing
##   frames 7-13  (the user's sprites 8-14) the bottom row, the same again
##
## The two rows are all but identical by design -- the cast plunges down the first, comes
## back up the second and then bobs inside its first few frames. The rects are MEASURED
## off the art (the rows sit at y 8 and y 32, each 21 px tall, 16 px apart across); an
## re-export that moves them has to move these too.
##
## Every frame's BOTTOM pixel row is the waterline: the art sinks by moving DOWN inside
## its cell and being cut off at the bottom edge. That is why the two rows are different
## heights, and why the bobber hangs off bobber_anchor() (its waterline) rather than off
## its top -- anchoring the top made the sink read as "the bottom pixel is being deleted".
const BOBBER_COLUMNS := 7
const BOBBER_FRAMES := 14
const BOBBER_ROW_RECTS: Array[Rect2i] = [
	Rect2i(256, 8, 16, 21),
	Rect2i(256, 32, 16, 21),
]

## Small fish. 0/1/2 are the straight swim cycle, 3/4 the curved "darting" pair.
## Every rect here is the sprite's exact opaque bounding box, measured off the sheet --
## a rect with slack in it drags a neighbouring frame's pixels in once the sprite is
## rotated, which is what "the fish shows two different sprites" was.
const FISH_SMALL_RECTS: Array[Rect2i] = [
	Rect2i(5, 36, 5, 18),
	Rect2i(21, 36, 5, 17),
	Rect2i(37, 36, 5, 17),
	Rect2i(0, 61, 9, 13),
	Rect2i(22, 61, 9, 13),
]

## Big fish silhouettes, sitting directly to the right of the small ones. There are only
## FOUR: 0/1/2 are the straight swim cycle and 3 is the curved dart, and the other half
## of the cycle is the same frames MIRRORED (see the big frame lists in
## Fishing_Minigame.gd). Bounding boxes, same as above.
const FISH_BIG_RECTS: Array[Rect2i] = [
	Rect2i(49, 33, 13, 46),
	Rect2i(65, 33, 13, 46),
	Rect2i(81, 33, 13, 46),
	Rect2i(100, 36, 19, 37),
]

static var _sheet_image_cache: Image = null
static var _textures: Dictionary = {}
static var _images: Dictionary = {}
static var _anchors: Dictionary = {}


# ============================================================
# TEXTURES
# ============================================================

static func bobber_texture(frame: int) -> Texture2D:
	return _frame_texture(_bobber_rect(frame))


static func fish_texture(frame: int, big: bool = false) -> Texture2D:
	return _frame_texture(_fish_rect(frame, big))


## The rod as it is USED, handle at the bottom and red tip at the far end. The vertical
## sheet is stored upside down, so it is flipped once here and everything downstream --
## including rod_tip() and rod_pivot() -- works in the flipped orientation.
static func rod_texture(vertical: bool) -> Texture2D:
	var key := "rodtex_v" if vertical else "rodtex_h"
	if _textures.has(key):
		return _textures[key]
	var tex := ImageTexture.create_from_image(_rod_image(vertical))
	_textures[key] = tex
	return tex


static func fish_frame_count(big: bool = false) -> int:
	return FISH_BIG_RECTS.size() if big else FISH_SMALL_RECTS.size()


static func fish_size(frame: int, big: bool = false) -> Vector2:
	var r := _fish_rect(frame, big)
	return Vector2(r.size.x, r.size.y)


static func rod_size(vertical: bool) -> Vector2:
	var tex := rod_texture(vertical)
	return Vector2(tex.get_width(), tex.get_height()) if tex != null else Vector2.ZERO


# ============================================================
# ANCHOR PIXELS
# ============================================================
# All returned as PIXEL CENTRES relative to the frame's own top-left corner.

## Centre of the bobber's top-most pixel -- the antenna tip, where the line ties on.
static func bobber_top(frame: int) -> Vector2:
	return _anchor("bt%d" % frame, _bobber_rect(frame), "top_any")


## The bobber's WATERLINE: the bottom edge of the frame, on the tie-on column. This is
## the bobber's node origin, so a sinking frame stays put at the surface instead of
## hanging off a top that is moving down inside the cell. Sharing bobber_top()'s x means
## the line ties on at exactly the sprite's own x, which is what stopped it drawing half
## a pixel to one side of the antenna.
static func bobber_anchor(frame: int) -> Vector2:
	return Vector2(bobber_top(frame).x, float(_bobber_rect(frame).size.y))


## Centre of the bobber's BOTTOM-most pixel -- the end of the line, which is what a
## caught Pokémon hangs off. Not the same as bobber_anchor(): a frame that is still
## riding high has empty rows between its art and the waterline.
static func bobber_low(frame: int) -> Vector2:
	return _anchor("bl%d" % frame, _bobber_rect(frame), "bottom_any")


## Centre of the fish's top-most pixel: its head, and its rotation origin.
static func fish_head(frame: int, big: bool = false) -> Vector2:
	return _anchor("fh%d%s" % [frame, "b" if big else "s"], _fish_rect(frame, big), "top_any")


## Centre of the rod's red tip, in UNFLIPPED texture pixels.
static func rod_tip(vertical: bool) -> Vector2:
	return _rod_anchor(vertical, "top_red")


## Centre of the rod's bottom-most brown pixel: the handle, and the rotation pivot.
## In UNFLIPPED texture pixels -- FishingRodVertical.png is stored upside down, so the
## caller flips the sprite and mirrors this point itself.
static func rod_pivot(vertical: bool) -> Vector2:
	return _rod_anchor(vertical, "bottom_brown")


# ============================================================
# INTERNALS
# ============================================================

static func _bobber_rect(frame: int) -> Rect2i:
	var i := clampi(frame, 0, BOBBER_FRAMES - 1)
	var row: Rect2i = BOBBER_ROW_RECTS[i / BOBBER_COLUMNS]
	return Rect2i(row.position.x + (i % BOBBER_COLUMNS) * row.size.x, row.position.y,
			row.size.x, row.size.y)


static func _fish_rect(frame: int, big: bool) -> Rect2i:
	var list: Array[Rect2i] = FISH_BIG_RECTS if big else FISH_SMALL_RECTS
	return list[clampi(frame, 0, list.size() - 1)]


static func _sheet_image() -> Image:
	if _sheet_image_cache == null:
		var tex: Texture2D = load(SHEET_PATH)
		if tex == null:
			push_error("FishingArt: cannot load " + SHEET_PATH)
			_sheet_image_cache = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		else:
			_sheet_image_cache = tex.get_image()
			if _sheet_image_cache.is_compressed():
				_sheet_image_cache.decompress()
	return _sheet_image_cache


static func _frame_texture(rect: Rect2i) -> Texture2D:
	var key := "t%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if _textures.has(key):
		return _textures[key]
	var atlas := AtlasTexture.new()
	atlas.atlas = load(SHEET_PATH)
	atlas.region = Rect2(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	# Without this a ROTATED sprite samples just outside its region and drags the
	# neighbouring frame in along one edge -- the "fish shows two sprites at once" bug.
	atlas.filter_clip = true
	_textures[key] = atlas
	return atlas


static func _rod_image(vertical: bool) -> Image:
	var key := "rod_v" if vertical else "rod_h"
	if _images.has(key):
		return _images[key]
	var tex: Texture2D = load(ROD_VERTICAL_PATH) if vertical else load(ROD_HORIZONTAL_PATH)
	var img: Image
	if tex == null:
		push_error("FishingArt: cannot load the %s rod" % ("vertical" if vertical else "horizontal"))
		img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	else:
		img = tex.get_image()
		if img.is_compressed():
			img.decompress()
		if vertical:
			# FishingRodVertical.png is drawn tip-down: its red mark sits 3px from the
			# bottom. One flip puts the tip at the top and the handle at the bottom, the
			# same way round as the horizontal rod.
			img.flip_y()
	_images[key] = img
	return img


static func _rod_anchor(vertical: bool, mode: String) -> Vector2:
	var key := "%s_%s" % ["rv" if vertical else "rh", mode]
	if _anchors.has(key):
		return _anchors[key]
	var point := _scan(_rod_image(vertical), mode, Rect2i(Vector2i.ZERO, _rod_image(vertical).get_size()))
	_anchors[key] = point
	return point


static func _anchor(key: String, rect: Rect2i, mode: String) -> Vector2:
	if _anchors.has(key):
		return _anchors[key]
	var point := _scan(_sheet_image(), mode, rect)
	_anchors[key] = point
	return point


## Finds a single pixel inside `rect` of `img` by the rule named in `mode`, returned as
## its centre relative to the rect's top-left. Falls back to the rect centre when nothing
## matches, so a bad re-export cannot produce a NaN-laden transform.
##
## Pure black counts as empty as well as zero alpha: Fishing.png shipped opaque on a black
## background, so this keeps working whichever version of the sheet is on disk.
static func _scan(img: Image, mode: String, rect: Rect2i) -> Vector2:
	var want_bottom := mode.begins_with("bottom")
	var found_y := -1
	var lo := 0
	var hi := -1
	for y in rect.size.y:
		var row_lo := -1
		var row_hi := -1
		for x in rect.size.x:
			var c := img.get_pixel(rect.position.x + x, rect.position.y + y)
			if c.a <= 0.0 or (c.r8 == 0 and c.g8 == 0 and c.b8 == 0):
				continue
			var hit := false
			match mode:
				"top_any", "bottom_any":
					hit = true
				"top_orange":
					hit = _is_orange(c)
				"bottom_dark":
					hit = not _is_orange(c)
				"top_red":
					hit = _is_red(c)
				"bottom_brown":
					hit = not _is_red(c)
			if not hit:
				continue
			if row_lo < 0:
				row_lo = x
			row_hi = x
		if row_hi >= 0:
			found_y = y
			lo = row_lo
			hi = row_hi
			if not want_bottom:
				break
	if found_y < 0:
		# Nothing matched -- the last bobber frame of a row is a couple of dark pixels, so
		# it has no orange part at all. Use the bottom-most opaque pixel instead of giving up.
		if want_bottom and mode != "bottom_any":
			return _scan(img, "bottom_any", rect)
		return Vector2(rect.size.x, rect.size.y) * 0.5
	# The HORIZONTAL CENTRE of the matched row, not its leftmost pixel: the bobber's
	# antenna is a few pixels wide, and anchoring the line on its left edge drew the line
	# visibly off to one side of it.
	return Vector2((lo + hi) * 0.5 + 0.5, found_y + 0.5)


static func _is_orange(c: Color) -> bool:
	return c.r8 > 150 and c.g8 > 80 and c.b8 < 150


static func _is_red(c: Color) -> bool:
	return c.r8 > 150 and c.g8 < 100 and c.b8 < 100
