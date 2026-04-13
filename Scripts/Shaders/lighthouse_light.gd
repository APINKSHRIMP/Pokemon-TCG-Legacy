extends Node2D

@export var rotation_speed: float = 0.6
@export var sweep_degrees: float = 120.0
@export var center_angle: float = 0.0

func _process(delta: float) -> void:
	var sweep_radians := deg_to_rad(sweep_degrees / 2.0)
	var center_radians := deg_to_rad(center_angle)
	var offset := sin(Time.get_ticks_msec() / 1000.0 * rotation_speed) * sweep_radians
	$LighthouseCone.rotation = center_radians + offset
