extends CanvasLayer

# ============================================================
# TUTORIAL CALLOUT -- one piece of a card on the board, cropped out, grown and ringed
# ============================================================
# The tutorial points at a part of a card while it talks about it: a Weakness, a type
# symbol, a Resistance, an attack. That part is cropped out of the card's LARGE art,
# laid exactly over where it sits on the board, then grown (GROW_TIME) to `grow` times
# its size with the theme's spinning gradient ring round it. dismiss() shrinks it back
# onto the card and frees it.
#
# Preloaded (no class_name). Made by Tutorial_Director._callout():
#   var c := Callout.new()
#   main.add_child(c)
#   c.start(card_node, "base1-67", Rect2(35, 686, 130, 58), 3.0, floor_y)
#
# `region` is in the card art's own pixels on a 600 x 825 card (CARD_PX), so it does
# not care what size the card is drawn on the board.
# ============================================================

const CARD_PX := Vector2(600.0, 825.0)
const CARD_IMAGE_DIR := "res://Image_Assets/Card_Image_Library/"

# TWEAKABLE
const LAYER := 60                 # above the board and its message box, below menus (100) / preview (150)
const GROW_TIME := 1.0            # seconds to grow to full size
const SHRINK_TIME := 0.4          # seconds to shrink back onto the card
const SCREEN_MARGIN := 16.0       # a grown callout is kept this far inside the screen
const FLOOR_GAP := 10.0           # ...and this far above `floor_y` (the message box's top)
const RING_CORNER := 6.0          # the ring's corner radius
const BACKING_PAD := 4.0          # dark backing showing round the crop, px
const BACKING_COL := Color(0.0, 0.0, 0.0, 0.55)

var _card_node: TextureRect = null
var _region: Rect2
var _root: Control
var _backing: ColorRect
var _pic: TextureRect
var _ring: Control
var _from: Rect2
var _to: Rect2
var _tween: Tween = null
var _leaving: bool = false


func _init() -> void:
	layer = LAYER


## Crop `region` (CARD_PX pixels) out of card `uid`, drawn over `card_node`, and grow it
## to `grow` x. `floor_y` is the lowest a grown callout may reach (screen px).
func start(card_node: TextureRect, uid: String, region: Rect2, grow: float, floor_y: float) -> void:
	_card_node = card_node
	_region = region
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var tex: Texture2D = null
	var parts := uid.split("-")
	if parts.size() == 2:
		var path := CARD_IMAGE_DIR + parts[0] + "/Large/" + uid + ".png"
		if ResourceLoader.exists(path):
			tex = load(path)
	if tex == null and card_node != null:
		tex = card_node.texture
	if tex == null:
		queue_free()
		return
	var k := Vector2(tex.get_width(), tex.get_height()) / CARD_PX
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(region.position * k, region.size * k)

	_backing = ColorRect.new()
	_backing.color = BACKING_COL
	_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backing)

	_pic = TextureRect.new()
	_pic.texture = atlas
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_SCALE
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_pic)

	_from = _on_board()
	if _from.size.x <= 1.0:
		push_warning("TUTORIAL CALLOUT: %s is not on the board -- skipped" % uid)
		queue_free()
		return
	var size := _from.size * grow
	var centre := _from.get_center()
	var screen := Vector2(UIKit.screen_w(), UIKit.screen_h())
	var pos := centre - size * 0.5
	pos.x = clampf(pos.x, SCREEN_MARGIN, screen.x - SCREEN_MARGIN - size.x)
	pos.y = clampf(pos.y, SCREEN_MARGIN, minf(screen.y, floor_y - FLOOR_GAP) - size.y)
	_to = Rect2(pos, size)

	_ring = UIKit.add_selection_ring_rect(_root, _from, RING_CORNER)
	UIKit.strengthen_ring(_ring)
	_ring.modulate.a = 0.0
	_apply(0.0)

	var t: float = GROW_TIME if not _reduced() else 0.01
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(_apply, 0.0, 1.0, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_ring, "modulate:a", 1.0, t * 0.5)


## Shrinks back onto the card (wherever it is now) and frees itself.
func dismiss() -> void:
	if _leaving or _root == null or _pic == null or _ring == null:
		if not _leaving:
			queue_free()
		return
	_leaving = true
	if _tween != null:
		_tween.kill()
	var now := _rect_at(_cur_t)
	var home := _on_board()
	if home.size.x <= 1.0:
		home = _from
	_from = home
	_to = now
	var t: float = SHRINK_TIME if not _reduced() else 0.01
	_tween = create_tween().set_parallel(true)
	# Runs _apply from 1 (where it is) down to 0 (on the card).
	_tween.tween_method(_apply, 1.0, 0.0, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_root, "modulate:a", 0.0, t)
	_tween.chain().tween_callback(queue_free)


var _cur_t: float = 0.0

func _rect_at(t: float) -> Rect2:
	return Rect2(_from.position.lerp(_to.position, t), _from.size.lerp(_to.size, t))


func _apply(t: float) -> void:
	_cur_t = t
	var r := _rect_at(t)
	_pic.position = r.position
	_pic.size = r.size
	_backing.position = r.position - Vector2(BACKING_PAD, BACKING_PAD)
	_backing.size = r.size + Vector2(BACKING_PAD, BACKING_PAD) * 2.0
	if _ring != null:
		UIKit.place_selection_ring(_ring, r)


## Where the region sits on the board right now, in screen px.
func _on_board() -> Rect2:
	if _card_node == null or not is_instance_valid(_card_node) or not _card_node.is_inside_tree():
		return Rect2()
	var card: Rect2 = CardDetailPanel._screen_rect_of(_card_node)
	var s := card.size / CARD_PX
	return Rect2(card.position + _region.position * s, _region.size * s)


func _reduced() -> bool:
	var ui := get_node_or_null("/root/UITheme")
	return ui != null and ui.motion_reduced()
