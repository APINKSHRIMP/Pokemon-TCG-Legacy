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
## Where points come from (only the FOLLOWER gains from time and matches):
##   * GAIN_PER_HOUR for every in-game hour it spends following you (the clock; the night you
##     sleep through does not count). Credited whenever a map loads, and when it stops following.
##   * GAIN_PER_PRIZE for every prize card you take in a match you WIN with it following you.
##   * GAIN_PET when you pet it, GAIN_FAVOURITE_FOOD when you feed it its favourite food.
## Some Pokémon will evolve at a level (PokemonEvolution - the CSV's Evolution column).

# ---- TWEAKABLES -------------------------------------------------------------
const MAX := 196
const LEVEL_SIZE := 28          ## 196 / 28 = 7: levels 0..7 (7 only at the very top)
const GAIN_PER_HOUR := 1
const GAIN_PER_PRIZE := 1
const GAIN_PET := 2
const GAIN_FAVOURITE_FOOD := 5

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
static func add(species_key: String, amount: int) -> int:
	if species_key == "" or GameState.get_pokemon_flags(species_key).is_empty():
		return 0
	var p := clampi(points(species_key) + amount, 0, MAX)
	GameState.set_pokemon_flag(species_key, "affection", p)
	return p


static func set_points(species_key: String, p: int) -> void:
	if species_key == "" or GameState.get_pokemon_flags(species_key).is_empty():
		return
	GameState.set_pokemon_flag(species_key, "affection", clampi(p, 0, MAX))


# ---- time spent following you ---------------------------------------------------

## The game's own running clock in hours: day 1 8am = 8, day 2 9:30am = 33.5. Only grows.
static func now_hours() -> float:
	return float(GameState.get_date() - 1) * 24.0 + GameState.clock_hours()


## Starts counting hours for `species_key` from now (it has just started following you,
## or you have just woken up). Its flag "affection_clock" holds the hour last credited.
static func start_clock(species_key: String) -> void:
	if species_key == "" or GameState.get_pokemon_flags(species_key).is_empty():
		return
	GameState.set_pokemon_flag(species_key, "affection_clock", now_hours())


## Credits the follower with every WHOLE hour since it was last credited; the part-hour is
## kept for next time. Safe to call as often as you like.
static func credit_hours() -> void:
	var follower := GameState.get_follower()
	if follower == "":
		return
	var flags := GameState.get_pokemon_flags(follower)
	if flags.is_empty():
		return
	if not flags.has("affection_clock"):
		start_clock(follower)
		return
	var since := float(flags["affection_clock"])
	var whole := int(floor(now_hours() - since))
	if whole <= 0:
		if whole < 0:
			start_clock(follower)   # the clock went backwards (a debug time jump): start again
		return
	add(follower, whole * GAIN_PER_HOUR)
	GameState.set_pokemon_flag(follower, "affection_clock", since + float(whole))


## A match you WON with it following you: GAIN_PER_PRIZE per prize card you took.
## Also counts the win on it (flag "wins": matches won with it following you - kept for the
## "win X battles" evolutions).
static func on_match_won(prizes_taken: int) -> void:
	var follower := GameState.get_follower()
	if follower == "" or GameState.get_pokemon_flags(follower).is_empty():
		return
	GameState.bump_pokemon_flag(follower, "wins")
	if prizes_taken > 0:
		add(follower, prizes_taken * GAIN_PER_PRIZE)


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
