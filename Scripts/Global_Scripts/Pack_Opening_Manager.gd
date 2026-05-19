extends Node

# ============================================================
# PACK OPENING MANAGER - Autoload singleton
# ============================================================
# Full pack opening animation (split, card flip-through, summary).
# Called by Pack_Purchase_Script for bought packs and by
# MapManager for gifted packs. All animation logic lives here
# so updating the sequence only requires editing this file.
#
# Usage:
#   PackOpeningManager.open_packs(["base1_a", "base5_c"])
#   PackOpeningManager.open_packs(["base1_a"], 0.0)   # no intro fade
#   PackOpeningManager.all_packs_opened                # signal: done
#   PackOpeningManager.is_active()                     # bool guard
# ============================================================

signal all_packs_opened

const CARD_DISPLAY_SIZE  := Vector2(563, 788)
const PACK_IMAGES_FOLDER := "res://Image_Assets/Packs/"
const CARDBACK_PATH      := "res://Image_Assets/Card_Backs_And_Decks/cardback.png"
const CARD_SET_DATA_PATH := "res://Card_Set_Data/"

var _theme_kenney : Theme = preload("res://UI_Themes/kenneyUI.tres")

# ── Session state ──────────────────────────────────────────
var _is_active           : bool  = false
var _pack_queue          : Array = []
var _intro_fade_duration : float = 0.4

# ── Overlay ────────────────────────────────────────────────
var _overlay : CanvasLayer = null
var _bg_rect : ColorRect   = null

# ── Per-pack animation state ───────────────────────────────
var _current_pack_art    : String          = ""
var _pack_cards          : Array           = []
var _current_card_index  : int             = 0
var _face_card_rect      : TextureRect     = null
var _cardback_rect       : TextureRect     = null
var _waiting_for_advance : bool            = false
var _pack_body_rect      : TextureRect     = null
var _pack_top_rect       : TextureRect     = null
var _flying_card_rects   : Array           = []
var _showing_summary     : bool            = false
var _actual_card_size    : Vector2         = Vector2.ZERO
var _card_pos            : Vector2         = Vector2.ZERO
var _active_particles    : CPUParticles2D  = null
var _stack_rects         : Array           = []
var _new_card_ids        : Dictionary      = {}


# ── Public API ─────────────────────────────────────────────

func open_packs(pack_arts: Array, intro_fade_duration: float = 0.4) -> void:
	if pack_arts.is_empty():
		return
	if _is_active:
		push_warning("PackOpeningManager: already active, ignoring call")
		return
	_is_active           = true
	_pack_queue          = pack_arts.duplicate()
	_intro_fade_duration = intro_fade_duration
	_create_overlay()
	_open_next_pack()


func is_active() -> bool:
	return _is_active


# ── Input ──────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_active:
		return

	if _showing_summary:
		var is_space : bool = event is InputEventKey and event.pressed and event.keycode == KEY_SPACE
		var is_click : bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if is_space or is_click:
			_showing_summary = false
			get_viewport().set_input_as_handled()
			_on_summary_dismissed()
		return

	if _waiting_for_advance:
		var is_space : bool = event is InputEventKey and event.pressed and event.keycode == KEY_SPACE
		var is_click : bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if is_space or is_click:
			get_viewport().set_input_as_handled()
			_advance_card_reveal()


# ── Overlay management ─────────────────────────────────────

func _create_overlay() -> void:
	_overlay       = CanvasLayer.new()
	_overlay.layer = 20
	get_tree().current_scene.add_child(_overlay)

	_bg_rect                = ColorRect.new()
	_bg_rect.color          = Color(0, 0, 0, 0.8)
	_bg_rect.anchor_right   = 1.0
	_bg_rect.anchor_bottom  = 1.0
	_bg_rect.mouse_filter   = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_bg_rect)


func _clear_pack_visuals() -> void:
	for child in _overlay.get_children():
		if child != _bg_rect:
			child.queue_free()
	_pack_cards.clear()
	_face_card_rect      = null
	_cardback_rect       = null
	_pack_body_rect      = null
	_pack_top_rect       = null
	_flying_card_rects.clear()
	_showing_summary     = false
	_waiting_for_advance = false
	_active_particles    = null
	_stack_rects.clear()
	_new_card_ids.clear()
	_current_card_index  = 0


func _finish_all() -> void:
	_is_active = false
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay    = null
	_bg_rect    = null
	_pack_queue.clear()
	emit_signal("all_packs_opened")


# ── Pack queue ─────────────────────────────────────────────

func _open_next_pack() -> void:
	_clear_pack_visuals()
	if _pack_queue.is_empty():
		_finish_all()
		return
	_current_pack_art = _pack_queue.pop_front()
	_start_pack_opening()


func _on_summary_dismissed() -> void:
	if _pack_queue.is_empty():
		_finish_all()
	else:
		_open_next_pack()


# ── Opening animation ──────────────────────────────────────

func _start_pack_opening() -> void:
	var viewport_size   : Vector2 = get_viewport().get_visible_rect().size
	var center_x        : float   = viewport_size.x / 2.0
	var center_y        : float   = viewport_size.y / 2.0

	# Load pack texture and compute display size at 65% of viewport height
	var pack_path : String    = PACK_IMAGES_FOLDER + _current_pack_art + ".png"
	var pack_tex  : Texture2D = _load_texture(pack_path)
	if pack_tex == null:
		push_error("PackOpeningManager: pack texture not found: " + pack_path)
		_open_next_pack()
		return

	var pack_aspect : float   = float(pack_tex.get_width()) / float(pack_tex.get_height())
	var pack_h      : float   = viewport_size.y * 0.65
	var pack_w      : float   = pack_h * pack_aspect
	var pack_size   : Vector2 = Vector2(pack_w, pack_h)
	var center_pos  : Vector2 = Vector2(center_x - pack_size.x / 2.0, center_y - pack_size.y / 2.0)

	# ── Create pack image at centre ──
	var anim_pack := TextureRect.new()
	anim_pack.texture      = pack_tex
	anim_pack.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	anim_pack.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	anim_pack.size         = pack_size
	anim_pack.position     = center_pos
	anim_pack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(anim_pack)

	if _intro_fade_duration > 0.0:
		anim_pack.modulate.a = 0.0
		var fade_tw := create_tween()
		fade_tw.tween_property(anim_pack, "modulate:a", 1.0, _intro_fade_duration)
		await fade_tw.finished

	# ── Split pack into top / body ──
	var top_height  : float = 100.0
	var body_height : float = pack_size.y - top_height
	var tex_w       : float = float(pack_tex.get_width())
	var tex_h       : float = float(pack_tex.get_height())
	var top_tex_h   : float = tex_h * (top_height / pack_size.y)
	var body_tex_h  : float = tex_h - top_tex_h

	var top_atlas := AtlasTexture.new()
	top_atlas.atlas  = pack_tex
	top_atlas.region = Rect2(0, 0, tex_w, top_tex_h)

	var body_atlas := AtlasTexture.new()
	body_atlas.atlas  = pack_tex
	body_atlas.region = Rect2(0, top_tex_h, tex_w, body_tex_h)

	anim_pack.queue_free()

	_pack_top_rect             = TextureRect.new()
	_pack_top_rect.texture     = top_atlas
	_pack_top_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pack_top_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_pack_top_rect.size        = Vector2(pack_size.x, top_height)
	_pack_top_rect.position    = center_pos
	_pack_top_rect.pivot_offset = Vector2(pack_size.x / 2.0, top_height / 2.0)
	_pack_top_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_pack_top_rect)

	_pack_body_rect             = TextureRect.new()
	_pack_body_rect.texture     = body_atlas
	_pack_body_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pack_body_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_pack_body_rect.size        = Vector2(pack_size.x, body_height)
	_pack_body_rect.position    = center_pos + Vector2(0, top_height)
	_pack_body_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_pack_body_rect)

	SoundManagerScript.play_sfx_from_path("res://Audio/SFX/pack_tear_sfx.ogg")
	var split_tw := create_tween()
	split_tw.set_parallel(true)
	split_tw.tween_property(_pack_top_rect,  "position:y", center_pos.y - 20.0, 0.25).set_ease(Tween.EASE_OUT)
	split_tw.tween_property(_pack_body_rect, "position:y", center_pos.y + top_height + 20.0, 0.25).set_ease(Tween.EASE_OUT)
	await split_tw.finished

	var fly_tw := create_tween()
	fly_tw.set_parallel(true)
	fly_tw.tween_property(_pack_top_rect, "rotation_degrees", 10.0, 0.25)
	fly_tw.tween_property(_pack_top_rect, "position:y", -200.0, 0.25).set_ease(Tween.EASE_IN)
	await fly_tw.finished
	_pack_top_rect.queue_free()
	_pack_top_rect = null

	# ── Generate cards (before creating cardback so z_index is correct) ──
	var pack_id_for_set : String = _current_pack_art.rsplit("_", true, 1)[0]
	_pack_cards   = _generate_pack_cards(pack_id_for_set)
	_new_card_ids = _save_cards_to_player(pack_id_for_set, _pack_cards)
	_current_card_index = 0

	# ── Spawn cardback behind pack body ──
	var cardback_tex     : Texture2D = _load_texture(CARDBACK_PATH)
	var cb_aspect        : float     = float(cardback_tex.get_width()) / float(cardback_tex.get_height())
	var actual_card_size : Vector2
	if cb_aspect >= CARD_DISPLAY_SIZE.x / CARD_DISPLAY_SIZE.y:
		actual_card_size = Vector2(CARD_DISPLAY_SIZE.x, CARD_DISPLAY_SIZE.x / cb_aspect)
	else:
		actual_card_size = Vector2(CARD_DISPLAY_SIZE.y * cb_aspect, CARD_DISPLAY_SIZE.y)
	_actual_card_size = actual_card_size

	var card_pos : Vector2 = Vector2(center_x - actual_card_size.x / 2.0, center_y - actual_card_size.y / 2.0)
	_card_pos = card_pos

	_cardback_rect                    = TextureRect.new()
	_cardback_rect.texture            = cardback_tex
	_cardback_rect.expand_mode        = TextureRect.EXPAND_IGNORE_SIZE
	_cardback_rect.stretch_mode       = TextureRect.STRETCH_SCALE
	_cardback_rect.custom_minimum_size = actual_card_size
	_cardback_rect.size               = actual_card_size
	_cardback_rect.position           = card_pos
	_cardback_rect.pivot_offset       = actual_card_size / 2.0
	_cardback_rect.z_index            = _pack_cards.size() + 1
	_cardback_rect.mouse_filter       = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_cardback_rect)

	# ── Slide body off downward, revealing cardback ──
	var slide_tw := create_tween()
	slide_tw.tween_property(_pack_body_rect, "position:y", viewport_size.y + 50.0, 0.25).set_ease(Tween.EASE_IN)
	await slide_tw.finished
	_pack_body_rect.queue_free()
	_pack_body_rect = null

	# ── Pre-spawn first card (hidden, flips in after cardback flips out) ──
	var first_cd  : Dictionary = _pack_cards[0]
	var first_tex : Texture2D  = _load_card_texture(first_cd.get("id", ""), actual_card_size)
	var first_rect := TextureRect.new()
	first_rect.texture             = first_tex
	first_rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	first_rect.stretch_mode        = TextureRect.STRETCH_SCALE
	first_rect.custom_minimum_size = actual_card_size
	first_rect.size                = actual_card_size
	first_rect.position            = card_pos
	first_rect.pivot_offset        = actual_card_size / 2.0
	first_rect.scale               = Vector2(0.0, 1.0)
	first_rect.z_index             = _pack_cards.size()
	first_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(first_rect)

	# ── Flip cardback out ──
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_card_draw_sound)
	var flip_out := create_tween()
	flip_out.tween_property(_cardback_rect, "scale:x", 0.0, 0.25).set_ease(Tween.EASE_IN)
	await flip_out.finished
	_cardback_rect.queue_free()
	_cardback_rect = null

	# ── Flip first card in ──
	_face_card_rect = first_rect
	var flip_in := create_tween()
	flip_in.tween_property(_face_card_rect, "scale:x", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	await flip_in.finished

	# ── Spawn remaining cards as a stack behind the face card ──
	_stack_rects = [_face_card_rect]
	for i in range(1, _pack_cards.size()):
		var cd : Dictionary = _pack_cards[i]
		var fr := TextureRect.new()
		fr.texture             = _load_card_texture(cd.get("id", ""), actual_card_size)
		fr.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		fr.stretch_mode        = TextureRect.STRETCH_SCALE
		fr.custom_minimum_size = actual_card_size
		fr.size                = actual_card_size
		fr.position            = card_pos
		fr.pivot_offset        = actual_card_size / 2.0
		fr.z_index             = _pack_cards.size() - i
		fr.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(fr)
		_stack_rects.append(fr)

	# Holo sparkle on first card if applicable
	_active_particles = null
	if _pack_cards[0].get("rarity", "") == "Rare Holo":
		_active_particles = _start_holo_sparkle(_face_card_rect, _pack_cards[0])

	# NEW label if first card is new
	var first_id : String = _pack_cards[0].get("id", "")
	if _new_card_ids.has(first_id):
		_show_new_label(_face_card_rect)

	_waiting_for_advance = true


func _advance_card_reveal() -> void:
	if _face_card_rect == null or not is_instance_valid(_face_card_rect):
		return

	var viewport_size : Vector2 = get_viewport().get_visible_rect().size

	# Kill current holo particles
	if _active_particles != null and is_instance_valid(_active_particles):
		_active_particles.queue_free()
	_active_particles = null

	# Pre-start holo on next card so it's already glittering as the current flies away
	var next_index    : int             = _current_card_index + 1
	var new_particles : CPUParticles2D  = null
	if next_index < _pack_cards.size():
		if _pack_cards[next_index].get("rarity", "") == "Rare Holo":
			new_particles = _start_holo_sparkle(_stack_rects[next_index], _pack_cards[next_index])

	# Fly current card off screen upward (non-blocking)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_card_draw_sound)
	var flying_card : TextureRect = _face_card_rect
	_flying_card_rects.append(flying_card)
	var fly_tw := create_tween()
	fly_tw.tween_property(flying_card, "position:y", -viewport_size.y, 0.5).set_ease(Tween.EASE_IN)
	fly_tw.tween_callback(Callable(self, "_on_flying_card_finished").bind(flying_card))

	_face_card_rect = null
	_current_card_index += 1

	if _current_card_index >= _pack_cards.size():
		_waiting_for_advance = false
		_show_card_summary()
		return

	# Promote next card immediately — it was already rendered underneath
	_face_card_rect          = _stack_rects[_current_card_index]
	_face_card_rect.size     = _actual_card_size
	_face_card_rect.position = _card_pos
	_face_card_rect.scale    = Vector2(1.0, 1.0)

	var next_id : String = _pack_cards[_current_card_index].get("id", "")
	if _new_card_ids.has(next_id):
		_show_new_label(_face_card_rect)

	_active_particles    = new_particles
	_waiting_for_advance = true


func _on_flying_card_finished(card_rect: TextureRect) -> void:
	if card_rect != null and is_instance_valid(card_rect):
		_flying_card_rects.erase(card_rect)
		card_rect.queue_free()


func _show_card_summary() -> void:
	_waiting_for_advance = false

	# Clean up any cards still in flight
	for c in _flying_card_rects:
		if c != null and is_instance_valid(c):
			c.queue_free()
	_flying_card_rects.clear()

	if _active_particles != null and is_instance_valid(_active_particles):
		_active_particles.queue_free()
	_active_particles = null

	var viewport_size      : Vector2 = get_viewport().get_visible_rect().size
	var card_count         : int     = _pack_cards.size()
	var gap                : float   = 8.0
	var horizontal_padding : float   = 40.0
	var available_w        : float   = viewport_size.x - (horizontal_padding * 2.0) - (gap * (card_count - 1))
	var card_w             : float   = available_w / float(card_count)
	var card_aspect        : float   = CARD_DISPLAY_SIZE.x / CARD_DISPLAY_SIZE.y
	var card_h             : float   = card_w / card_aspect
	var max_h              : float   = viewport_size.y * 0.8
	if card_h > max_h:
		card_h = max_h
		card_w = card_h * card_aspect
	var summary_size : Vector2 = Vector2(card_w, card_h)

	var total_row_w : float = (card_w * card_count) + (gap * (card_count - 1))
	var start_x     : float = (viewport_size.x - total_row_w) / 2.0
	var row_y       : float = (viewport_size.y - card_h) / 2.0

	var summary_rects : Array = []
	for i in range(card_count):
		var cd  : Dictionary = _pack_cards[i]
		var tex : Texture2D  = _load_card_texture(cd.get("id", ""), summary_size)
		var rect := TextureRect.new()
		rect.texture             = tex
		rect.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode        = TextureRect.STRETCH_SCALE
		rect.custom_minimum_size = summary_size
		rect.size                = summary_size
		rect.position            = Vector2(start_x + i * (card_w + gap), row_y)
		rect.pivot_offset        = summary_size / 2.0
		rect.modulate.a          = 0.0
		rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(rect)
		summary_rects.append(rect)

	var fade_tw := create_tween()
	fade_tw.set_parallel(true)
	for rect in summary_rects:
		fade_tw.tween_property(rect, "modulate:a", 1.0, 0.35)
	await fade_tw.finished

	_showing_summary = true


# ── Card generation ────────────────────────────────────────

func _generate_pack_cards(set_id: String) -> Array:
	var json_path := CARD_SET_DATA_PATH + set_id + ".json"
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("PackOpeningManager: cannot open card set: " + json_path)
		return []
	var all_cards = JSON.parse_string(file.get_as_text())
	file.close()
	if not all_cards is Array:
		push_error("PackOpeningManager: unexpected card set format in " + json_path)
		return []

	var commons    : Array = []
	var uncommons  : Array = []
	var rares      : Array = []   # Non-holo rares only
	var holo_rares : Array = []   # Rare Holo only — pulled exclusively for god packs
	var rare_pool  : Array = []   # rares + holo_rares — used for the standard rare slot

	for card in all_cards:
		if _is_basic_energy(card):
			continue
		match card.get("rarity", ""):
			"Common":    commons.append(card)
			"Uncommon":  uncommons.append(card)
			"Rare":
				rares.append(card)
				rare_pool.append(card)
			"Rare Holo":
				holo_rares.append(card)
				rare_pool.append(card)

	# ── God-pack check ──────────────────────────────────────────
	# Bump the lifetime pack counter, then decide: every 100th pack is a
	# guaranteed god pack; otherwise a flat 0.5% chance per pack. The natural
	# 0.5% roll does NOT reset the modulo cadence — pack 100, 200, 300… are
	# always god packs no matter how lucky the player was beforehand.
	var pack_number: int = int(GameState.progress.get("packs_opened_total", 0)) + 1
	GameState.progress["packs_opened_total"] = pack_number
	GameState.save_progress()

	var is_god_pack: bool = (pack_number % 100 == 0) or (randf() < 0.005)

	if is_god_pack and holo_rares.size() > 0:
		print("PACK_OPENING: GOD PACK at pack #", pack_number, " (", holo_rares.size(), " unique Rare Holos in set)")
		var god_result : Array = []
		var god_used   : Dictionary = {}
		for _i in range(10):
			var pick := _pick_unique(holo_rares, god_used)
			if not pick.is_empty():
				god_result.append(pick)
		return god_result

	# ── Standard pack ───────────────────────────────────────────
	var bonus_rare : bool  = randf() < 0.25 and rare_pool.size() > 0
	var result     : Array = []
	var used_ids   : Dictionary = {}

	for _i in range(6):
		var pick := _pick_unique(commons, used_ids)
		if not pick.is_empty():
			result.append(pick)

	for _i in range(3):
		var pick := _pick_unique(uncommons, used_ids)
		if not pick.is_empty():
			result.append(pick)

	if rare_pool.size() > 0:
		var pick := _pick_unique(rare_pool, used_ids)
		if not pick.is_empty():
			result.append(pick)

	if bonus_rare:
		var pick := _pick_unique(rare_pool, used_ids)
		if not pick.is_empty():
			result.append(pick)

	return result


func _pick_unique(pool: Array, used_ids: Dictionary) -> Dictionary:
	if pool.is_empty():
		return {}
	var indices : Array = range(pool.size())
	indices.shuffle()
	for i in indices:
		var card : Dictionary = pool[i]
		var id   : String     = card.get("id", "")
		if not used_ids.has(id):
			used_ids[id] = true
			return card
	return pool[randi() % pool.size()]


func _is_basic_energy(card: Dictionary) -> bool:
	if card.get("supertype", "") != "Energy":
		return false
	for st in card.get("subtypes", []):
		if st == "Basic":
			return true
	return false


func _save_cards_to_player(set_id: String, cards: Array) -> Dictionary:
	if cards.is_empty():
		return {}

	var json_path := GameState.OWNED_CARDS_FOLDER + set_id + "_player_owned_cards.json"

	var file := FileAccess.open(json_path, FileAccess.READ)
	var data : Dictionary = {"owned_cards": []}
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			data = parsed

	var new_card_ids : Dictionary = {}

	for card in cards:
		var card_id : String = card.get("id", "")
		if card_id == "":
			continue
		var found := false
		for entry in data["owned_cards"]:
			if entry["card_id"] == card_id:
				if entry["owned"] == 0:
					new_card_ids[card_id] = true
				entry["owned"] = entry["owned"] + 1
				found = true
				break
		if not found:
			new_card_ids[card_id] = true
			data["owned_cards"].append({"card_id": card_id, "owned": 1})

	var write_file := FileAccess.open(json_path, FileAccess.WRITE)
	if write_file == null:
		push_error("PackOpeningManager: cannot write " + json_path)
		return new_card_ids
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()
	return new_card_ids


func _load_card_texture(card_id: String, target_size: Vector2) -> Texture2D:
	var parts := card_id.split("-")
	if parts.size() < 2:
		return _load_texture("res://Image_Assets/null.png")
	var card_set : String = parts[0]
	var path     : String
	if target_size.x < 250 or target_size.y < 350:
		path = "res://Image_Assets/Card_Image_Library/" + card_set + "/Small/" + card_id + ".png"
	else:
		path = "res://Image_Assets/Card_Image_Library/" + card_set + "/Large/" + card_id + ".png"
	var tex := _load_texture(path)
	if tex == null:
		tex = _load_texture("res://Image_Assets/null.png")
	return tex


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


# ── Holo sparkle ──────────────────────────────────────────

func _start_holo_sparkle(card_rect: TextureRect, card_data: Dictionary) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	_overlay.add_child(particles)

	var card_size : Vector2 = card_rect.size
	particles.global_position       = card_rect.global_position + card_size / 2.0
	particles.z_index               = 5
	particles.amount                = 150
	particles.lifetime              = 1.5
	particles.one_shot              = false
	particles.explosiveness         = 0.4
	particles.emitting              = true
	particles.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = card_size / 2.0
	particles.direction             = Vector2(0, 0)
	particles.initial_velocity_min  = 0.0
	particles.initial_velocity_max  = 0.0
	particles.gravity               = Vector2(0, 0)
	particles.scale_amount_min      = 3.0
	particles.scale_amount_max      = 8.0

	var sparkle_colour : Color = _get_holo_sparkle_colour(card_data)
	var bright         : Color = sparkle_colour.lightened(1)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, sparkle_colour)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(sparkle_colour.r, sparkle_colour.g, sparkle_colour.b, 0.0))
	particles.color_ramp = gradient

	return particles


func _get_holo_sparkle_colour(card_data: Dictionary) -> Color:
	var supertype : String = card_data.get("supertype", "")
	if supertype == "Pokémon" or supertype == "Pokemon":
		var types = card_data.get("types", [])
		if types.size() > 0:
			return _get_type_colour(types[0])
	return Color(0.85, 0.85, 0.9)


func _get_type_colour(type_name: String) -> Color:
	match type_name.to_lower():
		"fire":      return Color(1.0, 0.2, 0.1)
		"water":     return Color(0.2, 0.5, 1.0)
		"grass":     return Color(0.2, 0.8, 0.3)
		"lightning": return Color(1.0, 0.9, 0.1)
		"darkness":  return Color(0.15, 0.1, 0.2)
		"psychic":   return Color(0.55, 0.1, 1.0)
		"metal":     return Color(0.6, 0.6, 0.65)
		"fighting":  return Color(0.5, 0.3, 0.2)
		"dragon":    return Color(0.9, 0.7, 0.2)
		"fairy":     return Color(1.0, 0.4, 0.7)
		_:           return Color(1.0, 1.0, 1.0)


# ── NEW label ─────────────────────────────────────────────

func _show_new_label(card_rect: TextureRect) -> void:
	var label := Label.new()
	label.text                 = "NEW!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	label.custom_minimum_size  = Vector2(200, 60)
	label.size                 = Vector2(200, 60)
	label.add_theme_color_override("font_color",         Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_font_size_override("font_size", 52)
	label.theme    = _theme_kenney
	label.z_index  = 100
	label.modulate = Color.WHITE

	var spawn_x : float = card_rect.position.x + (card_rect.size.x / 2.0) - 100.0
	var spawn_y : float = card_rect.position.y + 20.0
	label.position = Vector2(spawn_x, spawn_y)
	_overlay.add_child(label)

	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", spawn_y - 220.0, 2.5)
	tw.tween_property(label, "modulate:a", 0.0, 1.8)
	tw.finished.connect(label.queue_free)
