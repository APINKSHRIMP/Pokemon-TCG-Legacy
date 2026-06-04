extends WorldObjectBase

# ============================================================
# SHOPKEEPER SCRIPT
# ============================================================
# Extends WorldObjectBase for movement/bubble, then adds the
# shop state machine on top.
#
# Shop states (stored in GameState.progress["shop_state"]):
#   "initial"        - Day 1, first interaction, offer starter set
#   "awaiting_funds" - Day 1, player saw offer but had no cash
#   "restocking"     - Starter purchased, waiting for Day 2
#   "open"           - Normal shop, pack purchase available
#
# JSON fields used:
#   npc_type  : "shop"  (still used for bubble icon selection)
#   shop_id   : unique string key e.g. "card_mart"
#   meet_text : fallback/open state welcome text
# ============================================================

var npc_name: String = ""
var npc_type: String = "shop"
var meet_text: String = ""
var repeat_text: String = ""
var gift_type: String = ""
var gift_value: String = ""
var shop_id: String = "card_mart"

const SHOP_CONFIG_PATH = "res://NPC_and_Opponent_Data/Shop_Config/shops.json"
var _shop_config: Dictionary = {}

# Card Mart starter-set constants
const STARTER_SET_COST = 500
const SHOP_STARTER_CARDS = "base1-49, base1-49, base1-48, base1-48, base1-96, base1-95, base1-95, base1-94, base1-94, base1-93, base1-93, base1-91, base1-83, base1-83, base1-77, base1-65, base1-65, base1-63, base1-63, base1-59, base1-59, base1-58, base1-58, base1-69, base1-69, base1-54, base1-53, base1-53, base1-46, base1-46, base1-45, base1-45, base1-44, base1-44, base1-42, base1-36, base1-33, base1-34, base1-32, base1-30, base1-28, base1-28, base1-24, base1-19"
# PLACEHOLDER: Replace with actual 20 card IDs from two base1 boosters
const FREE_PACKS_DAY_2_CARDS = "base1_a,base1_b"

var _shop_state: String = "initial"

func _ready():
	add_to_group("npcs")
	player_block_distance = 70.0
	lock_facing = true
	super._ready()
	_load_shop_config()
	_shop_state = GameState.progress.get("shop_state", "initial")
	if _shop_config.get("always_open", false):
		_shop_state = "open"
	print("[Shopkeeper] Ready — shop_id=", shop_id, " state=", _shop_state,
		  " date=", GameState.get_date(), " cash=", GameState.get_cash())

func _load_shop_config():
	var file = FileAccess.open(SHOP_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[Shopkeeper] Cannot open shops.json")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_shop_config = parsed.get(shop_id, {})
	if _shop_config.is_empty():
		push_error("[Shopkeeper] No config found for shop_id: " + shop_id)

func _get_bubble_texture() -> Texture2D:
	return load("res://image_assets/misc/shop_talk.png")

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
			GameState.progress["shop_free_packs_given"] = true
			GameState.save_progress()
			MapManager.queue_pack_gift(["base1_a", "base1_c"])
			message = "Welcome back! I've restocked. Here are two free packs to get you started!"
			MapManager._show_message_with_ok(message)
		else:
			message = "Welcome back! The shop is open now."
			MapManager._show_message_with_ok(message)
	else:
		MapManager._show_message_with_ok(message)

func _handle_open_state():
	print("[Shopkeeper] Open state — ready to sell packs")
	if shop_id == "card_mart" and GameState.get_date() > 2 \
			and not GameState.progress.get("shop_new_stock_shown", false):
		GameState.progress["shop_new_stock_shown"] = true
		GameState.save_progress()
		meet_text = "I've just received the remaining shipment of packs so take a look at the new stock I have now!"

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
