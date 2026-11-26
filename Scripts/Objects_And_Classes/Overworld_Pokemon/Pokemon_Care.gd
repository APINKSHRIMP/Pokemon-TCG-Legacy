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
## SLEEP (user 2026-11-25): each species sleeps in ONE time slot (the CSV's Sleeps column;
##   Night includes after midnight). Only your FOLLOWER can be kept up:
##   * the slot BEFORE its sleep slot: talking to it says it's getting sleepy (SLEEPY_LINES -
##     the least urgent line of all).
##   * its sleep slot, following you: stronger lines (TIRED_LINES), and from
##     SLEEP_SAD_AFTER_HOURS into the slot (counted from when it started following you, if
##     later) the sad bubble; every whole hour after that costs SLEEP_LOSS_PER_HOUR (2pm sad,
##     3pm -20, 4pm -20 for an Afternoon sleeper). It never leaves over this.
##   * leave it at home and it goes to bed (PokemonHome.refresh_house puts each home Pokémon
##     on its bed during its sleep slot, and wandering downstairs the rest of the time - a
##     night Pokémon wanders downstairs all night, even while you sleep).
##   Flags: "follow_since" (the hour it last started following, or you woke up), "sleep_paid"
##   (hours charged) for the slot starting at "sleep_paid_at".
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
const SLEEP_SAD_AFTER_HOURS := 2.0
const SLEEP_LOSS_PER_HOUR := 20
const POLL_TIME := 0.5

## THE WARNING CRY (user 2026-11-26): no hunger or tiredness bar - instead, a Pokémon that
## needs something (hungry at any stage, or your follower in its sleep slot) gives a short,
## low, slow cry every WARN_CRY_EVERY real seconds while it's following you or on the same
## map (in the room) with you: the first WARN_CRY_FRACTION of its cry at WARN_CRY_PITCH
## (pitch AND speed: 0.75 = 25% lower and slower). Asleep ones stay quiet.
const WARN_CRY_EVERY := 30.0
const WARN_CRY_FRACTION := 0.5
const WARN_CRY_PITCH := 0.75
const WARN_CRY_LEVEL := 0.85   # its loudness against a normal cry (1.0)
## THE ALERT CRY (user 2026-11-26): once it's actually LOSING affection (starved past the
## free hour, or your follower kept up into the hours that cost it), the warning becomes the
## WHOLE cry (ALERT_CRY_FRACTION) at ALERT_CRY_PITCH (0.65 = 35% lower, and slower).
## Same timing as the warning.
const ALERT_CRY_FRACTION := 1.0
const ALERT_CRY_PITCH := 0.65
const ALERT_CRY_LEVEL := 1.0
## The first warning on each map load comes a random whole number of seconds in this range
## after you have control (user 2026-11-26) - the clock only starts once the post-match
## things (messages, medals, evolution, cutscenes) are done, and every warning timer is
## PAUSED while anything is on screen, so a warning is never heard over one.
const WARN_CRY_FIRST_MIN := 4
const WARN_CRY_FIRST_MAX := 10
## The slot before its sleep slot: it's getting sleepy (%s = its name).
const SLEEPY_LINES := [
	"%s is looking a bit sleepy!",
	"%s looks like it could go to sleep soon.",
	"%s is looking tired now.",
	"%s lets out a big yawn.",
	"%s's eyelids are starting to droop.",
	"%s is rubbing its eyes. It'll want its bed soon.",
]
## Its sleep slot and still following you (%s = its name).
const TIRED_LINES := [
	"%s can't keep its eyes open!",
	"%s is fighting to stay awake!",
	"%s should be in bed!",
	"%s is struggling to stay up, it's so tired.",
	"%s keeps nodding off on its feet!",
	"%s is so tired it can barely walk straight. Take it home to bed!",
]
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
## THE WARNING CRY: ID -> the msec (Time.get_ticks_msec) its next warning is due.
static var _next_warn_ms: Dictionary = {}
## The msec of the last poll (busy polls push every timer back by the time they took).
static var _last_warn_poll_ms: int = 0


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


## The sad bubble: starved past the free hour, or a follower kept up past its bedtime.
static func is_unhappy(species_key: String) -> bool:
	return hunger_stage(species_key) >= 4 or hours_kept_up(species_key) >= SLEEP_SAD_AFTER_HOURS


# ---- sleep ----------------------------------------------------------------------

## The slot right now, Bedtime counted as Night.
static func current_slot() -> String:
	var t := GameState.get_time()
	return "Night" if t == "Bedtime" else t


static func slot_before(slot: String) -> String:
	var i := PokemonPrefs.SLEEP_SLOTS.find(slot)
	return PokemonPrefs.SLEEP_SLOTS[(i + PokemonPrefs.SLEEP_SLOTS.size() - 1) % PokemonPrefs.SLEEP_SLOTS.size()]


static func sleep_slot(species_key: String) -> String:
	return PokemonPrefs.sleeps_of(PokemonHome.species_of(species_key))


## Is it this Pokémon's sleep slot right now?
static func is_sleep_time(species_key: String) -> bool:
	return current_slot() == sleep_slot(species_key)


static func is_sleepy_soon(species_key: String) -> bool:
	return current_slot() == slot_before(sleep_slot(species_key))


## The hour (now_hours) the current slot began.
static func slot_start_hours() -> float:
	var start: float = GameState.CLOCK_SLOT_START.get(current_slot(), 8.0)
	return PokemonAffection.now_hours() - (GameState.clock_hours() - start)


## Hours your FOLLOWER has been kept up in its sleep slot (0 for anyone else, or out of it).
static func hours_kept_up(species_key: String) -> float:
	if species_key == "" or species_key != GameState.get_follower() or not is_sleep_time(species_key):
		return 0.0
	var since := slot_start_hours()
	var flags := GameState.get_pokemon_flags(species_key)
	if flags.has("follow_since"):
		since = maxf(since, float(flags["follow_since"]))
	return maxf(PokemonAffection.now_hours() - since, 0.0)


## Charges the follower SLEEP_LOSS_PER_HOUR for every whole hour kept up past
## SLEEP_SAD_AFTER_HOURS in its sleep slot.
static func credit_sleep() -> void:
	var follower := GameState.get_follower()
	if follower == "" or GameState.get_pokemon_flags(follower).is_empty():
		return
	var kept := hours_kept_up(follower)
	if kept < SLEEP_SAD_AFTER_HOURS + 1.0:
		return
	var due := int(floor(kept - SLEEP_SAD_AFTER_HOURS))
	var flags := GameState.get_pokemon_flags(follower)
	var key := slot_start_hours()
	var paid := int(flags.get("sleep_paid", 0)) if is_equal_approx(float(flags.get("sleep_paid_at", -1.0)), key) else 0
	if due > paid:
		GameState.set_pokemon_flag_values(follower, {"sleep_paid": due, "sleep_paid_at": key})
		PokemonAffection.add(follower, -(due - paid) * SLEEP_LOSS_PER_HOUR)


## It has just started following you (or you've just woken up together).
static func note_following(species_key: String) -> void:
	if species_key != "" and not GameState.get_pokemon_flags(species_key).is_empty():
		GameState.set_pokemon_flag(species_key, "follow_since", PokemonAffection.now_hours())


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
	note_following(GameState.get_follower())   # it woke up with you


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
## first: hunger, then needing sleep, being ignored, getting sleepy (the last two only matter
## for the follower).
## Call BEFORE note_talked_to (which clears the ignored count).
static func care_line(species_key: String, poke_name: String, following: bool) -> String:
	var stage := hunger_stage(species_key)
	if stage > 0:
		var lines: Array = HUNGER_LINES[[0, 0, 1, 1, 2][stage]]
		return str(lines.pick_random()) % poke_name
	if following and is_sleep_time(species_key):
		return str(TIRED_LINES.pick_random()) % poke_name
	var flags := GameState.get_pokemon_flags(species_key)
	if int(flags.get("lonely_follow_paid", 0)) > 0 or int(flags.get("lonely_home_paid", 0)) > 0:
		return str(NEGLECT_LINES.pick_random()) % poke_name
	if following and is_sleepy_soon(species_key):
		return str(SLEEPY_LINES.pick_random()) % poke_name
	return ""


static func left_line(reason: String, poke_name: String, at_home: bool) -> String:
	var lines: Array = NEGLECT_LEFT_LINES
	if reason == "hunger":
		lines = HUNGER_LEFT_HOME_LINES if at_home else HUNGER_LEFT_LINES
	return str(lines.pick_random()) % poke_name


# ---- the watch ------------------------------------------------------------------

static func watch(map_root: Node) -> void:
	_watching = map_root
	_next_warn_ms.clear()   # a new map: the first warning is 4-10 s after you have control
	_last_warn_poll_ms = Time.get_ticks_msec()
	var tree := map_root.get_tree()
	while is_instance_valid(map_root) and map_root.is_inside_tree() and _watching == map_root:
		await tree.create_timer(POLL_TIME).timeout
		if not is_instance_valid(map_root) or not map_root.is_inside_tree() or _watching != map_root:
			return
		if GameState.going_to_bed:
			continue
		PokemonAffection.credit_hours()
		credit_hunger()
		credit_sleep()
		update_bubbles(tree)
		PokemonHome.note_positions(tree)   # the house layout (stairs keep where they were)
		var busy := _busy(map_root)
		warn_cries(tree, busy)
		if not busy:
			_show_next(map_root)


## Does it need something the warning cry is about? Hungry (any stage), or your follower in
## its sleep slot.
static func needs_warning(species_key: String) -> bool:
	if species_key == "" or GameState.get_pokemon_flags(species_key).is_empty() or is_leaving(species_key):
		return false
	return hunger_stage(species_key) >= 1 \
			or (species_key == GameState.get_follower() and is_sleep_time(species_key))


## Is it losing affection over it right now? Starved (stage 4), or your follower kept up
## past the first charged hour of its sleep slot (credit_sleep's first charge).
static func needs_alert(species_key: String) -> bool:
	return hunger_stage(species_key) >= 4 or hours_kept_up(species_key) >= SLEEP_SAD_AFTER_HOURS + 1.0


## THE WARNING CRY: every one of your Pokémon on this map that needs something cries (a part
## of its cry, low and slow) every WARN_CRY_EVERY seconds. One at a time. While something's
## on screen or a cutscene runs (`busy`) the timers stand still and no new one starts.
static func warn_cries(tree: SceneTree, busy: bool) -> void:
	var now := Time.get_ticks_msec()
	var elapsed := now - _last_warn_poll_ms
	_last_warn_poll_ms = now
	busy = busy or GameState.going_to_bed or MapManager.cutscene_active or MapManager.overworld_paused
	if busy:
		for id in _next_warn_ms.keys():
			_next_warn_ms[id] = int(_next_warn_ms[id]) + elapsed   # paused
		return
	var on_map := {}
	for group in [PokemonFollower.GROUP, PokemonHomeWanderer.GROUP]:
		for node in tree.get_nodes_in_group(group):
			var p := node as OverworldPokemon
			if p == null or p._is_gone or p.pokemon_id == "":
				continue
			if p is PokemonHomeWanderer and (p as PokemonHomeWanderer).asleep:
				continue
			if needs_warning(p.pokemon_id):
				on_map[p.pokemon_id] = p
	for id in _next_warn_ms.keys():
		if not on_map.has(id):
			_next_warn_ms.erase(id)   # (off this map or fine now: its first one waits again)
	for id in on_map:
		if not _next_warn_ms.has(id):
			_next_warn_ms[id] = now + randi_range(WARN_CRY_FIRST_MIN, WARN_CRY_FIRST_MAX) * 1000
	for id in on_map:
		if now < int(_next_warn_ms[id]):
			continue
		var alert := needs_alert(str(id))   # losing affection: the whole cry, lower
		if SoundManagerScript.play_cry_part(PokemonHome.species_of(str(id)),
				ALERT_CRY_PITCH if alert else WARN_CRY_PITCH,
				ALERT_CRY_FRACTION if alert else WARN_CRY_FRACTION,
				ALERT_CRY_LEVEL if alert else WARN_CRY_LEVEL):
			_next_warn_ms[id] = now + int(WARN_CRY_EVERY * 1000.0)
		return   # one per poll (if a cry was sounding it tries again next poll)


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
