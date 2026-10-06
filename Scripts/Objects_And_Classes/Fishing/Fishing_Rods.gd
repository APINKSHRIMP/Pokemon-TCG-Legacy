class_name FishingRods
extends RefCounted

## Every fishing rod and fishing permit, and what owning them does.
##
## RODS are items in progress["items"] (GameState.add_item_to_collection), named by
## their art in Image_Assets/Assorted_Extras. The BEST one owned is always the one
## fished with -- a worse rod is never picked over a better one. The Proto Rod is
## Olly's gift in the Fish Shop opening scene and is never sold; the rest are on the
## shop's Rods page (cosmetic_shop_inventory.json, rows with "rod": true).
##
## Per rod:
##   modifier    applied to the player's side of the fight as x (1 + modifier):
##               the fish's line_strength, reel_step and recharge_time (rest), the
##               energy correct input drains (Fishing_Minigame.ENERGY_DRAIN) and the
##               idle line recovery on both sides (TENSION_DECAY_RED / _BLUE).
##               Minus = harder. Passive energy bleed, swim speed and the strike run
##               are deliberately untouched.
##   throw       fraction of the fishing spot's water (catch line -> far edge) the
##               bobber is thrown.
##   big         false = big fish never bite at all.
##   big_flat / big_mult      a big fish's table % becomes (% + flat) x mult
##   small_flat / small_mult  a small fish's becomes max(0, % + flat) x mult
##   discount    off every BETTER rod's $ and Fish Coin price once this is the best
##               rod owned. Not cumulative: only the best owned rod's discount counts.
##
## TWEAKABLE -- every rod's numbers are here and nowhere else.
const RODS := {
	"Proto_Rod": {"label": "Proto Rod", "modifier": -0.30, "throw": 0.25, "big": false,
			"big_flat": 0.0, "big_mult": 1.0, "small_flat": 0.0, "small_mult": 1.0, "discount": 0.0},
	"Improved_Rod": {"label": "Improved Rod", "modifier": -0.15, "throw": 0.40, "big": false,
			"big_flat": 0.0, "big_mult": 1.0, "small_flat": 0.0, "small_mult": 1.0, "discount": 0.10},
	"Good_Rod": {"label": "Good Rod", "modifier": -0.05, "throw": 0.50, "big": true,
			"big_flat": 0.0, "big_mult": 1.0, "small_flat": 0.0, "small_mult": 1.0, "discount": 0.20},
	"Super_Rod": {"label": "Super Rod", "modifier": 0.05, "throw": 0.60, "big": true,
			"big_flat": 1.0, "big_mult": 1.10, "small_flat": -5.0, "small_mult": 0.90, "discount": 0.30},
	"Amazing_Rod": {"label": "Amazing Rod", "modifier": 0.15, "throw": 0.70, "big": true,
			"big_flat": 5.0, "big_mult": 1.20, "small_flat": -10.0, "small_mult": 0.80, "discount": 0.50},
	"Gold_Rod": {"label": "Gold Rod", "modifier": 0.30, "throw": 0.80, "big": true,
			"big_flat": 15.0, "big_mult": 1.50, "small_flat": -20.0, "small_mult": 0.50, "discount": 0.0},
}
## Worst to best. A rod's position here is what "better" means everywhere.
const ROD_ORDER := ["Proto_Rod", "Improved_Rod", "Good_Rod", "Super_Rod", "Amazing_Rod", "Gold_Rod"]

## Map data name -> the permit needed to fish there. A map not listed needs none.
const PERMITS := {
	"Celeste_Harbour": "Celeste_Harbour_Fishing_Permit",
	"Verdant_Forest": "Verdant_Forest_Fishing_Permit",
	"DeepOceanFishing": "Deep_Ocean_Fishing_Permit",
}
const PERMIT_LABELS := {
	"Celeste_Harbour_Fishing_Permit": "Celeste Harbour Fishing Permit",
	"Verdant_Forest_Fishing_Permit": "Verdant Forest Fishing Permit",
	"Deep_Ocean_Fishing_Permit": "Deep Ocean Fishing Permit",
}

const NO_ROD_MESSAGE := "You have no fishing rod to go fishing with!"
## %s = the permit's name.
const NO_PERMIT_MESSAGE := "You need a %s to fish here! It can be bought from the FISH shop."


## The best rod the player owns, or "" for none.
static func best_owned() -> String:
	var best := ""
	for rod in ROD_ORDER:
		if GameState.has_item(rod):
			best = rod
	return best


static func has_any_rod() -> bool:
	return best_owned() != ""


static func rank(rod: String) -> int:
	return ROD_ORDER.find(rod)


static func is_rod(item_name: String) -> bool:
	return RODS.has(item_name)


static func label(item_name: String) -> String:
	if RODS.has(item_name):
		return str(RODS[item_name]["label"])
	return str(PERMIT_LABELS.get(item_name, item_name.replace("_", " ")))


## The numbers of the rod being fished with. Proto Rod's when none is owned, so a
## debug cast without a rod still works.
static func current() -> Dictionary:
	var rod := best_owned()
	return RODS[rod if rod != "" else "Proto_Rod"]


## True once `rod` is owned OR beaten by a better rod already owned -- buying a rod
## marks every worse one as owned too, so this and has_item agree after a purchase.
static func owned_or_superseded(rod: String) -> bool:
	return rank(rod) >= 0 and rank(rod) <= rank(best_owned())


## Fraction off a rod's prices right now: the best owned rod's discount, applied only
## to rods better than it.
static func discount_for(rod: String) -> float:
	var best := best_owned()
	if best == "" or rank(rod) <= rank(best):
		return 0.0
	return float(RODS[best]["discount"])


static func discounted(price: int, rod: String) -> int:
	return int(round(price * (1.0 - discount_for(rod))))


## Banks `rod` and every worse rod (skipping straight to a better one owns the lot).
static func grant(rod: String) -> void:
	for i in rank(rod) + 1:
		GameState.add_item_to_collection(ROD_ORDER[i])


# ============================================================
# PERMITS
# ============================================================

static func permit_for_map(map_data: String) -> String:
	return str(PERMITS.get(map_data, ""))


## "" when the player may fish on this map, else the message saying why not.
static func fishing_blocked_reason(map_data: String) -> String:
	if not has_any_rod():
		return NO_ROD_MESSAGE
	var permit := permit_for_map(map_data)
	if permit != "" and not GameState.has_item(permit):
		return NO_PERMIT_MESSAGE % label(permit)
	return ""


# ============================================================
# BITE RATES
# ============================================================

## One row's weight with the current rod: big fish pushed up (or removed entirely by
## a rod that cannot hold them), small fish pushed down. Rates are table percents.
static func adjusted_rate(base: float, big: bool) -> float:
	var rod := current()
	if big:
		if not bool(rod["big"]):
			return 0.0
		return maxf(0.0, (base + float(rod["big_flat"])) * float(rod["big_mult"]))
	return maxf(0.0, base + float(rod["small_flat"])) * float(rod["small_mult"])
