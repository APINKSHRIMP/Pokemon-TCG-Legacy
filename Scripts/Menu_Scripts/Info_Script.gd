extends Node

# ─── Constants ───────────────────────────────────────────────────────────────

const SPRITE_FOLDER      := "res://Image_Assets/Character_Sprites/In_Battle_Sprites"
const SLEEVE_FOLDER      := "res://Image_Assets/Sleeves"
const SLEEVE_DEFAULT     := "res://Image_Assets/Sleeves/1_Default_English.png"
const COIN_FOLDER        := "res://Image_Assets/Coins"
const MAX_NAME_LENGTH    := 21
const OWNED_CARDS_FOLDER := "user://Player_Owned_Cards"
const OWNED_CARDS_SUFFIX := "_player_owned_cards.json"

# Cosmetic-collection folders, matched to the screens that display them so the X / Y counters
# on this card can never disagree with what those grids actually show.
# Costumes live in SPRITE_FOLDER above — Costume_Script lists that same folder.
const SLEEVE_SMALL_FOLDER   := "res://Image_Assets/Sleeves/small"  # what Sleeves_Scene_Script lists
const COIN_BACK_IMAGE       := "Back Basic.png"  # placeholder art for unowned coins, not a collectible
const DEFAULT_SLEEVE_PREFIX := "1_Default"       # the four starter sleeves the sleeve grid hides

# Statistics panel sizing. `statistics` is 787x510 at y=367 and the "View MEDALS" button overlaps
# it from y=836, so the 12 rows have to fit in ~469px of clear height. Measured in Godot: a row is
# 31px at font 22, so 12 rows come to 438px at separation 6 (the old separation of 10 would have
# reached 482px and run under the button). Shrink the font or the gap here if more rows are added.
const STAT_FONT_SIZE  := 22
const STAT_SEPARATION := 6

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
	if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Escape key ──────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if GameState.close_sub_menu(): return   # ISSUE #52: map is still loaded behind us — just pop this overlay
		SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Statistics ──────────────────────────────────────────────────────────────

func _populate_stats() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", STAT_SEPARATION)
	stats_control.add_child(vbox)

	var prog := GameState.progress

	var unique_defeated : int = prog.get("opponents_beaten", []).size()
	var total_defeated  : int = int(prog.get("opponents_beaten_count_total", 0))
	var packs_opened    : int = int(prog.get("packs_opened_total", 0))
	var matches_won     : int = int(prog.get("matches_won", 0))
	var matches_played  : int = int(prog.get("matches_played", 0))

	var cards := _scan_card_collection()
	var sets_total : int = int(cards["sets_total"])

	# "Unlocked" means the set's pack is buyable — progress["packs_unlocked"] holds set ids.
	# Intersected with the sets that actually exist so a stray entry can never push the
	# numerator past the denominator.
	var sets_unlocked := 0
	for set_id in prog.get("packs_unlocked", []):
		if cards["set_ids"].has(String(set_id)):
			sets_unlocked += 1

	var sleeve_universe  := _sleeve_universe()
	var coin_universe    := _coin_universe()
	var costume_universe := _costume_universe()

	var rows := [
		["Unique Opponents Defeated", str(unique_defeated)],
		["Total Opponents Defeated",  str(total_defeated)],
		["Matches Won",               str(matches_won)],
		["Matches Played",            str(matches_played)],
		["Packs Opened",              str(packs_opened)],
		["Card Sets Unlocked",        _fraction(sets_unlocked, sets_total)],
		["Sets Completed",            _fraction(int(cards["sets_completed"]), sets_total)],
		["Total Cards Owned",         str(cards["total"])],
		["Unique Cards Collected",    str(cards["unique"])],
		["Sleeves Owned",             _fraction(_count_owned(sleeve_universe, GameState.get_sleeves()), sleeve_universe.size())],
		["Coins Owned",               _fraction(_count_owned(coin_universe, GameState.get_coins()), coin_universe.size())],
		["Costumes Owned",            _fraction(_count_owned(costume_universe, GameState.get_costumes()), costume_universe.size())],
	]

	for row in rows:
		vbox.add_child(_make_stat_row(row[0], row[1]))


# "12 / 38" — used by every X / Y counter so they all format identically.
func _fraction(owned: int, total: int) -> String:
	return str(owned) + " / " + str(total)


func _make_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color.BLACK)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	val.add_theme_color_override("font_color", Color.BLACK)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	hbox.add_child(lbl)
	hbox.add_child(val)
	return hbox


# One pass over user://Player_Owned_Cards/ answers every card statistic on this screen:
#   total / unique  — copies owned, and distinct cards owned
#   sets_total      — the denominator for both set counters (one file per set, 38 of them)
#   sets_completed  — a set counts as complete once at least one copy of EVERY card in it is
#                     owned. The owned-cards files leave basic Energy out (base1 lists 96 of its
#                     102 cards), so those unlimited cards can't block completion.
#   set_ids         — {"base1": true, ...}, used to sanity-check progress["packs_unlocked"]
# The folder also holds a Set_ID_Names_Dictionary and hand-made backups ("base1_player_owned_cards
# ALL.json"); the OWNED_CARDS_SUFFIX test is what keeps those out of the counts.
func _scan_card_collection() -> Dictionary:
	var result := {
		"total": 0,
		"unique": 0,
		"sets_total": 0,
		"sets_completed": 0,
		"set_ids": {},
	}

	var dir := DirAccess.open(OWNED_CARDS_FOLDER)
	if dir == null:
		return result

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(OWNED_CARDS_SUFFIX):
			var path := OWNED_CARDS_FOLDER + "/" + fname
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var parsed = JSON.parse_string(f.get_as_text())
				f.close()
				if parsed is Dictionary and parsed.has("owned_cards"):
					result["sets_total"] += 1
					result["set_ids"][fname.trim_suffix(OWNED_CARDS_SUFFIX)] = true
					var cards_in_set := 0
					var owned_in_set := 0
					for entry in parsed["owned_cards"]:
						if entry is Dictionary:
							cards_in_set += 1
							var owned := int(entry.get("owned", 0))
							if owned > 0:
								owned_in_set    += 1
								result["total"] += owned
								result["unique"] += 1
					if cards_in_set > 0 and owned_in_set == cards_in_set:
						result["sets_completed"] += 1
		fname = dir.get_next()
	dir.list_dir_end()

	return result


# ─── Cosmetic collection counting ────────────────────────────────────────────

# Lists the real asset files in a res:// folder. The editor shows "Ditto.jpg" next to its
# "Ditto.jpg.import" sidecar, and an exported build can list "Ditto.jpg.remap" instead, so both
# suffixes are stripped and the result de-duplicated through a Dictionary.
func _list_asset_files(folder: String) -> Dictionary:
	var out : Dictionary = {}
	var dir := DirAccess.open(folder)
	if dir == null:
		push_error("Info: cannot open folder " + folder)
		return out

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean := fname
			if clean.ends_with(".import"):
				clean = clean.trim_suffix(".import")
			elif clean.ends_with(".remap"):
				clean = clean.trim_suffix(".remap")
			out[clean] = true
		fname = dir.get_next()
	dir.list_dir_end()
	return out


# Each universe below is keyed EXACTLY the way that collection is stored in progress, so
# ownership is a straight lookup and no per-collection name-munging is needed here.

# progress["coins"] holds filenames: "Pikachu Gold.png"
func _coin_universe() -> Dictionary:
	var out : Dictionary = {}
	for fname in _list_asset_files(COIN_FOLDER):
		if fname != COIN_BACK_IMAGE:
			out[fname] = true
	return out


# progress["sleeves"] holds bare basenames: "Ditto". The four "1_Default*" card backs are
# excluded to match the sleeve grid, which also hides them — that is what stops the starter
# "default" entry every save begins with from counting as a collected sleeve.
func _sleeve_universe() -> Dictionary:
	var out : Dictionary = {}
	for fname in _list_asset_files(SLEEVE_SMALL_FOLDER):
		if not String(fname).begins_with(DEFAULT_SLEEVE_PREFIX):
			out[String(fname).get_basename()] = true
	return out


# progress["costumes"] holds lowercased filenames: "1ash.png" (GameState lowercases on save)
func _costume_universe() -> Dictionary:
	var out : Dictionary = {}
	for fname in _list_asset_files(SPRITE_FOLDER):
		out[String(fname).to_lower()] = true
	return out


func _count_owned(universe: Dictionary, owned: Array) -> int:
	var count := 0
	for entry in owned:
		if universe.has(String(entry)):
			count += 1
	return count


# ─── Cheat notification ──────────────────────────────────────────────────────

func _flash_cheat_message(message: String) -> void:
	# ISSUE #53 FIX: drive the cheat popup as a self-contained "float up + fade out" like the in-match
	# floating labels, animated by a Tween OWNED BY the CanvasLayer (a root child). Previously the
	# cleanup awaited a timer bound to THIS script; escaping the Info sub-menu freed the script and
	# cancelled the await, leaving the label stuck on screen forever. Now it always fades within ~2s.
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
