extends WorldObjectBase

# ============================================================
# NPC OBJECT SCRIPT
# ============================================================
# Gift NPCs are detected automatically: if gift_type != "" the
# NPC is treated as a gift NPC. No npc_type field needed.
# All NPCs (gift or text-only) use repeat_text for their
# second-and-beyond interaction text.
#
# Gift types:
#   "card"           - gift_value = comma-separated card IDs
#   "coin"           - gift_value = coin filename e.g. "Pikachu Gold 1"
#   "cash"           - gift_value = amount as string e.g. "250"
#   "energy_style"   - gift_value = style name e.g. "Base1"
#   "costume"        - gift_value = costume filename e.g. "lass.png"
#   "available_pack" - gift_value = pack name e.g. "base4"
#   "pack_of_cards"  - gift_value = pack set name e.g. "base1"
# ============================================================

var npc_name: String = ""
# Display name for message boxes. npc_name is the unique tracking key (it encodes
# the days/times this NPC appears, so gifts and met-flags stay per-instance) and is
# never shown to the player. friendly_name is what the message box header reads.
var friendly_name: String = ""
var npc_type: String = "text_only"   # kept for bubble icon: "text_only" | "shop"
var meet_text: String = ""
var repeat_text: String = ""
var gift_type: String = ""
var gift_value: String = ""

# Costume-gated interaction. When required_costume is set, the NPC shows a
# different greeting (costume_match_text) and hands over its gift ONLY while
# the player is wearing that costume sprite. Otherwise it acts as an ordinary
# text NPC (meet_text / repeat_text) and gives nothing.
var required_costume: String = ""
var costume_match_text: String = ""

func _ready():
	add_to_group("npcs")
	super._ready()

func _get_bubble_texture() -> Texture2D:
	if npc_type == "shop":
		return load("res://image_assets/misc/shop_talk.png")
	var already_interacted = has_gift_been_given() if is_gift_npc() else has_been_met()
	if already_interacted:
		return load("res://image_assets/misc/old_talk.png")
	else:
		return load("res://image_assets/misc/new_talk.png")

# ============================================================
# TRACKING
# ============================================================

func is_gift_npc() -> bool:
	return gift_type != ""

func has_gift_been_given() -> bool:
	return GameState.has_received_gift(npc_name)

func has_been_met() -> bool:
	return GameState.has_met_npc(npc_name)

func mark_as_met() -> void:
	GameState.mark_npc_met(npc_name)
