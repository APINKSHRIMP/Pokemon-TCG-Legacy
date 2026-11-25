class_name PokemonAffection
extends RefCounted

## AFFECTION (2026-11-24): how much each of YOUR Pokémon likes you, 0 to MAX, in its flags
## (GameState pokemon_flags[species]["affection"]). Every LEVEL_SIZE points is a new level,
## 0 to 7, and each level has its own talk reaction and lines - like the walking-Pokémon
## games, where the closer it is to you the happier it acts when you turn round to it.
##
##   level 0   looks away for a second - skittish, doesn't trust you yet
##   level 1   looks away, not as long, then looks back - still doesn't trust you
##   level 2   doesn't look away, but watches you carefully
##   level 3   a little hop - it looks happy
##   level 4   wiggles side to side - a really good mood
##   level 5   jumps up and down with glee lines - it likes you a lot
##   level 6   jumps up and down with hearts - it loves you lots
##   level 7   jumps AND wiggles, with hearts - your best friend, ready for anything
##
## Where points come from (user 2026-11-25; matches and fish only count for the FOLLOWER):
##   * GAIN_PER_HOUR for every in-game hour it spends following you, GAIN_PER_HOUR_HOME for
##     every hour it spends at home (the clock - matches, fishing, anything that moves it; the
##     night you sleep through does NOT count). Credited by the care watch on every map, and
##     whenever it starts or stops following.
##   * GAIN_PER_NIGHT_IN_BED for every night it sleeps in a bed (the bedroom's _do_sleep).
##   * GAIN_PER_PRIZE for every prize card you take in a match (won or lost) with it following
##     you, and GAIN_PER_WIN for a win.
##   * GAIN_PER_FISH for every fish you catch with it following you.
##   * GAIN_PET when it ACCEPTS a pet (a chance - PET CHANCE below); LOSS_FAILED_PET when it
##     doesn't. GAIN_FAVOURITE_FOOD when you feed it (always its favourite food).
##   * Losses for hunger and being ignored: PokemonCare.
## Some Pokémon will evolve at a level (PokemonEvolution - the CSV's Evolution column).

# ---- TWEAKABLES -------------------------------------------------------------
const MAX := 700
const LEVEL_SIZE := 100         ## 700 / 100 = 7: levels 0..7 (7 only at the very top)
const GAIN_PER_HOUR := 2        ## following you
const GAIN_PER_HOUR_HOME := 1   ## living at home
const GAIN_PER_NIGHT_IN_BED := 10
const GAIN_PER_PRIZE := 1
const GAIN_PER_WIN := 5
const GAIN_PER_FISH := 1
const GAIN_PET := 2
const LOSS_FAILED_PET := 1
const GAIN_FAVOURITE_FOOD := 10

## PET CHANCE (user 2026-11-25): a pet can be tried any time, but whether it is accepted
## depends on its level and the in-game hours since the LAST TRY (pass or fail - every try
## restarts the timer; the hours you sleep through count, it's real time apart).
##   * levels 0-5: for PET_LOCKOUT_HOURS[level] hours after a try, every try fails. After that
##     it starts at PET_START_CHANCE and climbs PET_CHANCE_PER_HOUR per hour (smoothly, per
##     minute) to a sure thing: level 0 = 5h locked, 50% at 5h, 60% at 6h ... 100% at 10h;
##     level 5 = never locked, 50% straight away, 100% after 5h.
##   * level 6 and 7 (from PET_ALWAYS_LEVEL): it always works - it loves you already.
##   * just gone up to a new highest level (flag "pet_free"): the next try works, then the
##     timer runs again from that try.
##   * a NEW Pokémon's timer starts when it joins you (PokemonHome), so a level 0 one can't be
##     pet for its first 5 hours. (No "pet_clock" at all - only an old save - counts as never tried.)
## Only an accepted pet gives GAIN_PET (and counts in its "pets" flag).
const PET_LOCKOUT_HOURS := [5.0, 4.0, 3.0, 2.0, 1.0, 0.0]   ## per level 0..5
const PET_START_CHANCE := 0.5
const PET_CHANCE_PER_HOUR := 0.1
const PET_ALWAYS_LEVEL := 6
## What it says when you wake it up, per level 0..7 (%s = its name).
const WAKE_LINES := [
	["%s was fast asleep! It glares at you for waking it up.", "%s jolts awake and snaps at you. Why did you wake it up?!"],
	["%s wakes with a start. It hated being woken up!", "%s grumbles awake. It wasn't happy about that."],
	["%s wakes up groggily... It doesn't look pleased.", "%s blinks awake and eyes you suspiciously."],
	["%s yawns and slowly wakes up. It doesn't seem to mind too much.", "%s stirs awake. It seems okay with it."],
	["%s stretches and wakes up. It doesn't mind being woken up.", "%s wakes up with a little yawn and looks at you."],
	["%s wakes up and stretches happily. It seems pleased to see you!", "%s opens its eyes and perks right up when it sees you."],
	["%s wakes up and beams at you. It's glad you woke it up!", "%s wakes up and nuzzles you straight away!"],
	["%s springs awake, overjoyed to see you!", "%s wakes up and jumps for joy. It missed you!"],
]
## The pet lines come in four bands of two levels: 0-1, 2-3, 4-5, 6-7 (one picked at random,
## %s = its name). Bands 6-7 can't fail, so they have no "fail" lines. Say "pet", never
## "petting" / "petted" (user's rule).
const PET_LINES := {
	"fail": [
		[   # levels 0-1: won't have it
			"%s jerks away from your hand!",
			"%s snaps at your fingers! It doesn't want to be touched.",
			"%s backs off and keeps its distance.",
			"%s dodges your hand and glares at you.",
			"%s shuffles out of reach. It isn't having any of it.",
		],
		[   # levels 2-3: doesn't trust you yet
			"%s steps back, watching you closely. It doesn't trust you yet.",
			"%s turns away. It isn't ready for that yet.",
			"%s edges away from your hand, keeping an eye on you.",
			"%s isn't quite sure about you yet and moves out of reach.",
			"%s ducks under your hand and watches you warily.",
		],
		[   # levels 4-5: had enough for now
			"%s has had plenty of attention for now.",
			"%s wriggles away. It's had enough pets for the moment.",
			"%s looks a bit crowded. Maybe give it some space.",
			"%s doesn't want a pet right now.",
			"%s feels a little smothered. Maybe later!",
		],
	],
	"ok": [
		[   # levels 0-1: puts up with it
			"%s grudgingly lets you give it a pet.",
			"%s winces a little as you touch it... but it puts up with it.",
			"%s tenses up, but lets you give it a quick pet.",
			"%s tolerates the pet. It doesn't seem to enjoy it much.",
			"%s tentatively lets you reach out. It isn't sure about this...",
		],
		[   # levels 2-3: doesn't mind
			"%s lets you give it a pet. It doesn't seem to mind.",
			"%s accepts the pet, though it doesn't lean into it.",
			"%s seems okay with that.",
			"%s stays still for the pet. It almost seems to enjoy it!",
			"%s doesn't pull away. It seems to be warming up to you.",
		],
		[   # levels 4-5: enjoyed it
			"%s loved that! ...but it seems to have had enough for now.",
			"%s enjoyed the pet... just about!",
			"%s seems to smile as you give it a pet.",
			"%s leans into your hand. It's feeling closer to you.",
			"%s closes its eyes happily. It really liked that!",
		],
		[   # levels 6-7: loves it
			"%s leans right into your hand. It loves it!",
			"%s nuzzles up against you. It can't get enough!",
			"%s snuggles closer. It didn't want you to stop!",
			"%s is your best bud! It loves every pet.",
			"%s presses happily against your hand. It loves you!",
		],
	],
}

## Level 0 / 1: how long it looks away before turning back (seconds).
const LOOK_AWAY_TIME := [1.1, 0.45]
## The hops: height (its own world px), time per half-hop.
const HOP_PX := 4.0
const HOP_TIME := 0.09
## The wiggle: how far each way (world px), time per swing, swings.
const WIGGLE_PX := 1.5
const WIGGLE_TIME := 0.07
const WIGGLE_SWINGS := 6
## The hearts (levels 6-7): how many, the gap between them, how far they float up, how long each lives.
const HEARTS := [0, 0, 0, 0, 0, 0, 3, 5]
const HEART_GAP := 0.16
const HEART_RISE := 10.0
const HEART_LIFE := 0.9
## The glee lines (level 5): how long they stay, how many times they pulse.
const GLEE_TIME := 0.9
const GLEE_PULSES := 3
const HEART_ICON := "res://Image_Assets/Icons/Message_Icons/heart.png"
const GLEE_ICON := "res://Image_Assets/Icons/Message_Icons/glee.png"
const EMOTE_Z := 101

## What it says when you talk to it, per level; one at random (%s = its name).
const LINES := [
	[   # 0
		"%s turns away from you. It doesn't seem to trust you yet...",
		"%s looks away nervously. It's still skittish around you.",
		"%s avoids your eyes. It doesn't trust you just yet.",
	],
	[   # 1
		"%s glances away... then slowly looks back at you. It still doesn't quite trust you.",
		"%s looks away for a moment, then peeks back. It isn't sure about you yet.",
		"%s hesitates, then turns back to face you. It doesn't fully trust you yet.",
	],
	[   # 2
		"%s is watching you carefully.",
		"%s keeps a close eye on you, wondering what you'll do next.",
		"%s stares at you intently. It's trying to figure you out.",
	],
	[   # 3
		"%s looks happy!",
		"%s seems glad to be with you.",
		"%s gives you a cheerful look!",
	],
	[   # 4
		"%s wiggles from side to side. It seems to be in a really good mood!",
		"%s is feeling great!",
		"%s sways happily. It's in high spirits!",
	],
	[   # 5
		"%s hops up and down! It really likes you a lot!",
		"%s jumps about excitedly. It's so happy to be with you!",
		"%s bounces with glee! It likes you a lot!",
	],
	[   # 6
		"%s jumps for joy! It loves you lots!",
		"%s is bursting with affection! It loves you!",
		"%s bounces around you happily. It loves you so much!",
	],
	[   # 7
		"%s is your best friend! It won't ever leave your side!",
		"%s dances around you, full of love. It's ready for anything with you!",
		"%s looks at you with total trust. Best friends, ready for any adventure!",
	],
]
# -----------------------------------------------------------------------------


static func points(species_key: String) -> int:
	return int(GameState.get_pokemon_flags(species_key).get("affection", 0))


static func level_of_points(p: int) -> int:
	return clampi(p / LEVEL_SIZE, 0, MAX / LEVEL_SIZE)


static func level(species_key: String) -> int:
	return level_of_points(points(species_key))


## Adds (or with a negative amount, takes) points, clamped to 0..MAX. Only for Pokémon you own.
## Returns the new total.
## A NEW HIGHEST level (user 2026-11-25) is announced (PokemonCare's LEVEL_UP_LINES - flag
## "level_up") and makes the next pet a sure thing (flag "pet_free"). Losing a level (hunger)
## and getting it back again is not new, so it isn't announced twice.
static func add(species_key: String, amount: int) -> int:
	var flags := GameState.get_pokemon_flags(species_key)
	if species_key == "" or flags.is_empty():
		return 0
	var before := points(species_key)
	var p := clampi(before + amount, 0, MAX)
	var changes := {"affection": p}
	var lvl := level_of_points(p)
	if lvl > int(flags.get("announced_level", level_of_points(before))):
		changes["announced_level"] = lvl
		changes["level_up"] = lvl
		changes["pet_free"] = true
	GameState.set_pokemon_flag_values(species_key, changes)
	return p


# ---- a pet (see PET CHANCE above) --------------------------------------------------

## The chance (0..1) a pet would be accepted right now.
static func pet_chance(species_key: String) -> float:
	var lvl := level(species_key)
	if lvl >= PET_ALWAYS_LEVEL:
		return 1.0
	var flags := GameState.get_pokemon_flags(species_key)
	if bool(flags.get("pet_free", false)):
		return 1.0   # it has just gone up a level
	if not flags.has("pet_clock"):
		return 1.0   # never tried
	var since := now_hours() - float(flags["pet_clock"])
	if since < 0.0:
		return 1.0   # the clock went backwards (a debug time jump): treat it as long ago
	var lock: float = PET_LOCKOUT_HOURS[mini(lvl, PET_LOCKOUT_HOURS.size() - 1)]
	if since < lock:
		return 0.0
	return clampf(PET_START_CHANCE + PET_CHANCE_PER_HOUR * (since - lock), 0.0, 1.0)


## Tries a pet: rolls pet_chance, restarts the timer (pass or fail), and on a pass gives
## GAIN_PET and counts it. Returns {"ok": accepted, "level": the level it was AT when you tried}.
static func try_pet(species_key: String) -> Dictionary:
	var lvl := level(species_key)
	var ok := randf() < pet_chance(species_key)
	GameState.set_pokemon_flag_values(species_key, {"pet_clock": now_hours(), "pet_free": false})
	if ok:
		GameState.bump_pokemon_flag(species_key, "pets")
		add(species_key, GAIN_PET)
	else:
		add(species_key, -LOSS_FAILED_PET)
	return {"ok": ok, "level": lvl}


## 0-3: which two-level band `lvl` is in (0-1, 2-3, 4-5, 6-7).
static func pet_band(lvl: int) -> int:
	return clampi(lvl / 2, 0, 3)


## Talking to it while it sleeps wakes it up (user 2026-11-25): one of its level's lines.
static func wake_line(lvl: int, poke_name: String) -> String:
	var lines: Array = WAKE_LINES[clampi(lvl, 0, WAKE_LINES.size() - 1)]
	return str(lines.pick_random()) % poke_name


static func pet_line(lvl: int, ok: bool, poke_name: String) -> String:
	var bands: Array = PET_LINES["ok" if ok else "fail"]
	var lines: Array = bands[mini(pet_band(lvl), bands.size() - 1)]
	return str(lines.pick_random()) % poke_name


static func set_points(species_key: String, p: int) -> void:
	if species_key == "" or GameState.get_pokemon_flags(species_key).is_empty():
		return
	GameState.set_pokemon_flag(species_key, "affection", clampi(p, 0, MAX))


# ---- time spent following you ---------------------------------------------------

## The game's own running clock in hours: day 1 8am = 8, day 2 9:30am = 33.5. Only grows.
static func now_hours() -> float:
	return float(GameState.get_date() - 1) * 24.0 + GameState.clock_hours()


## Starts counting hours for `species_key` from now (it has just joined you, or you have
## just woken up). Its flag "affection_clock" holds the hour last credited.
static func start_clock(species_key: String) -> void:
	if species_key == "" or GameState.get_pokemon_flags(species_key).is_empty():
		return
	GameState.set_pokemon_flag(species_key, "affection_clock", now_hours())


## Every clock starts again from now (after the night: the night is not counted).
static func start_all_clocks() -> void:
	for id in PokemonHome.roster():
		start_clock(str(id))


## Credits every Pokémon you own with every WHOLE hour since it was last credited -
## GAIN_PER_HOUR following you, GAIN_PER_HOUR_HOME at home; the part-hour is kept for next
## time. Safe to call as often as you like (it writes only when a whole hour has gone by).
static func credit_hours() -> void:
	var follower := GameState.get_follower()
	var now := now_hours()
	for id in PokemonHome.roster():
		var species_key := str(id)
		var flags := GameState.get_pokemon_flags(species_key)
		if flags.is_empty():
			continue
		if not flags.has("affection_clock"):
			start_clock(species_key)
			continue
		var since := float(flags["affection_clock"])
		var whole := int(floor(now - since))
		if whole <= 0:
			if whole < 0:
				start_clock(species_key)   # the clock went backwards (a debug time jump): start again
			continue
		GameState.set_pokemon_flag(species_key, "affection_clock", since + float(whole))
		add(species_key, whole * (GAIN_PER_HOUR if species_key == follower else GAIN_PER_HOUR_HOME))


## Bedtime: GAIN_PER_NIGHT_IN_BED for everyone sleeping in a bed tonight (anyone without one
## has already left - MapManager.confirm_sleep).
static func credit_night_in_bed() -> void:
	var beds := PokemonHome.assignment()
	for id in PokemonHome.roster():
		if beds.has(id) or PokemonHome.sleeps_on_player_bed(str(id)):
			add(str(id), GAIN_PER_NIGHT_IN_BED)


## A match with it following you, won or lost: GAIN_PER_PRIZE per prize card you took, and
## GAIN_PER_WIN for a win. A win is also counted on it (flag "wins": matches won with it
## following you - kept for the "win X battles" evolutions).
static func on_match_result(won: bool, prizes_taken: int) -> void:
	var follower := GameState.get_follower()
	if follower == "" or GameState.get_pokemon_flags(follower).is_empty():
		return
	var gain := maxi(prizes_taken, 0) * GAIN_PER_PRIZE
	if won:
		GameState.bump_pokemon_flag(follower, "wins")
		gain += GAIN_PER_WIN
	if gain > 0:
		add(follower, gain)


## A fish caught with it following you.
static func on_fish_caught() -> void:
	var follower := GameState.get_follower()
	if follower != "" and not GameState.get_pokemon_flags(follower).is_empty():
		add(follower, GAIN_PER_FISH)


# ---- talking to it -------------------------------------------------------------

static func talk_line(species_key: String, poke_name: String) -> String:
	var lines: Array = LINES[level(species_key)]
	return str(lines.pick_random()) % poke_name


## Plays its level's reaction on `pokemon` (an OverworldPokemon already facing the player).
## Fire and forget: it finishes on its own and never holds anything up.
static func react(pokemon: OverworldPokemon, lvl: int, player_pos: Vector2) -> void:
	if pokemon == null or not is_instance_valid(pokemon) or pokemon.sprite == null:
		return
	var calm := UITheme.motion_reduced()
	match lvl:
		0, 1:
			# Looks the other way, then back at you.
			var away := pokemon.global_position - player_pos
			pokemon.face_vector(away)
			await pokemon.get_tree().create_timer(LOOK_AWAY_TIME[lvl]).timeout
			if is_instance_valid(pokemon):
				pokemon.face_vector(player_pos - pokemon.global_position)
		2:
			pass   # it just keeps watching you
		3:
			if not calm:
				_hops(pokemon, 1)
		4:
			if not calm:
				_wiggle(pokemon)
		5:
			_glee(pokemon)
			if not calm:
				_hops(pokemon, 3)
		6:
			_hearts(pokemon, HEARTS[6])
			if not calm:
				_hops(pokemon, 3)
		_:
			_hearts(pokemon, HEARTS[7])
			if not calm:
				await _hops(pokemon, 2)
				if is_instance_valid(pokemon):
					_wiggle(pokemon)


## Hops and wiggles move the sprite's OFFSET (sheet px), not its position: the walk cycle
## resets sprite.position on every frame change (OverworldPokemon._apply_region).
static func _hops(pokemon: OverworldPokemon, count: int) -> void:
	await hop(pokemon, count, HOP_PX, HOP_TIME)


## Shared with MapManager's pet / feed hop.
static func hop(pokemon: OverworldPokemon, count: int, px: float, half_time: float) -> void:
	var spr := pokemon.sprite
	var up := px / maxf(pokemon.draw_scale(), 0.01)
	var tw := spr.create_tween()
	for _k in count:
		tw.tween_property(spr, "offset:y", -up, half_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(spr, "offset:y", 0.0, half_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished


static func _wiggle(pokemon: OverworldPokemon) -> void:
	var spr := pokemon.sprite
	var side := WIGGLE_PX / maxf(pokemon.draw_scale(), 0.01)
	var tw := spr.create_tween()
	for k in WIGGLE_SWINGS:
		tw.tween_property(spr, "offset:x", side if k % 2 == 0 else -side, WIGGLE_TIME)
	tw.tween_property(spr, "offset:x", 0.0, WIGGLE_TIME)
	await tw.finished


## Where its head is, in its own space: the top of the drawn art.
static func head_y(pokemon: OverworldPokemon) -> float:
	var top := (float(pokemon.art_top) - pokemon.cell.y * 0.5) * pokemon.draw_scale()
	return pokemon.sprite.position.y + top - 3.0


static func _emote_sprite(pokemon: OverworldPokemon, icon: String) -> Sprite2D:
	if not ResourceLoader.exists(icon):
		return null
	var s := Sprite2D.new()
	s.texture = load(icon)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.z_as_relative = false
	s.z_index = EMOTE_Z
	s.add_to_group("no_time_grade")   # keeps its own colours at night, like SpeechEmote
	pokemon.add_child(s)
	return s


static func _hearts(pokemon: OverworldPokemon, count: int) -> void:
	for k in count:
		if not is_instance_valid(pokemon):
			return
		var h := _emote_sprite(pokemon, HEART_ICON)
		if h == null:
			return
		var start := Vector2(randf_range(-7.0, 7.0), head_y(pokemon))
		h.position = start
		h.scale = Vector2.ZERO
		var tw := h.create_tween()
		tw.tween_property(h, "scale", Vector2.ONE * 1.3, 0.08)
		tw.tween_property(h, "scale", Vector2.ONE, 0.06)
		tw.parallel().tween_property(h, "position:y", start.y - HEART_RISE, HEART_LIFE).set_ease(Tween.EASE_OUT)
		tw.tween_property(h, "modulate:a", 0.0, 0.15)
		tw.tween_callback(h.queue_free)
		await pokemon.get_tree().create_timer(HEART_GAP).timeout


static func _glee(pokemon: OverworldPokemon) -> void:
	var g := _emote_sprite(pokemon, GLEE_ICON)
	if g == null:
		return
	g.position = Vector2(0, head_y(pokemon) - 2.0)
	var tw := g.create_tween()
	var beat := GLEE_TIME / float(GLEE_PULSES * 2)
	for _k in GLEE_PULSES:
		tw.tween_property(g, "scale", Vector2.ONE * 1.25, beat)
		tw.tween_property(g, "scale", Vector2.ONE, beat)
	tw.tween_property(g, "modulate:a", 0.0, 0.12)
	tw.tween_callback(g.queue_free)
