extends CharacterBody2D

# ============================================================
# SHOPKEEPER SCRIPT
# ============================================================
# Replaces NPC_Object_Script entirely for shop-type NPCs.
# Contains all NPC movement/bubble logic PLUS the shop
# state machine. Attach this to Shopkeeper_Object_Scene.tscn
# instead of NPC_Object_Script.gd.
#
# Shop states (stored in GameState.progress["shop_state"]):
#   "initial"        - Day 1, first interaction, offer starter set
#   "awaiting_funds" - Day 1, player saw offer but had no cash
#   "restocking"     - Starter purchased, waiting for Day 2
#   "open"           - Normal shop, pack purchase available
#
# JSON fields used (Card_Mart_NPCs.json shopkeeper entry):
#   npc_type       : "shop"  (still used for bubble icon selection)
#   shop_id        : unique string key e.g. "card_mart"
#   meet_text      : fallback/open state welcome text
#   repeat_text    : not used for shop NPCs
# ============================================================

# ── NPC base vars ──────────────────────────────────────────
var npc_name: String = ""
var sprite: String = ""
var npc_type: String = "shop"
var meet_text: String = ""
var repeat_text: String = ""
var gift_type: String = ""
var gift_value: String = ""

# ── Shop-specific vars ────────────────────────────────────
var shop_id: String = "card_mart"

# ── Movement config ────────────────────────────────────────
var movement_pattern: String = "idle_down"
var patrol_distance: float = 100.0
var patrol_speed: float = 60.0
var patrol_axis: String = "horizontal"
var wander_radius: float = 200.0

# ── Internal movement state ────────────────────────────────
var patrol_direction_vec: Vector2 = Vector2.ZERO
var patrol_step: int = 0
var distance_walked: float = 0.0
var current_facing: String = "down"
var _restore_timer: SceneTreeTimer = null

var _wander_origin: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _is_wandering: bool = false

# ── Bubble ─────────────────────────────────────────────────
var _bubble_sprite: Sprite2D = null
const BUBBLE_Y_OFFSET: float = -19.0
const BUBBLE_Z_INDEX: int = 100

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var direction_timer: Timer = $DirectionTimer

const DIRECTIONS  = ["up", "down", "left", "right"]
const DIR_VECTORS = {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
const SQUARE_ORDER = ["down", "right", "up", "left"]

# ── Card Mart constants ────────────────────────────────────
const STARTER_SET_COST = 500
const SHOP_STARTER_CARDS = "base1-49, base1-49, base1-48, base1-48, base1-96, base1-95, base1-95, base1-94, base1-94, base1-93, base1-93, base1-91, base1-83, base1-83, base1-77, base1-65, base1-65, base1-63, base1-63, base1-59, base1-59, base1-58, base1-58, base1-69, base1-69, base1-54, base1-53, base1-53, base1-46, base1-46, base1-45, base1-45, base1-44, base1-44, base1-42, base1-36, base1-33, base1-34, base1-32, base1-30, base1-28, base1-28, base1-24, base1-19"
# PLACEHOLDER: Replace with actual 20 card IDs from two base1 boosters
const FREE_PACKS_DAY_2_CARDS = "base1-1, base1-2, base1-3, base1-4, base1-5, base1-6, base1-7, base1-8, base1-9, base1-10, base1-11, base1-12, base1-13, base1-14, base1-15, base1-16, base1-17, base1-18, base1-19, base1-20"

# ── Shop state ────────────────────────────────────────────
var _shop_state: String = "initial"

# ============================================================
# READY
# ============================================================

func _ready():
	add_to_group("npcs")
	animated_sprite.sprite_frames = SpriteSheetLoader.load_sprite_frames(sprite)
	animated_sprite.scale = Vector2(0.5, 0.5)
	animated_sprite.play("idle_down")
	_setup_bubble()
	_init_movement()
	_shop_state = GameState.progress.get("shop_state", "initial")
	print("[Shopkeeper] Ready — shop_id=", shop_id, " state=", _shop_state,
		  " date=", GameState.get_date(), " cash=", GameState.get_cash())

func _init_movement():
	match movement_pattern:
		"idle_random":
			direction_timer.wait_time = randf_range(1.0, 4.0)
			direction_timer.timeout.connect(_on_direction_timer_timeout)
			direction_timer.start()
		"idle_cycle":
			animated_sprite.play("walk_down")
		"idle_left":   animated_sprite.play("idle_left")
		"idle_right":  animated_sprite.play("idle_right")
		"idle_up":     animated_sprite.play("idle_up")
		"idle_down":   animated_sprite.play("idle_down")
		"patrol_line":
			distance_walked = 0.0
			if patrol_axis == "horizontal":
				patrol_direction_vec = Vector2.RIGHT
				current_facing = "right"
			else:
				patrol_direction_vec = Vector2.DOWN
				current_facing = "down"
		"patrol_square":
			distance_walked = 0.0
			patrol_step = 0
			patrol_direction_vec = DIR_VECTORS[SQUARE_ORDER[0]]
			current_facing = SQUARE_ORDER[0]
		"random_wander":
			_wander_origin = position
			direction_timer.wait_time = randf_range(1.0, 4.0)
			direction_timer.timeout.connect(_on_direction_timer_timeout)
			direction_timer.start()

# ============================================================
# BUBBLE
# ============================================================

func _setup_bubble():
	_bubble_sprite = Sprite2D.new()
	_bubble_sprite.position = Vector2(0, BUBBLE_Y_OFFSET)
	_bubble_sprite.z_index = BUBBLE_Z_INDEX
	_bubble_sprite.visible = false
	add_child(_bubble_sprite)

func _get_bubble_texture() -> Texture2D:
	return load("res://image_assets/misc/shop_talk.png")

func show_bubble():
	if _bubble_sprite == null:
		return
	_bubble_sprite.texture = _get_bubble_texture()
	_bubble_sprite.visible = true

func hide_bubble():
	if _bubble_sprite == null:
		return
	_bubble_sprite.visible = false

func refresh_bubble():
	if _bubble_sprite != null and _bubble_sprite.visible:
		_bubble_sprite.texture = _get_bubble_texture()

# ============================================================
# MOVEMENT
# ============================================================

func _is_player_blocking() -> bool:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	return position.distance_to(players[0].position) < 70.0

func _physics_process(delta):
	match movement_pattern:
		"patrol_line":
			if _is_player_blocking():
				velocity = Vector2.ZERO
				animated_sprite.play("idle_" + current_facing)
				return
			_process_patrol_line(delta)
		"patrol_square":
			if _is_player_blocking():
				velocity = Vector2.ZERO
				animated_sprite.play("idle_" + current_facing)
				return
			_process_patrol_square(delta)
		"random_wander":
			if _is_player_blocking():
				velocity = Vector2.ZERO
				animated_sprite.play("idle_" + current_facing)
				return
			_process_random_wander(delta)
		_:
			velocity = Vector2.ZERO
			return
	move_and_slide()

func _process_patrol_line(delta):
	velocity = patrol_direction_vec * patrol_speed
	distance_walked += patrol_speed * delta
	animated_sprite.play("walk_" + current_facing)
	if distance_walked >= patrol_distance:
		distance_walked = 0.0
		patrol_direction_vec = -patrol_direction_vec
		if patrol_direction_vec.x > 0:   current_facing = "right"
		elif patrol_direction_vec.x < 0: current_facing = "left"
		elif patrol_direction_vec.y > 0: current_facing = "down"
		else:                            current_facing = "up"

func _process_patrol_square(delta):
	velocity = patrol_direction_vec * patrol_speed
	distance_walked += patrol_speed * delta
	animated_sprite.play("walk_" + current_facing)
	if distance_walked >= patrol_distance:
		distance_walked = 0.0
		patrol_step = (patrol_step + 1) % 4
		var dir_name = SQUARE_ORDER[patrol_step]
		patrol_direction_vec = DIR_VECTORS[dir_name]
		current_facing = dir_name

func _process_random_wander(delta):
	if not _is_wandering:
		velocity = Vector2.ZERO
		return
	var to_target = _wander_target - position
	if to_target.length() < 2.0:
		position = _wander_target
		velocity = Vector2.ZERO
		_is_wandering = false
		animated_sprite.play("idle_" + current_facing)
		return
	var move_dir = to_target.normalized()
	velocity = move_dir * patrol_speed
	if abs(move_dir.x) > abs(move_dir.y):
		current_facing = "right" if move_dir.x > 0 else "left"
	else:
		current_facing = "down" if move_dir.y > 0 else "up"
	animated_sprite.play("walk_" + current_facing)

func _pick_wander_target():
	var step = randf_range(30.0, 80.0)
	var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	dirs.shuffle()
	for dir in dirs:
		var candidate = position + dir * step
		if candidate.distance_to(_wander_origin) <= wander_radius:
			_wander_target = candidate
			_is_wandering = true
			return
	var to_origin = _wander_origin - position
	_wander_target = position + (to_origin.normalized() if to_origin.length() > 1.0 else Vector2.ZERO) * step
	_is_wandering = true

func _on_direction_timer_timeout():
	match movement_pattern:
		"idle_random":
			var new_dir = DIRECTIONS[randi() % DIRECTIONS.size()]
			current_facing = new_dir
			animated_sprite.play("idle_" + new_dir)
		"random_wander":
			if not _is_wandering:
				_pick_wander_target()
	direction_timer.wait_time = randf_range(2.0, 5.0)
	direction_timer.start()

func pause_and_face(target_position: Vector2):
	velocity = Vector2.ZERO
	set_physics_process(false)
	direction_timer.stop()
	_is_wandering = false
	if _restore_timer != null and is_instance_valid(_restore_timer):
		_restore_timer.timeout.disconnect(_on_restore_facing)
		_restore_timer = null
	var diff = target_position - position
	if abs(diff.x) > abs(diff.y):
		current_facing = "right" if diff.x > 0 else "left"
	else:
		current_facing = "down" if diff.y > 0 else "up"
	animated_sprite.play("idle_" + current_facing)

func resume_movement():
	set_physics_process(true)
	match movement_pattern:
		"idle_random":
			direction_timer.wait_time = randf_range(2.0, 5.0)
			direction_timer.start()
		"idle_cycle":
			animated_sprite.play("walk_down")
		"patrol_line", "patrol_square":
			if patrol_direction_vec.x > 0:   current_facing = "right"
			elif patrol_direction_vec.x < 0: current_facing = "left"
			elif patrol_direction_vec.y > 0: current_facing = "down"
			else:                            current_facing = "up"
		"random_wander":
			direction_timer.wait_time = randf_range(2.0, 5.0)
			direction_timer.start()
		"idle_down", "idle_up", "idle_left", "idle_right":
			_restore_timer = get_tree().create_timer(1.0)
			_restore_timer.timeout.connect(_on_restore_facing)

func _on_restore_facing():
	_restore_timer = null
	if not is_instance_valid(self):
		return
	match movement_pattern:
		"idle_down":  animated_sprite.play("idle_down");  current_facing = "down"
		"idle_up":    animated_sprite.play("idle_up");    current_facing = "up"
		"idle_left":  animated_sprite.play("idle_left");  current_facing = "left"
		"idle_right": animated_sprite.play("idle_right"); current_facing = "right"

# ============================================================
# SHOP STATE MACHINE
# ============================================================

func on_interact() -> bool:
	print("[Shopkeeper] on_interact() — state=", _shop_state)
	match _shop_state:
		"initial":
			_handle_initial_state()
			return true
		"awaiting_funds":
			_handle_awaiting_funds_state()
			return true
		"restocking":
			_handle_restocking_state()
			return true
		"open":
			_handle_open_state()
			return false
		_:
			print("[Shopkeeper] Unknown state: ", _shop_state)
			_shop_state = "open"
			return false

func _handle_initial_state():
	print("[Shopkeeper] Initial state — offering starter set for $", STARTER_SET_COST)
	var message = "Welcome to Card Mart! I've got a special starter pack just for you.\n\nIt contains a selection of cards to get you started.\n\nCost: $" + str(STARTER_SET_COST)
	var cash = GameState.get_cash()
	
	if cash >= STARTER_SET_COST:
		print("[Shopkeeper] Player can afford starter set")
		MapManager._show_message_with_choices(message)
	else:
		print("[Shopkeeper] Player cannot afford starter set (have $" + str(cash) + ")")
		MapManager._show_message_with_ok(message + "\n\nCome back when you've got more cash.")
		_shop_state = "awaiting_funds"
		GameState.progress["shop_state"] = _shop_state
		GameState.save_progress()

func _handle_awaiting_funds_state():
	print("[Shopkeeper] Awaiting funds state")
	var message = "Got your cash yet?"
	var cash = GameState.get_cash()
	
	if cash >= STARTER_SET_COST:
		print("[Shopkeeper] Player now has enough cash")
		MapManager._show_message_with_choices(message + "\n\nReady to buy the starter set?")
	else:
		print("[Shopkeeper] Player still cannot afford it")
		MapManager._show_message_with_ok(message)

func _handle_restocking_state():
	print("[Shopkeeper] Restocking state (Date: " + str(GameState.get_date()) + ")")
	var message = "Come back tomorrow with more cash!"
	if GameState.get_date() > 1:
		print("[Shopkeeper] Day 2 reached — transitioning to open")
		_shop_state = "open"
		GameState.progress["shop_state"] = _shop_state
		if not GameState.progress.get("shop_free_packs_given", false):
			print("[Shopkeeper] Giving free packs")
			GameState.give_cards(FREE_PACKS_DAY_2_CARDS)
			GameState.progress["shop_free_packs_given"] = true
			GameState.save_progress()
			message = "Welcome back! I've restocked. Here are some free packs to get started properly."
			MapManager._show_message_with_ok(message)
		else:
			message = "Welcome back! The shop is open now."
			MapManager._show_message_with_ok(message)
	else:
		MapManager._show_message_with_ok(message)

func _handle_open_state():
	print("[Shopkeeper] Open state — ready to sell packs")

func _finish_starter_purchase():
	print("[Shopkeeper] Processing starter set purchase...")
	var cash = GameState.get_cash()
	if cash < STARTER_SET_COST:
		print("[Shopkeeper] Purchase failed: insufficient cash")
		return
	
	GameState.add_cash(-STARTER_SET_COST)
	GameState.give_cards(SHOP_STARTER_CARDS)
	GameState.progress["player_collected_shop_starter_set"] = true
	_shop_state = "restocking"
	GameState.progress["shop_state"] = _shop_state
	GameState.save_progress()
	print("[Shopkeeper] Starter set purchased. Transitioned to restocking state")
	MapManager._show_message_with_ok("Thanks for your purchase! Come back tomorrow for more stock.")
