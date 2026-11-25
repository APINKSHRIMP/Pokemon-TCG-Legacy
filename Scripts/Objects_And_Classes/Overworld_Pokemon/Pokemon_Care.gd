class_name PokemonCare
extends RefCounted

## LOOKING AFTER YOUR POKÉMON (2026-11-25): hunger, being ignored, Pokémon leaving you, and
## the notices and talk lines about them. Everything here is per Pokémon ID, in its flags.
##
## HUNGER (the CSV's "Hunger" column = hours until it is hungry, H; blank = it never gets
## hungry, never starves, and can't be fed):
##   * Every Pokémon you own (following you or at home) counts hours awake since it was last
##     fed (flag "hunger"; "hunger_clock" = the hour last counted). The night you sleep through
##     does NOT count (the bed's _do_sleep counts up to bedtime, then restarts the clocks).
##   * Stages (hunger_stage), user 2026-11-25:
##       1 HUNGRY       hunger >= H: it can be fed. No bubble - talking to it says so (HUNGER_LINES[0]).
##       2 VERY HUNGRY  half way from hungry to starving: stronger lines.
##       3 STARVING     hunger >= H * STARVING_FACTOR: a free STARVE_GRACE_HOURS (still the
##                      very-hungry lines, no penalty).
##       4 STARVED      past the free hour: each whole hour costs affection - the first
##                      STARVE_EARLY_CHARGES hours STARVE_LOSS_EARLY, then STARVE_LOSS_LATE
##                      each ("starve_paid" = hours charged). The sad bubble shows, and the
##                      strongest lines.
##   * A starving charge that leaves it at 0 affection -> it LEAVES (back to the wild).
##   * Feeding it (its favourite food, only when hungry) puts hunger back to 0.
##
## IGNORED (user 2026-11-25): hours awake without you talking to it (the menu opening counts).
##   Following you: NEGLECT_FOLLOW_LOSS per NEGLECT_FOLLOW_HOURS. At home: NEGLECT_HOME_LOSS
##   per NEGLECT_HOME_HOURS. The next talk says it felt forgotten (NEGLECT_LINES), and the
##   counts start again. A charge that leaves it at 0 affection -> it leaves (NEGLECT_LEFT_LINES).
##
## LEAVING: flag "leave_reason" ("hunger" / "neglect") is set by the charge that took it to 0.
##   Following you: told at once. At home: told when you're next in the house
##   (GameState pokemon_left_notices).
##
## LEVEL UPS: PokemonAffection.add() marks a new highest level (flag "level_up"); one line from
## LEVEL_UP_LINES pops up the next time nothing else is on screen (or as the talk line, if you
## talk to it first and nothing more urgent is waiting).
##
## THE WATCH: BaseMapScene starts watch() on every map. Every POLL_TIME it counts hunger and
## hours, sets the sad bubbles, and - only when nothing else is going on (no box, menu,
## cutscene, medal, evolution, battle return) - shows the next notice.

# ---- TWEAKABLES -------------------------------------------------------------
const STARVING_FACTOR := 2.0
## 0.5 = "very hungry" from half way between hungry and starving.
const VERY_HUNGRY_FRACTION := 0.5
## Hours it can be starving before it costs anything (and before the sad bubble).
const STARVE_GRACE_HOURS := 1
const STARVE_LOSS_EARLY := 20
const STARVE_EARLY_CHARGES := 2
const STARVE_LOSS_LATE := 50
const NEGLECT_FOLLOW_HOURS := 6.0
const NEGLECT_FOLLOW_LOSS := 10
const NEGLECT_HOME_HOURS := 12.0
const NEGLECT_HOME_LOSS := 20
const POLL_TIME := 0.5
## Said when it reaches a new highest level, levels 1..7 (%s = its name).
const LEVEL_UP_LINES := [
	"%s seems to be starting to trust you a tiny bit... Now might be a chance to pet it.",
	"%s seems to trust you somewhat more now... It looks like you can probably pet it.",
	"%s feels like it can fully trust you. You could definitely pet it now.",
	"%s seems to be getting comfortable around you. It seems it wants you to pet it.",
	"%s feels super comfortable around you now. It wants to be pet!",
	"%s feels a lot closer to you! It's asking you to pet it!",
	"%s feels closer to you than ever!",
]
## The talk line while it is hungry: hungry / very hungry (and the free starving hour) /
## starved. One at random, %s = its name.
const HUNGER_LINES := [
	[   # 1 hungry
		"You can hear %s's belly rumble...",
		"%s seems a bit peckish.",
		"%s looks like it could use a bite to eat.",
		"%s hasn't eaten in a while.",
		"%s looks hungry.",
		"%s keeps sniffing at your bag. It must be hungry.",
		"%s's tummy gives a little growl.",
	],
	[   # 2 very hungry (and the free starving hour)
		"%s looks really hungry!",
		"%s could really do with something to eat.",
		"%s has stomach cramps from not eating.",
		"%s is almost starving!",
		"%s's belly is rumbling loudly. It needs food soon!",
		"%s keeps looking at you, hoping for something to eat.",
		"%s is getting weak with hunger.",
	],
	[   # 4 starved (stage 3, the free starving hour, uses the lines above)
		"%s is absolutely starving!",
		"%s hasn't had anything to eat in a long time.",
		"%s looks like it's going to pass out from starvation!",
		"%s really needs something to eat!",
		"%s is so hungry it's ravenous!",
		"%s is wasting away... It needs food right now!",
		"%s can barely stand up, it's so hungry.",
	],
]
## The talk line after it was ignored long enough to lose affection (%s = its name).
const NEGLECT_LINES := [
	"%s thought you'd forgotten about it...",
	"%s was worried you didn't like it any more.",
	"%s looks like it's a little bit upset with you.",
	"%s gives you a hurt look. Where have you been?",
	"%s seems sulky. It wanted some attention.",
	"%s turns its nose up at you. It felt ignored.",
]
## It left: hunger (%s = its name).
const HUNGER_LEFT_LINES := [
	"%s was so hungry it left you...",
	"%s couldn't go any longer without food and wandered off to find some...",
	"%s was starving, so it went back to the wild to find something to eat...",
]
const HUNGER_LEFT_HOME_LINES := [
	"%s decided to leave. It must have been hungry...",
	"%s has gone. It was starving and went off to find food...",
]
## It left: ignored (%s = its name).
const NEGLECT_LEFT_LINES := [
	"%s thought you forgot about it, so it left...",
	"%s felt like you clearly didn't like it, so it left...",
	"%s was hoping you would pay it a little bit more attention, so it has left...",
	"Things looked like they wouldn't have worked out between you and %s...",
	"If %s was getting no attention, it thought it might as well go home...",
]
# -----------------------------------------------------------------------------

static var _watching: Node = null


# ---- hunger ---------------------------------------------------------------------

## Hours until hungry (the CSV), 0 = never.
static func hunger_limit(species_key: String) -> float:
	return PokemonPrefs.hunger_of(PokemonHome.species_of(species_key))


static func hunger(species_key: String) -> float:
	return float(GameState.get_pokemon_flags(species_key).get("hunger", 0.0))


## 0 fine, 1 hungry, 2 very hungry, 3 starving (the free hour), 4 starved (it's costing it).
static func hunger_stage(species_key: String) -> int:
	var limit := hunger_limit(species_key)
	if limit <= 0.0:
		return 0
	var h := hunger(species_key)
	var starving := limit * STARVING_FACTOR
	if h >= starving + float(STARVE_GRACE_HOURS):
		return 4
	if h >= starving:
		return 3
	if h >= limit + (starving - limit) * VERY_HUNGRY_FRACTION:
		return 2
	if h >= limit:
		return 1
	return 0


static func is_hungry(species_key: String) -> bool:
	return hunger_stage(species_key) >= 1


static func is_starving(species_key: String) -> bool:
	return hunger_stage(species_key) >= 3


## The sad bubble: starved past the free hour.
static func is_unhappy(species_key: String) -> bool:
	return hunger_stage(species_key) >= 4


## What the k-th charged starving hour costs (k from 1).
static func starve_loss(k: int) -> int:
	return STARVE_LOSS_EARLY if k <= STARVE_EARLY_CHARGES else STARVE_LOSS_LATE


## Counts every Pokémon's hours since last time, and charges starving and ignored ones their
## affection. Safe to call as often as you like: it writes only when the clock has moved.
static func credit_hunger() -> void:
	var now := PokemonAffection.now_hours()
	var follower := GameState.get_follower()
	for id in PokemonHome.roster():
		var species_key := str(id)
		var flags := GameState.get_pokemon_flags(species_key)
		if flags.is_empty() or str(flags.get("leave_reason", "")) != "":
			continue
		var changes := {}
		var h := float(flags.get("hunger", 0.0))
		var delta := 0.0
		if not flags.has("hunger_clock"):
			changes["hunger_clock"] = now
		else:
			delta = now - float(flags["hunger_clock"])
			if delta != 0.0:
				changes["hunger_clock"] = now
				if delta > 0.0:   # (backwards = a debug time jump: just restart the count)
					h += delta
					changes["hunger"] = h
				else:
					delta = 0.0
		var loss := 0
		var reason := ""
		# HUNGER
		var limit := hunger_limit(species_key)
		if limit > 0.0:
			# Hours charged: the first at the end of the free hour(s), then one per hour.
			var starved := h - limit * STARVING_FACTOR
			var charged := int(floor(starved)) - STARVE_GRACE_HOURS + 1 if starved >= float(STARVE_GRACE_HOURS) else 0
			var paid := int(flags.get("starve_paid", 0))
			if charged > paid:
				changes["starve_paid"] = charged
				for k in range(paid + 1, charged + 1):
					loss += starve_loss(k)
				reason = "hunger"
		# IGNORED: hours awake since you last talked to it, following or at home.
		var following := species_key == follower
		var acc_key := "lonely_follow" if following else "lonely_home"
		var paid_key := acc_key + "_paid"
		var every := NEGLECT_FOLLOW_HOURS if following else NEGLECT_HOME_HOURS
		var acc := float(flags.get(acc_key, 0.0)) + delta
		if delta > 0.0:
			changes[acc_key] = acc
		var due := int(floor(acc / every))
		var lonely_paid := int(flags.get(paid_key, 0))
		if due > lonely_paid:
			changes[paid_key] = due
			loss += (due - lonely_paid) * (NEGLECT_FOLLOW_LOSS if following else NEGLECT_HOME_LOSS)
			if reason == "":
				reason = "neglect"
		if not changes.is_empty():
			GameState.set_pokemon_flag_values(species_key, changes)
		if loss > 0 and PokemonAffection.add(species_key, -loss) <= 0:
			GameState.set_pokemon_flag(species_key, "leave_reason", reason)


## After the night: every clock starts again from the morning (the night is not counted).
static func restart_hunger_clocks() -> void:
	var now := PokemonAffection.now_hours()
	for id in PokemonHome.roster():
		if not GameState.get_pokemon_flags(str(id)).is_empty():
			GameState.set_pokemon_flag(str(id), "hunger_clock", now)


## It has just eaten.
static func feed(species_key: String) -> void:
	GameState.set_pokemon_flag_values(species_key,
			{"hunger": 0.0, "starve_paid": 0, "hunger_clock": PokemonAffection.now_hours()})


## You talked to it: the ignored counts start again. Returns true if it had been ignored long
## enough to lose affection since you last talked to it (the talk line then says so).
static func note_talked_to(species_key: String) -> bool:
	var flags := GameState.get_pokemon_flags(species_key)
	if flags.is_empty():
		return false
	var hurt := int(flags.get("lonely_follow_paid", 0)) > 0 or int(flags.get("lonely_home_paid", 0)) > 0
	GameState.set_pokemon_flag_values(species_key, {"lonely_follow": 0.0, "lonely_follow_paid": 0,
			"lonely_home": 0.0, "lonely_home_paid": 0})
	return hurt


static func leave_reason(species_key: String) -> String:
	return str(GameState.get_pokemon_flags(species_key).get("leave_reason", ""))


static func is_leaving(species_key: String) -> bool:
	return leave_reason(species_key) != ""


## What it says when you talk to it about how it's doing, "" for nothing to say. Most urgent
## first: hunger, then (from PokemonSleep, if any) needing sleep, being ignored, getting sleepy.
## Call BEFORE note_talked_to (which clears the ignored count).
static func care_line(species_key: String, poke_name: String, following: bool) -> String:
	var stage := hunger_stage(species_key)
	if stage > 0:
		var lines: Array = HUNGER_LINES[[0, 0, 1, 1, 2][stage]]
		return str(lines.pick_random()) % poke_name
	var flags := GameState.get_pokemon_flags(species_key)
	if int(flags.get("lonely_follow_paid", 0)) > 0 or int(flags.get("lonely_home_paid", 0)) > 0:
		return str(NEGLECT_LINES.pick_random()) % poke_name
	return ""


static func left_line(reason: String, poke_name: String, at_home: bool) -> String:
	var lines: Array = NEGLECT_LEFT_LINES
	if reason == "hunger":
		lines = HUNGER_LEFT_HOME_LINES if at_home else HUNGER_LEFT_LINES
	return str(lines.pick_random()) % poke_name


# ---- the watch ------------------------------------------------------------------

static func watch(map_root: Node) -> void:
	_watching = map_root
	var tree := map_root.get_tree()
	while is_instance_valid(map_root) and map_root.is_inside_tree() and _watching == map_root:
		await tree.create_timer(POLL_TIME).timeout
		if not is_instance_valid(map_root) or not map_root.is_inside_tree() or _watching != map_root:
			return
		if GameState.going_to_bed:
			continue
		PokemonAffection.credit_hours()
		credit_hunger()
		update_bubbles(tree)
		if not _busy(map_root):
			_show_next(map_root)


## The sad bubble on every one of your Pokémon on this map.
static func update_bubbles(tree: SceneTree) -> void:
	for group in [PokemonFollower.GROUP, PokemonHomeWanderer.GROUP]:
		for node in tree.get_nodes_in_group(group):
			var p := node as OverworldPokemon
			if p == null or p.pokemon_id == "":
				continue
			var sleeping: bool = p is PokemonHomeWanderer and (p as PokemonHomeWanderer).asleep
			p.set_unhappy(is_unhappy(p.pokemon_id) and not sleeping)


static func _busy(map_root: Node) -> bool:
	if MapManager.message_panel == null or MapManager.message_panel.visible:
		return true
	if MapManager.cutscene_active or MapManager.is_hard_locked() or MatchTransition.is_returning():
		return true
	if PokemonEvolution.is_busy() or BaseMapScene.medals_waiting():
		return true
	if not GameState.test_match_mode and GameState.autotest == null and GameState.medals_dirty:
		return true
	if MapManager._player == null or not is_instance_valid(MapManager._player) or not bool(MapManager._player.get("can_move")):
		return true
	if map_root.get("_menu_canvas_layer") != null:
		return true
	return false


## One notice at most per call: someone leaving, then "it left while you were out", then a
## level up.
static func _show_next(map_root: Node) -> void:
	var tree := map_root.get_tree()
	var in_house := PokemonHome.in_house(MapManager._map_scene_path)
	for id in PokemonHome.roster():
		var species_key := str(id)
		if not is_leaving(species_key):
			continue
		var reason := leave_reason(species_key)
		var poke_name := PokemonHome.name_of(species_key)
		var species := PokemonHome.species_of(species_key)
		if species_key == GameState.get_follower():
			MapManager._pokemon_say(species_key, poke_name, left_line(reason, poke_name, false))
			PokemonHome.release(species_key)
			var follower := tree.get_first_node_in_group(PokemonFollower.GROUP) as OverworldPokemon
			if follower != null and is_instance_valid(follower) and follower.pokemon_id == species_key:
				follower.despawn()
			return
		PokemonHome.release(species_key)
		if in_house:
			for node in tree.get_nodes_in_group(PokemonHomeWanderer.GROUP):
				if (node as OverworldPokemon).pokemon_id == species_key:
					(node as OverworldPokemon).despawn()
			PokemonHome.refresh_house(MapManager._player.get_parent())
			MapManager._pokemon_say(species, poke_name, left_line(reason, poke_name, true))
			return
		var notes := GameState.get_pokemon_left_notices()
		notes.append({"name": poke_name, "species": species, "line": left_line(reason, poke_name, true)})
		GameState.set_pokemon_left_notices(notes)
	if in_house:
		var notes := GameState.get_pokemon_left_notices()
		if not notes.is_empty():
			var note: Dictionary = notes.pop_front()
			GameState.set_pokemon_left_notices(notes)
			var line := str(note.get("line", ""))
			if line == "":
				line = left_line("hunger", str(note.get("name", "")), true)
			MapManager._pokemon_say(str(note.get("species", "")), str(note.get("name", "")), line)
			return
	for id in PokemonHome.roster():
		var line := take_level_up_line(str(id))
		if line != "":
			MapManager._pokemon_say(str(id), PokemonHome.name_of(str(id)), line)
			MapManager.show_affection_hearts(str(id))
			return


## The waiting level-up line for `species_key` ("" if none), and it is no longer waiting.
static func take_level_up_line(species_key: String) -> String:
	var lvl := int(GameState.get_pokemon_flags(species_key).get("level_up", 0))
	if lvl <= 0:
		return ""
	GameState.set_pokemon_flag(species_key, "level_up", 0)
	return LEVEL_UP_LINES[clampi(lvl, 1, LEVEL_UP_LINES.size()) - 1] % PokemonHome.name_of(species_key)
