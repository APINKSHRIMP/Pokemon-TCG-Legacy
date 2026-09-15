class_name PokemonFlyer
extends OverworldPokemon

## FLYER template -- Pidgey, Wingull, Swellow... Spawned by OverworldPokemonSpawner
## just off the left or right edge of the camera, flies straight across above
## everything (no collision), and despawns once it passes the far edge of the map.
## A species with `"spin": true` in the registry (the Hoppip line) cycles its facings
## as it goes, so it turns round and round while drifting across.

# ---- tweakables -------------------------------------------------------------
## World pixels per second. The map is ~7500px wide, so a full crossing is minutes.
const SPEED := 40.0
## Each FLOCK gets one speed within +/- this fraction of SPEED (the spawner rolls it
## once and hands it to every member, so a flock stays together).
const SPEED_VARIANCE := 0.12
## Drawn above tree canopies (z 10-20) and everything else on the map.
const Z := 60
## Seconds per facing while spinning.
const SPIN_STEP := 0.3
const SPIN_ORDER := ["down", "left", "up", "right"]
## Ground shadow: a black copy of the current frame, offset down-right (sun from the
## top left). World pixels -- the overworld camera is zoomed 2.5x, so on screen it
## is 2.5x further.
const SHADOW_OFFSET := Vector2(50, 300)
const SHADOW_ALPHA := 0.2
## Just under tree canopies (z 10-20), so the shadow passes beneath them.
const SHADOW_Z := 9
## Up-and-down bob of the bird itself (the shadow stays level, which is what sells
## the height). World pixels of travel above/below the flight line, and seconds per
## full bob. Each bird starts at a random point so a flock doesn't bob in step.
const BOB_PIXELS := 3.0
const BOB_PERIOD := 1.2
# -----------------------------------------------------------------------------

## +1 flies right, -1 flies left. Set by the spawner before add_child().
var direction: float = 1.0
## Global x past which the flyer is gone. Set by the spawner.
var end_x: float = 0.0
## World pixels per second. The spawner sets one value for the whole flock; <= 0
## rolls a speed of its own.
var speed: float = 0.0

var _spins: bool = false
var _spin_time: float = 0.0
var _spin_index: int = 0
var _shadow: Sprite2D = null
var _bob_time: float = 0.0


static func roll_speed() -> float:
	return SPEED * randf_range(1.0 - SPEED_VARIANCE, 1.0 + SPEED_VARIANCE)


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	if speed <= 0.0:
		speed = roll_speed()
	_make_shadow()
	_bob_time = randf() * BOB_PERIOD
	_spins = bool(species_data.get("spin", false))
	if _spins:
		_spin_index = randi() % SPIN_ORDER.size()
		set_facing(SPIN_ORDER[_spin_index])
	else:
		set_facing("right" if direction > 0.0 else "left")


func _template_process(delta: float) -> void:
	global_position.x += direction * speed * delta
	if _spins:
		_spin_time += delta
		if _spin_time >= SPIN_STEP:
			_spin_time -= SPIN_STEP
			_spin_index = (_spin_index + 1) % SPIN_ORDER.size()
			set_facing(SPIN_ORDER[_spin_index])
	_bob(delta)
	_sync_shadow()
	if (direction > 0.0 and global_position.x > end_x) \
			or (direction < 0.0 and global_position.x < end_x):
		despawn()


## Moves only the sprite child, never the node, so the shadow child stays put. Runs
## every frame AFTER any set_facing(): _apply_region() resets sprite.position to zero
## whenever the frame changes. Rounded to whole pixels so the art stays crisp.
func _bob(delta: float) -> void:
	if sprite == null:
		return
	_bob_time += delta
	sprite.position.y = roundf(BOB_PIXELS * sin(TAU * _bob_time / BOB_PERIOD))


## modulate multiplies, so black at SHADOW_ALPHA turns every opaque pixel into a flat
## translucent black and leaves transparent pixels transparent.
func _make_shadow() -> void:
	_shadow = Sprite2D.new()
	_shadow.texture = sprite.texture
	_shadow.scale = sprite.scale
	_shadow.region_enabled = true
	_shadow.region_filter_clip_enabled = true
	_shadow.modulate = Color(0, 0, 0, SHADOW_ALPHA)
	_shadow.z_as_relative = false
	_shadow.z_index = SHADOW_Z
	_shadow.position = SHADOW_OFFSET
	add_child(_shadow)
	_sync_shadow()


## Mirrors whichever frame the sprite is showing (walk cycle and spin both change it).
func _sync_shadow() -> void:
	if _shadow != null and sprite != null:
		_shadow.region_rect = sprite.region_rect
