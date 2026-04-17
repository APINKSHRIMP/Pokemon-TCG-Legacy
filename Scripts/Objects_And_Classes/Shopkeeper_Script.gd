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
#   text           : fallback/open state welcome text
#   repeat_text    : not used for shop NPCs
# ============================================================

# ── NPC base vars ──────────────────────────────────────────
var npc_name: String = ""
var overworld_sprite: String = ""
var npc_type: String = "shop"
var text: String = ""
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
const SHOP_STARTER_CARDS = "base1-96, base1-95, base1-95, base1-94, base1-94, base1-93, base1-93, base1-91, base1-83, base1-83, base1-77, base1-65, base1-65, base1-63, base1-63, base1-59, base1-59, base1-58, base1-58, base1-69, base1-69, base1-54, base1-53, base1-53, base1-46, base1-46, base1-45, base1-45, base1-44, base1-44, base1-42, base1-36, base1-33, base1-34, base1-32, base1-30, base1-28, base1-28, base1-24, base1-19"
# PLACEHOLDER: Replace with actual 20 card IDs from two base1 boosters
const FREE_PACKS_DAY_2_CARDS = "base1-1, base1-2, base1-3, base1-4, base1-5, base1-6, base1-7, base1-8, base1-9, base1-10, base1-11, base1-12, base1-13, base1-14, base1-15, base1-16, base1-17, base1-18, base1-19, base1-20"

# ── Shop state ────────────────────────────────────────────
var _shop_state: String = "initial"

# ============================================================
# READY
# ============================================================

func _ready():
	add_to_group("npcs")
	animated_sprite.sprite_frames = SpriteSheetLoader.load_sprite_frames(overworld_sprite)
	animated_sprite.scale = Vector2(1, 1)
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
	# Shop NPCs always show shop_talk bubble
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
# NPC TRACKING (needed by MapManager)
# ============================================================

func has_gift_been_given() -> bool:
	return GameState.has_received_gift(npc_name)

func has_been_met() -> bool:
	return GameState.has_met_npc(npc_name)

func mark_as_met() -> void:
	GameState.mark_npc_met(npc_name)

# ============================================================
# SHOP STATE MACHINE — PUBLIC ENTRY POINT
# ============================================================
# Called by MapManager._on_player_npc_interact() via shop_callback.
# Returns true  = we handled it fully (MapManager does nothing more).
# Returns false = let MapManager open the default pack purchase UI.

func on_interact() -> bool:
	_shop_state = GameState.progress.get("shop_state", "initial")
	print("[Shopkeeper] on_interact — state=", _shop_state,
		  " date=", GameState.get_date(), " cash=", GameState.get_cash())
	match _shop_state:
		"initial":
			_handle_initial()
			return true
		"awaiting_funds":
			_handle_awaiting_funds()
			return true
		"restocking":
			_handle_restocking()
			return true
		"open":
			_handle_open()
			return false  # MapManager takes over → Pack_Purchase scene
		_:
			push_error("[Shopkeeper] Unknown state: " + _shop_state)
			return false

# ============================================================
# STATE HANDLERS
# ============================================================

func _handle_initial():
	if GameState.get_cash() < STARTER_SET_COST:
		MapManager._show_message_with_ok(
			"Oh a new customer at just the right time! The Mayor hit me with a genius new tariff so I can't afford my import of stock, so I'm discounting this collection of cards you can have for just $"
			+ str(STARTER_SET_COST)
			+ ". If you come back with the cash you can get a great deal but come back quick so you don't miss out!"
		)
		_set_state("awaiting_funds")
	else:
		MapManager._show_message_with_choices(
			"Do you want this huge bargain collection of cards for $"
			+ str(STARTER_SET_COST)
			+ "? It's a GREAT deal, I'm selling this at a huge loss. I have an order of packs waiting delivery... as soon as I can pay off that stupid.. uh, I mean, genius tariff. (You'd be doing me a huge favour here kid)"
		)
		_connect_choice_handlers("_on_starter_yes", "_on_starter_no")

func _handle_awaiting_funds():
	if GameState.get_cash() < STARTER_SET_COST:
		MapManager._show_message_with_ok(
			"You still don't have enough for the starter set. Come back when you've got $"
			+ str(STARTER_SET_COST) + ". I'm sure you can earn it."
		)
	else:
		MapManager._show_message_with_choices(
			"Ah, you've got enough now! Do you want to buy the starter set for $"
			+ str(STARTER_SET_COST) + "?"
		)
		_connect_choice_handlers("_on_starter_yes", "_on_starter_no")

func _handle_restocking():
	var free_packs_given = GameState.progress.get("shop_free_packs_given", false)
	if GameState.get_date() >= 2 and not free_packs_given:
		_give_free_packs()
	else:
		MapManager._show_message_with_ok(
			"Thanks for helping me out here, I've used your additional funds to pay off the remaining balance on the import so come back in the morning and I'll have my full stock back in. I'll even throw in a free pack or two just for you for helping me out!"
		)

func _handle_open():
	MapManager._show_message_with_ok("Welcome! Would you like to browse the shop?")

# ============================================================
# STARTER SET PURCHASE
# ============================================================

func _on_starter_yes():
	_disconnect_choice_handlers()
	GameState.add_cash(-STARTER_SET_COST)
	GameState.progress["player_collected_shop_starter_set"] = true
	GameState.give_cards(SHOP_STARTER_CARDS)
	GameState.save_progress()
	_set_state("restocking")

	# Notify Card_Mart to remove the visual Starter_Set node
	var map = get_tree().current_scene
	if map.has_method("_remove_starter_set"):
		map._remove_starter_set()

	# Advance to Night if player has already beaten 4 opponents this Evening
	if GameState.get_current_defeated() == 4 and GameState.get_time() == "Evening" and GameState.get_date() == 1:
		GameState.advance_time("Night")

	MapManager._hide_message()
	MapManager._show_message_with_ok(
		"Here you go, all yours. There was some good stuff in there if you've not collected a lot already so you might want to add those new cards to your deck. (Press the escape key and then go to Cards & Deck to amend your deck)"
	)

func _on_starter_no():
	_disconnect_choice_handlers()
	MapManager._on_no_pressed()

# ============================================================
# DAY 2 FREE PACKS
# ============================================================

func _give_free_packs():
	GameState.give_cards(FREE_PACKS_DAY_2_CARDS)
	GameState.progress["shop_free_packs_given"] = true
	GameState.save_progress()
	_set_state("open")
	MapManager._show_message_with_ok(
		"Welcome back! As promised, here are a couple of free packs to say thank you for helping me out yesterday. My full stock is in now so feel free to browse and buy more!"
	)

# ============================================================
# STATE HELPER
# ============================================================

func _set_state(new_state: String):
	_shop_state = new_state
	GameState.progress["shop_state"] = new_state
	GameState.save_progress()
	print("[Shopkeeper] State → ", new_state)

# ============================================================
# YES/NO BUTTON WIRING
# ============================================================

func _connect_choice_handlers(yes_func: String, no_func: String):
	# Disconnect MapManager defaults
	if MapManager.yes_button.pressed.is_connected(MapManager._on_yes_pressed):
		MapManager.yes_button.pressed.disconnect(MapManager._on_yes_pressed)
	if MapManager.no_button.pressed.is_connected(MapManager._on_no_pressed):
		MapManager.no_button.pressed.disconnect(MapManager._on_no_pressed)
	# Connect ours (guard against double-connect)
	if not MapManager.yes_button.pressed.is_connected(Callable(self, yes_func)):
		MapManager.yes_button.pressed.connect(Callable(self, yes_func))
	if not MapManager.no_button.pressed.is_connected(Callable(self, no_func)):
		MapManager.no_button.pressed.connect(Callable(self, no_func))

func _disconnect_choice_handlers():
	for fn in ["_on_starter_yes", "_on_starter_no"]:
		var c = Callable(self, fn)
		if MapManager.yes_button.pressed.is_connected(c):
			MapManager.yes_button.pressed.disconnect(c)
		if MapManager.no_button.pressed.is_connected(c):
			MapManager.no_button.pressed.disconnect(c)
	# Restore MapManager defaults
	if not MapManager.yes_button.pressed.is_connected(MapManager._on_yes_pressed):
		MapManager.yes_button.pressed.connect(MapManager._on_yes_pressed)
	if not MapManager.no_button.pressed.is_connected(MapManager._on_no_pressed):
		MapManager.no_button.pressed.connect(MapManager._on_no_pressed)

func _exit_tree():
	_disconnect_choice_handlers()

# ============================================================
# MOVEMENT (identical to NPC_Object_Script)
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
