class_name PokemonSwingingBug
extends OverworldPokemon

## SWINGING BUG template -- Spinarak, Kakuna, Burmy... Dangles from a strand of silk
## at its spawn point, facing one way (no turning, no walk cycle), and sways through a
## slow shallow U: down-and-right to the bottom of the arc, up-and-right to the top,
## then back the same way. No collision.

# ---- tweakables -------------------------------------------------------------
const Z := 25
## The one direction it faces for as long as it hangs there.
const FACING := "down"
## Half-width of the sway, and how far the middle of the U dips, in world pixels.
const SWAY_PIXELS := 1.0
## Seconds for one full swing there and back.
const SWAY_PERIOD := 10.0
## Silk strand drawn from the top of the sprite upwards. 0 hides it.
const SILK_LENGTH := 5.0
const SILK_COLOUR := Color(1, 1, 1, 0.55)
const SILK_WIDTH := 0.5
# -----------------------------------------------------------------------------

var _anchor: Vector2
var _time: float = 0.0


func _template_ready() -> void:
	z_as_relative = false
	z_index = Z
	animating = false
	_anchor = global_position
	# Start somewhere random in the swing so neighbouring bugs don't sway in step.
	_time = randf() * SWAY_PERIOD
	set_facing(FACING)
	_update_sway()


func _template_process(delta: float) -> void:
	_time += delta
	_update_sway()


## s runs -1..1 across the swing; the height is 0 at both ends and SWAY_PIXELS at
## the middle, which traces the U. Snapped to whole pixels so the art stays crisp.
func _update_sway() -> void:
	var s := sin(TAU * _time / SWAY_PERIOD)
	var offset := Vector2(SWAY_PIXELS * s, SWAY_PIXELS * (1.0 - s * s))
	var next := (_anchor + offset).round()
	if next != global_position:
		global_position = next
		queue_redraw()


## The strand hangs from a fixed point above the middle of the swing to the top of
## the art, so it leans as the bug sways. Drawn before the sprite child, i.e. behind.
func _draw() -> void:
	if SILK_LENGTH <= 0.0:
		return
	var art_top_local: float = (-cell.y * 0.5 + art_top) * draw_scale()
	var pivot_local: Vector2 = to_local(_anchor + Vector2(0, art_top_local - SILK_LENGTH))
	draw_line(pivot_local, Vector2(0, art_top_local), SILK_COLOUR, SILK_WIDTH)
