extends WorldObjectBase

# ============================================================
# SHOPKEEPER SCRIPT
# ============================================================
# Extends WorldObjectBase for movement/bubble, then adds the Card Mart's opening
# week on top. Every other shop (always_open in shops.json) goes straight to its
# Yes/No with meet_text.
#
# The Card Mart's stock follows the date (Pack_Purchase_Script._load_player_data())
# and so does what the shopkeeper says -- the first time the player talks to him on
# that day, then a shorter line after:
#   Day 1    out of stock, nothing to sell
#   Day 2    Base Set only, Jungle and Fossil delayed
#   Day 3+   everything
#
# JSON fields used:
#   npc_type  : "shop"  (still used for bubble icon selection)
#   shop_id   : unique string key e.g. "card_mart"
#   meet_text : the greeting for every shop but the Card Mart
# ============================================================

var npc_name: String = ""
# Display name for message boxes — see NPC_Object_Script for why this is separate
# from npc_name (which is the unique tracking key).
var friendly_name: String = ""
# Message box colour theme — see NPC_Object_Script. Empty falls back to the default theme.
var message_colour: String = ""
var npc_type: String = "shop"
var meet_text: String = ""
var repeat_text: String = ""
var gift_type: String = ""
var gift_value: String = ""
var shop_id: String = "card_mart"

const SHOP_CONFIG_PATH = "res://NPC_and_Opponent_Data/Shop_Config/shops.json"
var _shop_config: Dictionary = {}

# ── The Card Mart's opening week — TWEAKABLE text ───────────────────────────
const MART_DAY_1_FIRST := "Hello! I'm so sorry but I'm completely out of stock already! I've been having trouble keeping up with demand but I have a big shipment due tomorrow so come back and I'll have plenty to buy then!"
const MART_DAY_1_AGAIN := "Hello! Come back tomorrow and I'll have plenty of stock in!"
const MART_DAY_2_FIRST := "Hello! I've still had delays on getting Jungle and Fossil packs in, but I've got plenty of base packs in so I'm selling them for cheaper than Jungle and Fossil! Are you looking to buy some?"
const MART_DAY_2_AGAIN := "Hello! Are you looking to buy some base packs?"
const MART_DAY_3_FIRST := "Hello! I've managed to get plenty of Jungle and Fossil packs in, but I've kept base packs priced slightly cheaper! Are you looking to buy some?"
const MART_DAY_3_AGAIN := "Hello! Are you looking to buy some packs? I've got plenty in stock!"
# The dates on which the player has already heard that day's first line.
const GREETED_KEY := "card_mart_greeted_days"

func _ready():
	add_to_group("npcs")
	player_block_distance = 70.0
	lock_facing = true
	super._ready()
	_load_shop_config()

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
	return load("res://Image_Assets/Icons/Message_Icons/shop_talk.png")

# ============================================================
# GREETING
# ============================================================

## True when MapManager should NOT go on to the shop's Yes/No (the shop is shut).
## Otherwise meet_text is set to today's greeting and MapManager asks the question.
func on_interact() -> bool:
	if _shop_config.get("always_open", false):
		return false
	var date := GameState.get_date()
	var greeted: Array = GameState.progress.get(GREETED_KEY, [])
	var first: bool = date not in greeted
	if first:
		greeted.append(date)
		GameState.progress[GREETED_KEY] = greeted
		GameState.save_progress()
	if date <= 1:
		MapManager._show_message_with_ok(MART_DAY_1_FIRST if first else MART_DAY_1_AGAIN)
		return true
	if date == 2:
		meet_text = MART_DAY_2_FIRST if first else MART_DAY_2_AGAIN
	else:
		meet_text = MART_DAY_3_FIRST if first else MART_DAY_3_AGAIN
	return false
