class_name FishingZone
extends Area2D

## ============================================================
## FISHING AREAS -- attached to a "FishingAreas" Area2D node
## ============================================================
## Each RectangleShape2D CollisionShape2D child of this node is a spot the player can
## fish from. The shape's NAME carries the direction the WATER lies in:
##
##   Fish_Down      water is below the player -- they end up facing down
##   Fish_Left_2    water is to the left; the _2 only keeps the node name unique
##
## Pressing Space/Enter while standing inside one starts the cast.
##
## Shaped after Interactables_Script.gd, which does the same named-shape lookup for
## signs and the bed. Do NOT overlap a fishing rect with an interactable rect on the same
## map: both listen on _unhandled_input and the winner is decided by tree order.
## ============================================================

const NAME_PREFIX := "Fish_"

var _player: Node2D = null


func _ready() -> void:
	# Purely a lookup table of rectangles -- it never needs to detect anything itself.
	monitoring = false
	monitorable = false
	_player = get_parent().get_node_or_null("Player") as Node2D


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	# A dialog owns the press while it is up.
	if MapManager.wants_message_input():
		return
	if _player == null or not is_instance_valid(_player) or not _player.can_move:
		return
	if not FishingData.player_has_rod():
		return
	var direction := direction_at(_player.global_position)
	if direction == "":
		return
	# Consume it so it can't also trigger an NPC or a sign behind us.
	get_viewport().set_input_as_handled()
	MapManager.start_fishing(direction)


## The water direction of the fishing rect the world point falls inside, or "" if it is
## not in one.
func direction_at(world_pos: Vector2) -> String:
	var local := to_local(world_pos)
	for child in get_children():
		if not (child is CollisionShape2D) or not (child.shape is RectangleShape2D):
			continue
		var rect_size: Vector2 = child.shape.size
		var rect := Rect2(child.position - rect_size / 2.0, rect_size)
		if rect.has_point(local):
			var direction := _direction_from_name(String(child.name))
			if direction != "":
				return direction
			push_warning("FishingZone: '%s' has no direction in its name (expected e.g. %sDown)"
					% [child.name, NAME_PREFIX])
	return ""


## "Fish_Left_2" -> "left". Returns "" for a name that doesn't parse.
static func _direction_from_name(shape_name: String) -> String:
	var rest := shape_name
	if rest.begins_with(NAME_PREFIX):
		rest = rest.substr(NAME_PREFIX.length())
	var word := rest.split("_")[0].to_lower()
	return word if word in OverworldPokemon.DIRECTIONS else ""
