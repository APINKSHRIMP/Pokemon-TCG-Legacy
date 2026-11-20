class_name MedalReveal
extends Node

# ============================================================
# MEDAL REVEAL - "you earned a medal", granted like a gift.
# The same look as every other gift: the black 80% dim, the item (here a spinning 3D coin - MedalCoin3D) at the gift
# coin's spot, and the game's own message box with its OK. Press accept / cancel, click ANYWHERE or a pad button to
# dismiss it (this node forwards that press to the box, so the player never has to hit the box itself); with several
# medals earned at once each one follows the last on the same screen.
#
#   await MedalReveal.play(host_node, awards)      awards = MedalData.take_new_awards()
# ============================================================

signal finished
signal _acked

## TWEAKABLE: the coin's resting size is the gift coin's (MapManager.GIFT_COIN_SIZE) times this.
const GROW_TO := 1.25
## Presses this soon after a medal appears are ignored, so a button mashed through the last box can't skip it.
const MIN_HOLD := 0.7

var _awards: Array = []
var _root: Control
var _dim: ColorRect
var _coin: MedalCoin3D
var _sparkle: CPUParticles2D = null
var _age := 0.0


static func play(host: Node, awards: Array) -> void:
	if awards.is_empty() or host == null or not host.is_inside_tree():
		return
	var r := MedalReveal.new()
	r._awards = awards
	host.add_child(r)
	await r.finished
	r.queue_free()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ui: Node = MapManager._ui_layer
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_root)
	# just BELOW the message box, so the box draws over the dim like in every gift
	ui.move_child(_root, maxi(0, MapManager.message_panel.get_index()))
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	_coin = MedalCoin3D.new()
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_coin)
	_run()


func _exit_tree() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()


func _run() -> void:
	for i in range(_awards.size()):
		_age = 0.0
		var def: Dictionary = _awards[i]["def"]
		var tier: int = int(_awards[i]["tier"])
		var metal := MedalData.metal_of(def, tier)
		var tex := _texture(MedalData.art_path(def, tier))
		var sc := UIKit.item_scale()
		var d: float = MapManager.GIFT_COIN_SIZE.x * GROW_TO * sc
		_coin.full_diameter = d
		_coin.size = Vector2(d, d) * 1.15
		_coin.position = Vector2(UIKit.screen_w() * 0.5, UIKit.screen_h() * (MapManager.GIFT_DISPLAY_CENTER_Y_COIN / 1080.0)) - _coin.size * 0.5
		_coin.begin(tex, metal, false)
		if _sparkle != null and is_instance_valid(_sparkle):
			_sparkle.free()
		_sparkle = MedalSparkle.attach(_coin, metal, 0.7, Vector2.ONE * d * 0.42, 2.4)
		var grade := (MedalData.grade_name(def, tier) + " ") if MedalData.is_tiered(def) else ""
		var text := "You've earned the %s%s Medal!" % [grade, String(def.get("name", ""))]
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_gift_received)
		MapManager.show_message_then(text, func() -> void: _acked.emit())
		await _acked
	MapManager._hide_message()   # show_message_then leaves the box up - clear it WITH the dim and the coin
	finished.emit()


func _texture(path: String) -> Texture2D:
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null:
		var img := Image.load_from_file(path)
		if img != null:
			t = ImageTexture.create_from_image(img)
	return t


func _process(delta: float) -> void:
	_age += delta
	_dim.color.a = 0.8 * clampf(_age / 0.25, 0.0, 1.0)


## Accept / cancel / a click anywhere / a pad button all dismiss, by pressing the box's OK for the player. Everything
## else is swallowed so nothing reaches the map behind the gift.
func _input(event: InputEvent) -> void:
	var is_press := false
	if event is InputEventKey:
		is_press = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventJoypadButton:
		is_press = (event as InputEventJoypadButton).pressed
	elif event is InputEventMouseButton:
		is_press = UIInput.is_click(event)
	elif event is InputEventScreenTouch:
		is_press = (event as InputEventScreenTouch).pressed
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton \
			or event is InputEventJoypadMotion or event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
	if is_press and _age >= MIN_HOLD and (UIInput.is_advance(event) or UIInput.is_click(event) \
			or event is InputEventJoypadButton or event is InputEventScreenTouch):
		MapManager.handle_message_accept()
