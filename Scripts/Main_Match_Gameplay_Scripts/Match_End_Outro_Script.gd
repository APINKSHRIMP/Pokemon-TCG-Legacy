extends Control

# ============================================================
# MATCH OUTRO SCENE SCRIPT
# ============================================================
# Displays after a match ends. Shows win/loss background,
# plays the appropriate jingle, and (on win) displays reward
# labels that fly in from off-screen. After 7 seconds total
# the scene fades out and returns to the map level.
# ============================================================

# Data loaded at startup
var opponent_data: Dictionary
var player_data: Dictionary
var battle_won: bool = false

# Animation config
var sprite_drift_duration: float = 5.0

# The Kenney UI theme used for reward labels
var kenney_theme = preload("res://UI_Themes/kenneyUI.tres")

# Icon textures for rewards
var pokedollar_icon_tex = preload("res://Image_Assets/Icons/Reward_Icons/pokedollar_icon.png")
var coin_icon_tex = preload("res://Image_Assets/Icons/Reward_Icons/coin_icon.png")
var costume_icon_tex = preload("res://Image_Assets/Icons/Reward_Icons/costume_icon.png")

# Scene node references
@onready var background = $match_outro_background
@onready var player_sprite = $PLAYER/player_sprite
@onready var opponent_sprite = $OPPONENT/opponent_sprite
@onready var win_labels_container = $"WIN LABELS"

# Reward tracking — built during _ready, animated afterwards
var reward_rows: Array = []  # Each entry: { "label": Label, "icon": TextureRect }

# Screen dimensions (matching the 1920x1080 project)
const SCREEN_W: float = 1920.0
const SCREEN_CENTER_X: float = 960.0

# Y positions for reward rows — these are in WIN LABELS local coords.
# The WIN LABELS node is at (762, 684) in the scene so these are offsets
# within that container. We space rows 70px apart starting from y=40
# (roughly where cash_placeholder_label sits).
const REWARD_START_Y: float = 40.0
const REWARD_ROW_SPACING: float = 70.0

# "Rewards:" header sits above the first reward row
const HEADER_Y: float = -10.0

# ============================================================
# INITIALIZATION
# ============================================================

func _ready() -> void:
	# Start fully black so we can fade in
	modulate.a = 0.0
	
	# Hide the placeholder labels — we build our own dynamically
	for child in win_labels_container.get_children():
		child.visible = false
	
	# Determine win or loss
	battle_won = (GameState.battle_result == "win")
	
	# Load data
	load_opponent_data(GameState.current_opponent_name)
	load_player_data()
	
	# Set background texture based on result
	if battle_won:
		var win_tex = load("res://Image_Assets/Backgrounds_And_Borders/Backgrounds/battle_win_screen.png")
		if win_tex:
			background.texture = win_tex
	else:
		var loss_tex = load("res://Image_Assets/Backgrounds_And_Borders/Backgrounds/battle_loss_screen.png")
		if loss_tex:
			background.texture = loss_tex
	
	# Update sprites with correct textures
	update_sprites()
	
	# Stop any existing BGM (match music)
	SoundManagerScript.stop_bgm()
	
	# Play the win or loss jingle
	if battle_won:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_win)
	else:
		SoundManagerScript.play_sfx(SoundManagerScript.SFX_battle_loss)
	
	# Build reward UI (win only)
	if battle_won:
		build_rewards()
	
	# Fade in from black
	var fade_in = create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, 0.5)
	await fade_in.finished
	
	# The scene is now visible and accepting clicks to skip/continue.
	# The player can click at any time — even before animations finish.
	click_enabled = true
	
	# Start sprite drift animation
	animate_sprites()
	
	# Animate rewards flying in (win only)
	if battle_won:
		animate_rewards()

# Track whether the player has clicked to leave
var click_enabled: bool = false
var transitioning: bool = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
	
	# Any mouse click while the scene is showing triggers the transition
	if event is InputEventMouseButton and event.pressed and click_enabled and not transitioning:
		transition_back_to_map()

# ============================================================
# DATA LOADING
# ============================================================

func load_opponent_data(trainer_name: String) -> void:
	var file = FileAccess.open(GameState.current_opponent_json_path, FileAccess.READ)
	if file == null:
		print("Error loading opponent file")
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		print("JSON parse error")
		return

	var opponents = json.data["opponents"]
	for opponent in opponents:
		if opponent.get("name") == trainer_name:
			opponent_data = opponent
			break

	if opponent_data.is_empty():
		print("Opponent with name ", trainer_name, " not found")
		return

	var const_file = FileAccess.open("res://NPC_and_Opponent_Data/All_NPC_Constant_Data.json", FileAccess.READ)
	if const_file != null:
		var const_data = JSON.parse_string(const_file.get_as_text())
		const_file.close()
		if const_data is Dictionary:
			var consts: Dictionary = const_data.get("opponents", {}).get(trainer_name, {})
			for key in consts:
				if not opponent_data.has(key):
					opponent_data[key] = consts[key]

	GameDataManager.opponent_data = opponent_data

func load_player_data() -> void:
	var file = FileAccess.open(GameState.PLAYER_CURRENT_DATA_PATH, FileAccess.READ)
	if file == null:
		print("Error loading player file")
		return
	
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	if error != OK:
		print("JSON parse error for player data")
		return
	
	player_data = json.data
	GameDataManager.player_data = player_data

# ============================================================
# SPRITE SETUP
# ============================================================

func update_sprites() -> void:
	if opponent_data.has("sprite"):
		var path = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + opponent_data["sprite"].to_lower() + ".png"
		var tex = load(path)
		if tex:
			opponent_sprite.texture = tex
		else:
			print("Could not load opponent sprite: ", path)
	
	if player_data.has("sprite"):
		var path = "res://Image_Assets/Character_Sprites/In_Battle_Sprites/" + player_data["sprite"].to_lower() + ".png"
		var tex = load(path)
		if tex:
			player_sprite.texture = tex
			player_sprite.flip_h = true
		else:
			print("Could not load player sprite: ", path)

# ============================================================
# SPRITE DRIFT ANIMATION (same as intro — slow slide apart)
# ============================================================

func animate_sprites() -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_parallel(true)
	tween.tween_property(player_sprite, "position:x", player_sprite.position.x - 100, sprite_drift_duration)
	tween.tween_property(opponent_sprite, "position:x", opponent_sprite.position.x + 100, sprite_drift_duration)

# ============================================================
# REWARD BUILDING (win only)
# ============================================================

func build_rewards() -> void:
	# --- "Rewards:" header (visible immediately, not animated) ---
	var header = Label.new()
	header.text = "Rewards:"
	header.theme = kenney_theme
	header.add_theme_font_size_override("font_size", 42)
	header.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Position the header centred above the reward rows.
	# WIN LABELS container is at x=762 in the scene. We want the header
	# centred on screen, so we offset relative to the container.
	header.position = Vector2(-200, HEADER_Y)
	header.size = Vector2(800, 60)
	win_labels_container.add_child(header)
	
	# Track current row index for vertical positioning
	var row_index: int = 0
	
	# Check if this is the first time beating this opponent
	var is_first_win = not GameState.has_beaten_opponent(GameState.current_opponent_name)
	
	# --- 1. Cash reward (always granted, tripled on first win) ---
	var cash_amount_str = opponent_data.get("cash_reward", "0")
	var cash_amount = int(cash_amount_str)
	if is_first_win:
		cash_amount *= 3
	GameState.add_cash(cash_amount)
	
	var cash_label_text = str(cash_amount)
	if is_first_win:
		cash_label_text += " (First Win ×3!)"
	var cash_row = _create_reward_row(cash_label_text, pokedollar_icon_tex, row_index)
	reward_rows.append(cash_row)
	row_index += 1
	
	# --- First-win-only rewards ---
	if is_first_win:
		# --- 2. Coin reward (first win only) ---
		var coin_reward_key = opponent_data.get("coin_reward", "")
		if coin_reward_key != "" and not GameState.has_coin(coin_reward_key):
			GameState.add_coin_to_collection(coin_reward_key)
			var coin_display_name = format_coin_name(coin_reward_key)
			var coin_row = _create_reward_row(coin_display_name, coin_icon_tex, row_index)
			reward_rows.append(coin_row)
			row_index += 1
		
		# --- 3. Costume reward (first win only, if specified in opponent JSON) ---
		var costume_reward_key = opponent_data.get("costume_reward", "")
		if costume_reward_key != "" and not GameState.has_costume(costume_reward_key):
			GameState.add_costume_to_collection(costume_reward_key)
			var costume_display = costume_reward_key.replace("_", " ") + " Trainer Class"
			costume_display = capitalise_words(costume_display)
			var costume_row = _create_reward_row(costume_display, costume_icon_tex, row_index)
			reward_rows.append(costume_row)
			row_index += 1
		
		# --- 4. Future reward types (card, pack, etc.) go here ---
	
	# Mark opponent as beaten and increment counts (first win only)
	GameState.mark_opponent_beaten(GameState.current_opponent_name)

# Helper: create a label + icon pair for one reward row.
# Both start off-screen and will be animated in later.
func _create_reward_row(label_text: String, icon_texture: Texture2D, row_index: int) -> Dictionary:
	var y_pos = REWARD_START_Y + row_index * REWARD_ROW_SPACING
	
	# WIN LABELS is at x=762 in screen space. Screen centre in local coords = 960 - 762 = 198.
	var local_centre_x: float = 198.0
	
	# Icon is 40px wide with a 10px gap before the label = 50px total offset.
	var icon_gap: float = 50.0
	
	# --- Label (left-aligned, auto-sized to fit text) ---
	var label = Label.new()
	label.text = label_text
	label.theme = kenney_theme
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Don't set a fixed size — let Godot auto-fit to text content.
	# We need to add it to the tree first so it can calculate its size.
	win_labels_container.add_child(label)
	
	# Force a layout update so the label knows its own width
	label.reset_size()
	var label_width = label.size.x
	
	# The combined width of icon + gap + label text
	var total_width = icon_gap + label_width
	
	# Position the label so the icon+label unit is centred on screen.
	# The label sits to the right of the icon, so:
	#   unit_left_edge = local_centre_x - total_width / 2
	#   label_x = unit_left_edge + icon_gap
	var label_final_x = local_centre_x - total_width / 2.0 + icon_gap
	var icon_final_x = local_centre_x - total_width / 2.0
	
	# Start off-screen to the right
	label.position = Vector2(1200.0, y_pos)
	
	# --- Icon (Sprite2D scaled to exactly 40x40) ---
	var icon = Sprite2D.new()
	icon.texture = icon_texture
	icon.centered = false
	var tex_size = icon_texture.get_size()
	icon.scale = Vector2(40.0 / tex_size.x, 40.0 / tex_size.y)
	
	# Start off-screen to the left
	icon.position = Vector2(-1200.0, y_pos + 5)
	win_labels_container.add_child(icon)
	
	return {
		"label": label,
		"icon": icon,
		"label_final_x": label_final_x,
		"icon_final_x": icon_final_x,
	}

# ============================================================
# REWARD FLY-IN ANIMATION
# ============================================================

func animate_rewards() -> void:
	# Wait 0.3 seconds after the scene is visible before the first reward flies in
	await get_tree().create_timer(0.3).timeout
	
	for i in range(reward_rows.size()):
		var row = reward_rows[i]
		var label: Label = row["label"]
		var icon: Sprite2D = row["icon"]
		var label_final_x: float = row["label_final_x"]
		var icon_final_x: float = row["icon_final_x"]
		
		# Animate both simultaneously — label from the right, icon from the left
		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		
		tween.tween_property(label, "position:x", label_final_x, 0.6)
		tween.tween_property(icon, "position:x", icon_final_x, 0.6)
		
		await tween.finished
		
		# If there's another reward after this one, wait 0.3 seconds
		if i < reward_rows.size() - 1:
			await get_tree().create_timer(0.3).timeout

# ============================================================
# COIN NAME FORMATTING
# ============================================================
# Converts e.g. "Gyarados Blue" → "Blue Gyarados Coin"

func format_coin_name(raw: String) -> String:
	var base    := raw.trim_suffix(".png")
	var words   := base.split(" ")
	var colours := ["red", "blue", "gold", "silver", "green", "black", "purple",
					"pink", "brown", "yellow", "orange", "white"]
	var colour     := ""
	var number     := ""
	var name_parts : Array = []
	var i := words.size() - 1
	if i >= 0 and words[i].is_valid_int():
		number = words[i]
		i -= 1
	if i >= 0 and words[i].to_lower() in colours:
		colour = words[i]
		i -= 1
	for j in range(i + 1):
		name_parts.append(words[j])
	var pieces : Array = []
	if colour != "":
		pieces.append(colour)
	pieces.append_array(name_parts)
	pieces.append("Coin")
	if number != "":
		pieces.append(number)
	return " ".join(pieces)

func capitalise_words(text: String) -> String:
	var words = text.split(" ")
	var result = []
	for word in words:
		if word.length() > 0:
			result.append(word.substr(0, 1).to_upper() + word.substr(1))
	return " ".join(result)

# ============================================================
# SCENE TRANSITION — BACK TO MAP
# ============================================================

func transition_back_to_map() -> void:
	print("DEBUG return path: ", GameState.return_map_scene_path)
	# Prevent multiple triggers
	transitioning = true
	click_enabled = false
	
	# Check if time should advance
	if battle_won:
		# IF YOU DEFEAT THE FIRST 4 OPPONENTS IN CELESTE HARBOUR ON DAY 1 MOVE TO EVENING 1
		if GameState.get_current_defeated() == 4 and GameState.get_time() == "Day" and GameState.get_date() == 1:
			GameState.advance_time("Evening")
			
		# IF YOU DEFEAT THE SECOND 4 OPPONENTS IN CELESTE HARBOUR ON EVENING 1 AND HAVE COLLECTED THE SHOP STARTER SET MOVE TO NIGHT 1
		if GameState.get_current_defeated() == 4 and GameState.get_time() == "Evening" and GameState.get_date() == 1 \
				and GameState.progress.get("player_collected_shop_starter_set", false):
			GameState.advance_time("Night")
				
	# Stop any win/loss jingle that may still be playing
	# SFX are played as children of SoundManagerScript, so stop and free them all
	for child in SoundManagerScript.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.queue_free()
	
	# Fade out to black
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	
	# Return to the map level the player came from
	var map_path = GameState.return_map_scene_path
	if map_path == "":
		map_path = "res://Scenes/Map_Scenes/World_Maps/World_Map_Base_Scene.tscn"
	
	SceneCache.change_scene(map_path)
