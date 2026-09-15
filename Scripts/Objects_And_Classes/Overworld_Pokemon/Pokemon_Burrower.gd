class_name PokemonBurrower
extends OverworldPokemon

## BURYING template -- Diglett, Dugtrio, Sandygast. The spawn point is the patch of
## ground it comes out of. It pops up fast, one row of pixels at a time from the
## top of its head down, rising a pixel per row so it looks pushed up through the
## floor, with a burst of dirt/sand pixels. It looks around for its up time, then
## goes back down the same way -- bottom row first -- with another burst.
##
## Up time: the spawn point's `up_time` if set, else the species' `up_time` in the
## registry, else DEFAULT_UP_TIME. Particle colour: the species' `particle_colour`.

# ---- tweakables -------------------------------------------------------------
const Z := 1
## Seconds to fully appear / disappear.
const RISE_TIME := 0.2
const SINK_TIME := 0.2
const DEFAULT_UP_TIME := 5.0
## Seconds between glances while up.
const LOOK_MIN := 1.2
const LOOK_MAX := 2.8
const DEFAULT_PARTICLE_COLOUR := Color8(122, 82, 48)
const PARTICLE_COUNT := 16
# -----------------------------------------------------------------------------

enum Phase { RISING, UP, SINKING }

var _phase: int = Phase.RISING
var _time: float = 0.0
var _up_time: float = DEFAULT_UP_TIME
var _look_timer: float = 0.0


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	animating = false
	var point_up := float(spawn_point.get("up_time", 0))
	var species_up := float(species_data.get("up_time", 0))
	_up_time = point_up if point_up > 0.0 else (species_up if species_up > 0.0 else DEFAULT_UP_TIME)
	set_facing("down")
	set_clip_rows(0)
	_burst()


func _template_process(delta: float) -> void:
	_time += delta
	match _phase:
		Phase.RISING:
			var t := clampf(_time / RISE_TIME, 0.0, 1.0)
			set_clip_rows(ceili(art_height() * t))
			if t >= 1.0:
				_phase = Phase.UP
				_time = 0.0
				_look_timer = randf_range(LOOK_MIN, LOOK_MAX)
		Phase.UP:
			_look_timer -= delta
			if _look_timer <= 0.0:
				_look_timer = randf_range(LOOK_MIN, LOOK_MAX)
				set_facing(DIRECTIONS[randi() % DIRECTIONS.size()])
			if _time >= _up_time:
				_phase = Phase.SINKING
				_time = 0.0
				set_facing("down")
				_burst()
		Phase.SINKING:
			var t := clampf(_time / SINK_TIME, 0.0, 1.0)
			set_clip_rows(ceili(art_height() * (1.0 - t)))
			if t >= 1.0:
				despawn()


func _burst() -> void:
	var base := particle_colour(DEFAULT_PARTICLE_COLOUR)
	var width := cell.x * draw_scale() * 0.5
	PixelBurst.fire(get_parent(), global_position,
			[base, base.darkened(0.25), base.lightened(0.15)], PARTICLE_COUNT, 1.0, width, Z + 1)
