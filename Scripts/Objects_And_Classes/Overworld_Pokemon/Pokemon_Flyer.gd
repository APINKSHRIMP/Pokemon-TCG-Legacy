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
## Each flyer in a group gets its own speed within +/- this fraction, so a flock
## loosens out rather than moving as one rigid block.
const SPEED_VARIANCE := 0.12
## Drawn above tree canopies (z 10-20) and everything else on the map.
const Z := 60
## Seconds per facing while spinning.
const SPIN_STEP := 0.3
const SPIN_ORDER := ["down", "left", "up", "right"]
# -----------------------------------------------------------------------------

## +1 flies right, -1 flies left. Set by the spawner before add_child().
var direction: float = 1.0
## Global x past which the flyer is gone. Set by the spawner.
var end_x: float = 0.0

var _speed: float = SPEED
var _spins: bool = false
var _spin_time: float = 0.0
var _spin_index: int = 0


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	_speed = SPEED * randf_range(1.0 - SPEED_VARIANCE, 1.0 + SPEED_VARIANCE)
	_spins = bool(species_data.get("spin", false))
	if _spins:
		_spin_index = randi() % SPIN_ORDER.size()
		set_facing(SPIN_ORDER[_spin_index])
	else:
		set_facing("right" if direction > 0.0 else "left")


func _template_process(delta: float) -> void:
	global_position.x += direction * _speed * delta
	if _spins:
		_spin_time += delta
		if _spin_time >= SPIN_STEP:
			_spin_time -= SPIN_STEP
			_spin_index = (_spin_index + 1) % SPIN_ORDER.size()
			set_facing(SPIN_ORDER[_spin_index])
	if (direction > 0.0 and global_position.x > end_x) \
			or (direction < 0.0 and global_position.x < end_x):
		despawn()
