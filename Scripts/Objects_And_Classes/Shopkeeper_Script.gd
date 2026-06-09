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
	var message = "Hello there! I've not seen you before, I assume you're new in town? Sadly thanks to the new tariffs introduced, I can't afford the import on my regular stock shipment this week and I'm all out of packs. So I've put all of my spare stock into this box here and I'm selling it for super cheap to make just enough to pay the import charge. I'm only looking for $" + str(STARTER_SET_COST)+" for it. It's an amazing bargain I promise you."
	var cash = GameState.get_cash()
	if cash >= STARTER_SET_COST:
		print("[Shopkeeper] Player can afford starter set")
		MapManager._pending_confirm_yes = _finish_starter_purchase
		MapManager._show_message_with_choices(message)
	else:
		print("[Shopkeeper] Player cannot afford starter set (have $" + str(cash) + ")")
		MapManager._show_message_with_ok(message + " If you want it you better hurry back with the funds soon, otherwise somebody might snap up this bargain first!")
		_shop_state = "awaiting_funds"
		GameState.progress["shop_state"] = _shop_state
		GameState.save_progress()

func _handle_awaiting_funds_state():
	print("[Shopkeeper] Awaiting funds state")
	var cash = GameState.get_cash()
	if cash >= STARTER_SET_COST:
		var message = "Hello again! You're in luck, nobody has taken this off me yet so you still have a chance to grab this bargain before someone else does! It contains a load of good cards that will be really useful to you. Would you like to buy it? It's a once in a lifetime offer, you won't get the chance again!"
		print("[Shopkeeper] Player now has enough cash")
		MapManager._pending_confirm_yes = _finish_starter_purchase
		MapManager._show_message_with_choices(message)
	else:
		var message = "I won't be able to afford the import on my regular packs until somebody takes this, so until then I won't have anything else to sell I'm afraid. I promise this is an absolute steal, I'm selling it all at a great loss but I have no other choice. If you're just starting out in the TCG it'll help you massively. As a bonus, if you do take this off my hands today I'll throw in a free pack for you when you return."
		print("[Shopkeeper] Player still cannot afford it")
		MapManager._show_message_with_ok(message)

func _handle_restocking_state():
	print("[Shopkeeper] Restocking state (Date: " + str(GameState.get_date()) + ")")
	var message = "Thanks again, I should have the shipment of stock in by tomorrow, so come back in the morning and I'll have plenty of packs for you then."
	if GameState.get_date() > 1:
		print("[Shopkeeper] Day 2 reached — transitioning to open")
		_shop_state = "open"
		GameState.progress["shop_state"] = _shop_state
		if not GameState.progress.get("shop_free_packs_given", false):
			print("[Shopkeeper] Giving free packs")
			GameState.progress["shop_free_packs_given"] = true
			GameState.save_progress()
			MapManager.queue_pack_gift(["base1_a", "base1_c"])
			message = "Welcome back! Good to see you again. As expected my stocks arrived today so I have plenty of packs now. However... they only sent me Base packs. As a thanks, here are two free packs to get you started! I should get my other sets in tomorrow but I'll give you a discount on Base set packs as an apology."
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
		meet_text = "I've just received the remaining shipment of packs. I now have Jungle and Fossil packs in for sale so take a look."

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
	var scene = get_tree().current_scene
	if scene.has_method("_remove_starter_set"):
		scene._remove_starter_set()
	if scene.has_method("_update_cash_label"):
		scene._update_cash_label()
	print("[Shopkeeper] Starter set purchased. Transitioned to restocking state")
	MapManager._show_message_with_ok("Thanks for your purchase! I'll get the order in right away for my usual shipment now so they'll be here for tomorrow morning. I'll throw you a couple packs in for free as a thank you when you come back! ")
