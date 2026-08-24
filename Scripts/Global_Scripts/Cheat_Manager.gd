class_name CheatManager
extends RefCounted

# Card lists mirrored from Player_House_Upstairs.gd and Shopkeeper_Script.gd.
# Update these if the source constants ever change.
# ISSUE #130: mirrors Player_House_Upstairs.STARTER_BOX_CARDS exactly -- see the note there.
const _STARTER_BOX_CARDS := "base1-27, base1-27, base1-47, base1-47, base1-47, base1-47, base1-48, base1-48, base1-48, base1-48, base1-52, base1-52, base1-52, base1-52, base1-59, base1-59, base1-61, base1-61, base1-61, base1-61, base1-65, base1-65, base1-65, base1-65, base1-67, base1-67, base1-90, base1-90, base1-91, base1-91, base1-94, base1-94"
const _SHOP_STARTER_CARDS  := "base1-49, base1-49, base1-48, base1-48, base1-96, base1-95, base1-95, base1-93, base1-93, base1-91, base1-83, base1-83, base1-77, base1-65, base1-65, base1-63, base1-63, base1-59, base1-59, base1-58, base1-58, base1-69, base1-69, base1-54, base1-53, base1-53, base1-46, base1-46, base1-45, base1-45, base1-44, base1-44, base1-43, base1-43, base1-42, base1-36, base1-33, base1-34, base1-32, base1-30, base1-28, base1-28, base1-24, base1-19"

const _CHEAT_LABELS := {
	"CHT.All_Cards_1":      "All Base/Gym/Promo cards cheat activated",
	"CHT.All_Cards_2":      "All Neo/e-Card cards cheat activated",
	"CHT.All_Cards_3":      "All EX Series 1 cards cheat activated",
	"CHT.All_Cards_4":      "All EX Series 2/POP cards cheat activated",
	"CHT.Gimme_Cash":       "Max cash cheat activated",
	"CHT.Add_Starter_Set":  "Starter set added",
	"CHT.Add_Shop_Set":     "Shop set added",
	"CHT.Remove_All_Cards": "Remove all cards cheat activated",
	# ISSUE #134: cosmetic collections. "All" means every file the matching grid screen lists —
	# the universes come from GameState so these can never disagree with the trainer card counters.
	"CHT.All_Coins":        "All coins cheat activated",
	"CHT.All_Costumes":     "All costumes cheat activated",
	"CHT.All_Sleeves":      "All sleeves cheat activated",
	# ISSUE #155: every basic-Energy printing the deck builder's style picker can offer.
	"CHT.All_Energy_Styles": "All energy styles cheat activated",
}

# ISSUE #99: the four groups between them must cover EVERY set in Card_Set_Data/ — the promo sets
# (basep, si1, np) and the five POP sets were missing entirely, so no cheat could ever unlock them.
# Each promo set is grouped with the era it belongs to.
const _SET_GROUPS := {
	"CHT.All_Cards_1": ["base1", "base2", "base3", "base5", "gym1", "gym2", "basep", "si1"],
	"CHT.All_Cards_2": ["neo1", "neo2", "neo3", "neo4", "ecard1", "ecard2", "ecard3", "np"],
	"CHT.All_Cards_3": ["ex1", "ex2", "ex3", "ex4", "ex5", "ex6", "ex7", "ex8"],
	"CHT.All_Cards_4": ["ex9", "ex10", "ex11", "ex12", "ex13", "ex14", "ex15", "ex16",
						"pop1", "pop2", "pop3", "pop4", "pop5"],
}

# Returns the display message if `name` is a recognised cheat code and the
# cheat was applied, or an empty string if it is not a cheat code.
#
# ISSUE #131 FIX: matching is CASE-INSENSITIVE. The codes are typed into the trainer-card name
# box, an ordinary free-text field with no hint that "CHT.All_Cards_1" has to be capitalised
# exactly like that -- so "cht.all_cards_1" and "CHT.ALL_CARDS_1" now work too. The canonical
# spelling from _CHEAT_LABELS is what gets applied and reported back, so the confirmation popup
# reads identically however it was typed.
static func check_and_apply(player_name: String) -> String:
	var typed := player_name.strip_edges().to_lower()
	if typed == "":
		return ""
	for code in _CHEAT_LABELS:
		if String(code).to_lower() == typed:
			_apply(code)
			return _CHEAT_LABELS[code]
	return ""


static func _apply(code: String) -> void:
	match code:
		"CHT.All_Cards_1", "CHT.All_Cards_2", "CHT.All_Cards_3", "CHT.All_Cards_4":
			for set_id in _SET_GROUPS[code]:
				_set_cards_in_set(set_id, 99)
		"CHT.Gimme_Cash":
			var current := GameState.get_cash()
			GameState.add_cash(99999 - current)
		"CHT.Add_Starter_Set":
			GameState.give_cards(_STARTER_BOX_CARDS)
		"CHT.Add_Shop_Set":
			GameState.give_cards(_SHOP_STARTER_CARDS)
		"CHT.Remove_All_Cards":
			_zero_all_cards()
		"CHT.All_Coins":
			# Every coin in Image_Assets/Coins except the "Back Basic" placeholder.
			var coins := GameState.get_coin_universe().keys()
			var new_coins := GameState.add_coins_to_collection(coins)
		"CHT.All_Costumes":
			# Every in-battle trainer sprite — the same folder the costume grid lists.
			var costumes := GameState.get_costume_universe().keys()
			var new_costumes := GameState.add_costumes_to_collection(costumes)
		"CHT.All_Energy_Styles":
			# ISSUE #155: the universe comes from GameState.ENERGY_STYLES, the same table the deck
			# builder's picker is built from, so this can never grant a style the picker won't show.
			var styles := GameState.get_energy_style_universe()
			var new_styles := GameState.add_energy_styles_to_collection(styles)
			print("ISSUE #155 FIX ACTIVE: CHT.All_Energy_Styles granted ", new_styles,
				" new styles of ", styles.size(), " total")
		"CHT.All_Sleeves":
			# include_defaults = true: the sleeve grid shows the "1_Default*" backs, so "all" owns them.
			var sleeves := GameState.get_sleeve_universe(true).keys()
			var new_sleeves := GameState.add_sleeves_to_collection(sleeves)


static func _set_cards_in_set(set_id: String, count: int) -> void:
	var path := GameState.OWNED_CARDS_FOLDER + set_id + "_player_owned_cards.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary or not data.has("owned_cards"):
		return
	for entry in data["owned_cards"]:
		entry["owned"] = count
	if count > 0:
		data["set_unlocked"] = true
	var wf := FileAccess.open(path, FileAccess.WRITE)
	if wf == null:
		return
	wf.store_string(JSON.stringify(data, "\t"))
	wf.close()
	if count > 0:
		_mark_pack_unlocked(set_id)


# ISSUE #133 FIX: "Card Sets Unlocked" on the trainer card counts progress["packs_unlocked"], NOT
# the per-set `set_unlocked` flag the card cheats were writing -- so a cheat could hand the player
# every card in a set (pushing "Sets Completed" up) while "Card Sets Unlocked" never moved. The two
# stores mean different things (owned_cards.set_unlocked = "the deck builder may browse this set";
# packs_unlocked = "this set's pack is buyable in the shop"), but granting a whole set implies
# both, so the cheat now writes both. Every other unlock path already does this by hand -- see
# Player_House_Upstairs._on_box_step3() and MapManager's pack-gift branch.
#
# Deliberately one-way: CHT.Remove_All_Cards zeroes the counts but does not re-lock the packs,
# matching the existing behaviour of never clearing `set_unlocked` on the way down either.
static func _mark_pack_unlocked(set_id: String) -> void:
	if not GameState.progress.has("packs_unlocked"):
		GameState.progress["packs_unlocked"] = []
	var packs: Array = GameState.progress["packs_unlocked"]
	if set_id in packs:
		return
	packs.append(set_id)
	GameState.progress["packs_unlocked"] = packs
	GameState.save_progress()


static func _zero_all_cards() -> void:
	var dir := DirAccess.open(GameState.OWNED_CARDS_FOLDER)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with("_player_owned_cards.json"):
			var set_id := fname.replace("_player_owned_cards.json", "")
			_set_cards_in_set(set_id, 0)
		fname = dir.get_next()
	dir.list_dir_end()
