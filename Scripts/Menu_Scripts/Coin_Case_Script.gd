extends Node

# ─── Constants ───────────────────────────────────────────────────────────────

const COIN_FOLDER        := "res://Image_Assets/Coins"
const COIN_BACK_IMAGE    := "Back Basic.png"
const COIN_SIZE          := Vector2(100, 100)
const COIN_SEPARATION    := 10
const COLUMNS            := 17

# Absolute paths to player data files.
# GDScript's res:// is read-only in exported builds, so player data lives in
# the project folder via an absolute path during development. In a shipped game
# you would swap these to use OS.get_user_data_dir() instead.
var PLAYER_DATA_PATH: String:
	get: return GameState.PLAYER_CURRENT_DATA_PATH
var PLAYER_PROGRESS_PATH: String:
	get: return GameState.PROGRESS_PATH

# ─── State ───────────────────────────────────────────────────────────────────

# Full res:// path of the coin currently selected/animated
var selected_coin_path   : String = ""
var selected_coin_rect   : TextureRect = null

# The coin name stored in player_data.json on load — used to detect unsaved changes
var saved_coin_name      : String = ""

var _active_tween        : Tween = null
var _active_particles    : CPUParticles2D = null
# Tracks which rect received the most recent click — reset each frame in _input
var _last_clicked_rect   : TextureRect = null

# ISSUE #32: input-blocking loading overlay shown while the coin grid builds.
var _loading_overlay     : MenuLoadingOverlay = MenuLoadingOverlay.new()

# Flat set of owned coin filenames e.g. {"Pikachu Gold 1.png": true}
# Using a Dictionary as a set gives O(1) lookups vs iterating an Array
var _owned_coins         : Dictionary = {}

# ─── Zoom state ──────────────────────────────────────────────────────────────
var zoom_overlay     : CanvasLayer = null
var is_zoomed        : bool = false
var last_zoomed_coin : TextureRect = null

# ─── Node references ─────────────────────────────────────────────────────────

@onready var grid        : GridContainer = $"coin_grid_container"
@onready var save_btn    : Button        = $"coin_save_button"
@onready var cancel_btn  : Button        = $"coin_cancel_button"
@onready var audio_player = AudioStreamPlayer.new()

# ─── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	add_child(audio_player)

	var audio_stream = load("res://Audio/BGM/coin_mode (TCG GB Water Club).ogg")
	audio_player.stream = audio_stream
	audio_player.bus = "Master"
	audio_player.stream.loop = true
	audio_player.play()
	_load_owned_coins_list()
	_load_player_data()

	save_btn.disabled = true
	save_btn.pressed.connect(_on_save_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

	_wrap_grid_in_scroll_container()
	# ISSUE #32: block input behind a loading overlay while the (potentially large) coin grid builds.
	_loading_overlay.show(self)
	await get_tree().process_frame
	await _load_coins()
	_loading_overlay.hide()
	if not is_inside_tree():
		return

	# After all coins are in the grid, auto-select the player's saved coin
	if saved_coin_name != "":
		_auto_select_saved_coin()


func _process(_delta: float) -> void:
	# Keep particles locked to the selected coin's screen position every frame.
	# The coin's on-screen position changes as the ScrollContainer is scrolled,
	# so we must update this manually rather than relying on a fixed position.
	if _active_particles and selected_coin_rect:
		_active_particles.global_position = selected_coin_rect.global_position + selected_coin_rect.size / 2.0


# ─── Data loading ────────────────────────────────────────────────────────────

# Reads the "Coins" array from Player_Game_Progress.json into _owned_coins dictionary.
# Each entry is a coin filename, e.g. "Pikachu Gold 1.png"
func _load_owned_coins_list() -> void:
	print("DEBUG CoinCase: opening ", PLAYER_PROGRESS_PATH)
	var file := FileAccess.open(PLAYER_PROGRESS_PATH, FileAccess.READ)
	if file == null:
		push_error("CoinCase: cannot open " + PLAYER_PROGRESS_PATH + " | error: " + str(FileAccess.get_open_error()))
		return
	var raw_text := file.get_as_text()
	file.close()
	print("DEBUG CoinCase: raw JSON length=", raw_text.length(), " preview=", raw_text.left(100))

	var data = JSON.parse_string(raw_text)
	print("DEBUG CoinCase: parsed type=", typeof(data), " value=", data)

	if not data is Dictionary:
		push_error("CoinCase: JSON did not parse to Dictionary, got: " + str(data))
		return
	if not data.has("coins"):
		push_error("CoinCase: 'Coins' key missing. Keys found: " + str(data.keys()))
		return

	print("DEBUG CoinCase: Coins array=", data["coins"])
	for coin_name in data["coins"]:
		_owned_coins[coin_name] = true
	print("DEBUG CoinCase: _owned_coins populated=", _owned_coins)


# Reads player_data.json and stores the current coin name so we know what is
# already saved and can detect when the player picks something different.
func _load_player_data() -> void:
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("CoinCase: cannot open " + PLAYER_DATA_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	# JSON.parse_string returns a Variant — we cast to Dictionary after checking
	var data = JSON.parse_string(json_text)
	if data is Dictionary and data.has("coin"):
		# player_data stores the name without extension, so we append .png
		var raw : String = data["coin"]
		if not raw.ends_with(".png"):
			raw = raw + ".png"
		saved_coin_name = raw


# ─── Scroll container setup ──────────────────────────────────────────────────

func _wrap_grid_in_scroll_container() -> void:
	var parent = grid.get_parent()

	var scroll := ScrollContainer.new()
	scroll.name = "coin_scroll_container"
	scroll.position = grid.position
	scroll.size = grid.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO

	parent.remove_child(grid)
	parent.add_child(scroll)
	scroll.add_child(grid)

	grid.position = Vector2.ZERO
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", COIN_SEPARATION)
	grid.add_theme_constant_override("v_separation", COIN_SEPARATION)


# ─── Coin loading ─────────────────────────────────────────────────────────────

func _load_coins() -> void:
	var dir := DirAccess.open(COIN_FOLDER)
	if dir == null:
		push_error("CoinCase: cannot open folder " + COIN_FOLDER)
		return

	# Collect all filenames first so we can sort them for a consistent order
	var files : Array = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".import"):
			# Skip the back-of-coin image — it is only used as a placeholder
			# for unowned coins and should never appear as its own grid entry
			if file_name != COIN_BACK_IMAGE:
				files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	files.sort()

	for fname in files:
		# ISSUE #32 FIX: bail if the scene was cancelled/freed mid-load (get_tree() would be null).
		if not is_inside_tree():
			return
		_add_coin_to_grid(fname)
		await get_tree().process_frame


func _add_coin_to_grid(file_name: String) -> void:
	var is_owned : bool = _owned_coins.has(file_name)
	print("DEBUG CoinCase: grid file=", file_name, " is_owned=", is_owned)

	# Owned coins show their real image; unowned coins show the back face
	var display_path : String
	if is_owned:
		display_path = COIN_FOLDER + "/" + file_name
	else:
		display_path = COIN_FOLDER + "/" + COIN_BACK_IMAGE

	var texture := load(display_path) as Texture2D
	if texture == null:
		return

	var rect := TextureRect.new()
	rect.texture             = texture
	rect.custom_minimum_size = COIN_SIZE
	rect.size                = COIN_SIZE
	rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode         = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL

	# Tag with the real coin filename — used for matching against player data
	rect.set_meta("coin_name", file_name)
	rect.set_meta("is_owned",  is_owned)

	if is_owned:
		rect.modulate = Color(0.8, 0.8, 0.8)
		rect.gui_input.connect(_on_coin_clicked.bind(rect))
	else:
		# Unowned coins are heavily dimmed and completely ignore mouse input
		rect.modulate     = Color(0.4, 0.4, 0.4)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	grid.add_child(rect)


# After the grid is fully populated, find the rect whose coin_name matches the
# saved coin and trigger the selection animation on it automatically
func _auto_select_saved_coin() -> void:
	for child in grid.get_children():
		if child is TextureRect and child.get_meta("coin_name", "") == saved_coin_name:
			_select_coin(child)
			return


# ─── Click / selection ───────────────────────────────────────────────────────

func _on_coin_clicked(event: InputEvent, rect: TextureRect) -> void:
	if not (event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed):
		return
	# Mark this rect as the last thing clicked so _input knows a valid target was hit
	_last_clicked_rect = rect
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_plus_select)

	if selected_coin_rect and selected_coin_rect != rect:
		_deselect_coin(selected_coin_rect)
		
	_select_coin(rect)
	
	# Enable save only when the chosen coin differs from what is already saved
	var chosen_name : String = rect.get_meta("coin_name", "")
	if chosen_name != saved_coin_name:
		save_btn.disabled = false
		var green_theme = load("res://UI_Themes/kenneyUI-green.tres")
		if green_theme:
			save_btn.theme = green_theme
	else:
		# Player re-clicked the already-saved coin — no changes to save
		save_btn.disabled = true
		save_btn.theme = load("res://UI_Themes/kenneyUI.tres")


func _select_coin(rect: TextureRect) -> void:
	selected_coin_rect = rect
	selected_coin_path = COIN_FOLDER + "/" + rect.get_meta("coin_name", "")
	_apply_selected_animation(rect)
	_start_sparkle(rect)


func _deselect_coin(rect: TextureRect) -> void:
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	if _active_particles:
		_active_particles.queue_free()
		_active_particles = null
	rect.modulate     = Color(0.8, 0.8, 0.8)
	rect.scale        = Vector2(1.0, 1.0)
	rect.pivot_offset = rect.size / 2.0


func _apply_selected_animation(rect: TextureRect) -> void:
	if _active_tween:
		_active_tween.kill()

	rect.pivot_offset = rect.size / 2.0
	rect.modulate     = Color.WHITE

	var tween := create_tween()
	tween.set_loops()
	_active_tween = tween

	tween.tween_property(rect, "modulate", Color.WHITE * 1.1, 0.2)
	tween.parallel().tween_property(rect, "scale", Vector2(1.02, 1.02), 0.2)
	tween.tween_property(rect, "modulate", Color.WHITE * 1.0, 0.2)
	tween.parallel().tween_property(rect, "scale", Vector2(1.0, 1.0), 0.2)


# ─── Save / Cancel ───────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	if selected_coin_rect == null:
		return

	var new_coin_name : String = selected_coin_rect.get_meta("coin_name", "")
	if new_coin_name == "":
		return

	# Read the full JSON, update only the coin field, then write it back
	var file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("CoinCase: cannot read " + PLAYER_DATA_PATH)
		return
	var json_text := file.get_as_text()
	file.close()
	
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gamemode_select)
	
	var data = JSON.parse_string(json_text)
	if not data is Dictionary:
		push_error("CoinCase: player_data.json is malformed")
		return

	# Strip .png to stay consistent with how player_data.json stores the value
	data["coin"] = new_coin_name.trim_suffix(".png")

	var write_file := FileAccess.open(PLAYER_DATA_PATH, FileAccess.WRITE)
	if write_file == null:
		push_error("CoinCase: cannot write " + PLAYER_DATA_PATH)
		return
	# indent="\t" keeps the file human-readable
	write_file.store_string(JSON.stringify(data, "\t"))
	write_file.close()

	saved_coin_name   = new_coin_name
	save_btn.disabled = true
	save_btn.theme    = load("res://UI_Themes/kenneyUI.tres")


func _on_cancel_pressed() -> void:
	SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")


# ─── Escape / Spacebar input ─────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			if is_zoomed:
				_hide_zoom()
				return
			SceneCache.change_scene("res://Scenes/Main_Menu_Scenes/Main_Menu_Scene.tscn")
			return

		if event.keycode == KEY_SPACE:
			if event.pressed and not event.is_echo():
				var rect = _get_hovered_coin()
				if rect == null and last_zoomed_coin != null and is_instance_valid(last_zoomed_coin):
					rect = last_zoomed_coin
				if rect != null:
					_show_zoom(rect)
			elif not event.pressed:
				_hide_zoom()

	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		call_deferred("_check_click_miss")


func _check_click_miss() -> void:
	if _last_clicked_rect == null:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_minus_select)
	_last_clicked_rect = null


# ─── Coin zoom ───────────────────────────────────────────────────────────────

func _get_hovered_coin() -> TextureRect:
	var hovered = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return null
	var node = hovered
	for i in range(5):
		if node == null:
			return null
		if node.has_meta("coin_name") and node.get_meta("is_owned", false):
			return node as TextureRect
		node = node.get_parent()
	return null


func _show_zoom(rect: TextureRect) -> void:
	if is_zoomed:
		return
	if rect.texture == null:
		return

	is_zoomed = true
	last_zoomed_coin = rect

	zoom_overlay = CanvasLayer.new()
	zoom_overlay.layer = 150
	add_child(zoom_overlay)

	var backdrop := ColorRect.new()
	backdrop.color         = Color(0, 0, 0, 0.95)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	zoom_overlay.add_child(backdrop)

	# Scale to 5× the grid cell size (100×100), capped so it fits on screen
	var tex_size  := rect.texture.get_size()
	var target    := Vector2(500.0, 500.0)
	var s         := minf(target.x / tex_size.x, target.y / tex_size.y)
	var disp_size := Vector2(tex_size.x * s, tex_size.y * s)

	var zoom_rect := TextureRect.new()
	zoom_rect.texture      = rect.texture
	zoom_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	zoom_rect.stretch_mode = TextureRect.STRETCH_SCALE
	zoom_rect.size         = disp_size
	zoom_rect.position     = Vector2((1920.0 - disp_size.x) / 2.0, (1080.0 - disp_size.y) / 2.0)
	zoom_overlay.add_child(zoom_rect)


func _hide_zoom() -> void:
	if not is_zoomed:
		return
	is_zoomed = false
	if zoom_overlay != null:
		zoom_overlay.queue_free()
		zoom_overlay = null

# ─── Sparkle particles ───────────────────────────────────────────────────────

func _start_sparkle(target: TextureRect) -> void:
	if _active_particles:
		_active_particles.queue_free()

	var particles := CPUParticles2D.new()
	add_child(particles)
	_active_particles = particles

	particles.global_position      = target.global_position + target.size / 2.0
	particles.z_index              = 50
	particles.amount               = 20
	particles.lifetime             = 0.9
	particles.one_shot             = false
	particles.explosiveness        = 0.0
	particles.emitting             = true
	particles.emission_shape       = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = target.size / 2.0
	particles.direction            = Vector2(0, 0)
	particles.initial_velocity_min = 0.0
	particles.initial_velocity_max = 0.0
	particles.gravity              = Vector2(0, 0)
	particles.scale_amount_min     = 3.0
	particles.scale_amount_max     = 6.0

	var sparkle_colour := _get_coin_sparkle_colour(selected_coin_path)
	var bright         := sparkle_colour.lightened(1.0)

	var gradient := Gradient.new()
	gradient.set_color(0, Color(bright.r, bright.g, bright.b, 0.0))
	gradient.add_point(0.3, sparkle_colour)
	gradient.add_point(0.5, bright)
	gradient.set_color(3, Color(sparkle_colour.r, sparkle_colour.g, sparkle_colour.b, 0.0))
	particles.color_ramp = gradient


func _get_coin_sparkle_colour(coin_path: String) -> Color:
	var n := coin_path.to_lower()
	if " red"    in n: return Color(1.0, 0.2,  0.2)
	if " gold"   in n: return Color(1.0, 0.85, 0.2)
	if " silver" in n: return Color(0.85, 0.85, 0.9)
	if " blue"   in n: return Color(0.3,  0.5,  1.0)
	if " green"  in n: return Color(0.2,  0.9,  0.3)
	if " pink"   in n: return Color(1.0,  0.2,  0.7)
	if " purple" in n: return Color(0.55, 0.1,  1.0)
	if " black"  in n: return Color(0.0,  0.0,  0.0)
	if " brown"  in n: return Color(0.5,  0.3,  0.2)
	return Color(1.0, 1.0, 1.0)
