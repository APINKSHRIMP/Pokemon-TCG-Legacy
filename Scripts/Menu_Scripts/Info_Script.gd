extends Node

# ─── Constants ───────────────────────────────────────────────────────────────

const SPRITE_FOLDER      := "res://Image_Assets/Character_Sprites/In_Battle_Sprites"
const SLEEVE_FOLDER      := "res://Image_Assets/Sleeves"
const SLEEVE_DEFAULT     := "res://Image_Assets/Sleeves/1_Default_English.png"
const COIN_FOLDER        := "res://Image_Assets/Coins"
const MAX_NAME_LENGTH    := 21
const OWNED_CARDS_FOLDER := "user://Player_Owned_Cards"

# Target display sizes — uniform regardless of source image dimensions
const SPRITE_SIZE  := Vector2(280, 360)  # fit (whole sprite visible, letterboxed)
const SLEEVE_SIZE  := Vector2(150, 210)  # fit (whole card back visible)
const COIN_SIZE    := Vector2(80, 80)    # fit (coins are roughly square)

var PLAYER_DATA_PATH: String:
	get: return GameState.PLAYER_CURRENT_DATA_PATH

# ─── State ───────────────────────────────────────────────────────────────────

var saved_player_name : String = ""

var _cheat_label       : Label = null
var _cheat_label_token : int   = 0

# ─── Node references ─────────────────────────────────────────────────────────

@onready var name_box      : LineEdit    = $"player_name"
@onready var dob_label     : LineEdit    = $"player_dob_label"
@onready var save_btn      : Button      = $"info_save_button"
@onready var cancel_btn    : Button      = $"info_cancel_button"
@onready var player_sprite : TextureRect = $"PlayerSprite"
@onready var sleeve_rect   : TextureRect = $"Sleeve"
@onready var coin_rect     : TextureRect = $"Coin"
@onready var deck_name_lbl : Label       = $"DeckName"
@onready var stats_control : Control     = $"statistics"

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	deck_name_lbl.add_theme_color_override("font_color", Color.BLACK)

	_load_player_data()

	name_box.max_length = MAX_NAME_LENGTH
	name_box.alignment  = HORIZONTAL_ALIGNMENT_CENTER
	name_box.text_changed.connect(_on_name_changed)

	save_btn.disabled = true
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	_populate_stats()


# ─── Data loading ────────────────────────────────────────────────────────────

func _load_player_data() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Info: cannot open " + PLAYER_DATA_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		push_error("Info: player_data.json is malformed")
		return

	# Name
	saved_player_name = data.get("name", "")
	name_box.text = saved_player_name

	# DOB
	var dob: String = data.get("date_of_birth", "")
	dob_label.text = "DOB: " + (dob if dob != "" else "--/--")

	# Battle sprite — fit inside SPRITE_SIZE so different-shaped sprites all appear the same size
	var sprite_name: String = data.get("sprite", "")
	if sprite_name != "":
		if not sprite_name.ends_with(".png"):
			sprite_name += ".png"
		var tex := load(SPRITE_FOLDER + "/" + sprite_name) as Texture2D
		if tex:
			_apply_fit_size(player_sprite, tex, SPRITE_SIZE)

	# Sleeve — fit inside SLEEVE_SIZE (150×210) for a uniform card-back preview
	var sleeve_name: String = data.get("sleeve", "default")
	var sleeve_tex: Texture2D = null
	if sleeve_name != "" and sleeve_name != "default":
		# Originals are a mix of .jpg and .png, so try both before falling back to the default.
		for ext: String in [".jpg", ".png"]:
			var sleeve_path := SLEEVE_FOLDER + "/" + sleeve_name + ext
			if ResourceLoader.exists(sleeve_path):
				sleeve_tex = load(sleeve_path) as Texture2D
				if sleeve_tex != null:
					break
	if sleeve_tex == null:
		sleeve_tex = load(SLEEVE_DEFAULT) as Texture2D
	if sleeve_tex:
		_apply_fit_size(sleeve_rect, sleeve_tex, SLEEVE_SIZE)

	# Coin — fit inside COIN_SIZE; coins are roughly square
	var coin_name: String = data.get("coin", "")
	if coin_name != "":
		if not coin_name.ends_with(".png"):
			coin_name += ".png"
		var coin_tex := load(COIN_FOLDER + "/" + coin_name) as Texture2D
		if coin_tex:
			_apply_fit_size(coin_rect, coin_tex, COIN_SIZE)

	# Deck name
	deck_name_lbl.text = data.get("deck", "")


# ─── Uniform image sizing ────────────────────────────────────────────────────

# Scales the texture to fit entirely inside target (letterbox / minf).
# Sets size explicitly — does not rely on the layout engine.
func _apply_fit_size(rect: TextureRect, tex: Texture2D, target: Vector2) -> void:
	var tex_size := tex.get_size()
	var s        := minf(target.x / tex_size.x, target.y / tex_size.y)
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture      = tex
	rect.size         = Vector2(tex_size.x * s, tex_size.y * s)


# ─── Name box ────────────────────────────────────────────────────────────────

func _on_name_changed(_new_text: String) -> void:
	_refresh_save_button_state()


# ─── Save button state ───────────────────────────────────────────────────────

func _refresh_save_button_state() -> void:
	var name_changed := name_box.text.strip_edges() != saved_player_name
	if name_changed:
		save_btn.disabled = false
		var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
		if green_theme:
			save_btn.theme = green_theme
	else:
		save_btn.disabled = true
		save_btn.theme = load("res://UI_Themes/kenneyUI.tres")


# ─── Save / Cancel ───────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Info: cannot read " + PLAYER_DATA_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		push_error("Info: player_data.json is malformed")
		return

	var new_name := name_box.text.strip_edges()
	if new_name != "":
		data["name"]      = new_name
		saved_player_name = new_name

	var write_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("Info: cannot write " + PLAYER_DATA_PATH)
		return
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)

	save_btn.disabled = true
	save_btn.theme = load("res://UI_Themes/kenneyUI.tres")

	var cheat_msg := CheatManager.check_and_apply(new_name)
	if cheat_msg != "":
		_flash_cheat_message(cheat_msg)


func _on_cancel_pressed() -> void:
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Escape key ──────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Statistics ──────────────────────────────────────────────────────────────

func _populate_stats() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	stats_control.add_child(vbox)

	var prog := GameState.progress

	var unique_defeated : int = prog.get("opponents_beaten", []).size()
	var total_defeated  : int = int(prog.get("opponents_beaten_count_total", 0))
	var packs_opened    : int = int(prog.get("packs_opened_total", 0))
	var sleeves_owned   : int = prog.get("sleeves", []).size()

	var card_totals := _count_owned_cards()

	var rows := [
		["Unique Opponents Defeated", str(unique_defeated)],
		["Total Opponents Defeated",  str(total_defeated)],
		["Packs Opened",              str(packs_opened)],
		["Sleeves Collected",         str(sleeves_owned)],
		["Total Cards Owned",         str(card_totals[0])],
		["Unique Cards Collected",    str(card_totals[1])],
	]

	for row in rows:
		vbox.add_child(_make_stat_row(row[0], row[1]))


func _make_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color.BLACK)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 22)
	val.add_theme_color_override("font_color", Color.BLACK)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	hbox.add_child(lbl)
	hbox.add_child(val)
	return hbox


func _count_owned_cards() -> Array:
	var total_count  : int = 0
	var unique_count : int = 0

	var dir := DirAccess.open(OWNED_CARDS_FOLDER)
	if dir == null:
		return [0, 0]

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with("_player_owned_cards.json"):
			var path := OWNED_CARDS_FOLDER + "/" + fname
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var parsed = JSON.parse_string(f.get_as_text())
				f.close()
				if parsed is Dictionary and parsed.has("owned_cards"):
					for entry in parsed["owned_cards"]:
						if entry is Dictionary:
							var owned := int(entry.get("owned", 0))
							if owned > 0:
								total_count  += owned
								unique_count += 1
		fname = dir.get_next()
	dir.list_dir_end()

	return [total_count, unique_count]


# ─── Cheat notification ──────────────────────────────────────────────────────

func _flash_cheat_message(message: String) -> void:
	# ISSUE #53 FIX: drive the cheat popup as a self-contained "float up + fade out" like the in-match
	# floating labels, animated by a Tween OWNED BY the CanvasLayer (a root child). Previously the
	# cleanup awaited a timer bound to THIS script; escaping the Info sub-menu freed the script and
	# cancelled the await, leaving the label stuck on screen forever. Now it always fades within ~2s.
	print("ISSUE #53 FIX ACTIVE: cheat popup floats up and auto-fades independent of the menu scene")
	_cheat_label_token += 1
	var my_token := _cheat_label_token

	# Remove any existing popup so rapid re-triggers don't stack.
	if _cheat_label != null and is_instance_valid(_cheat_label) and _cheat_label.get_parent() != null:
		_cheat_label.get_parent().queue_free()
	_cheat_label = null

	var layer := CanvasLayer.new()
	layer.name = "CheatCanvasLayer"
	layer.layer = 128
	get_tree().root.add_child(layer)

	var label := Label.new()
	label.name = "CheatNotificationLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = message
	var vp_size := get_viewport().get_visible_rect().size
	label.size = Vector2(vp_size.x, 80)
	label.position = Vector2(0, vp_size.y * 0.5 - 40)
	layer.add_child(label)
	_cheat_label = label

	# Float up ~120px while fading out over 2s, then free the layer. The tween is owned by `layer`
	# (a root child), so it completes even after this Info scene is freed.
	var tween := layer.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 120.0, 2.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 2.0).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func():
		if is_instance_valid(layer):
			layer.queue_free()
		if my_token == _cheat_label_token:
			_cheat_label = null
	)
