class_name EffectRegistry
extends RefCounted

######################################################################################################################################################
######################################################## EFFECT REGISTRY ############################################################################
######################################################################################################################################################
#
# A simple Callable-based lookup table used to dispatch card effects by key (e.g. lowercased attack
# name, card UID, or ability name). Adding a new card's effect only requires registering it here —
# no changes to dispatch chains in Main or CPU_AI.
#
# Usage:
#   var registry = EffectRegistry.new()
#   registry.register("hurricane", Callable(impl, "execute_hurricane"))
#   if registry.has("hurricane"):
#       await registry.dispatch("hurricane", [attacker, defender, is_opponent])
#

var _registry: Dictionary = {}

func register(key: String, execute_fn: Callable, score_fn: Callable = Callable()) -> void:
	if _registry.has(key):
		push_warning("EffectRegistry: Duplicate key '" + key + "' — overwriting previous entry.")
	_registry[key] = {"execute": execute_fn, "score": score_fn}

func has(key: String) -> bool:
	return _registry.has(key)

# Calls the execute Callable with the given args array.
# The returned value is a Signal when the function is async — await it at the call site.
func dispatch(key: String, args: Array) -> Variant:
	if not _registry.has(key):
		return null
	return _registry[key]["execute"].callv(args)

# Calls the score Callable with the given args array. Returns -1.0 if no scorer registered.
func score(key: String, args: Array) -> float:
	if not _registry.has(key):
		return -1.0
	var sc: Callable = _registry[key]["score"]
	if not sc.is_valid():
		return -1.0
	return float(sc.callv(args))

func get_all_keys() -> Array:
	return _registry.keys()
