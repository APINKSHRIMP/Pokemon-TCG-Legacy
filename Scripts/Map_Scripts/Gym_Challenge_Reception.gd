extends BaseMapScene

# ============================================================
# GYM CHALLENGE RECEPTION — interior
# Reached from Gym Plaza; leads onward to the Gym Challenge Hall.
# The base class auto-creates the OPPONENTS container at runtime
# since no such node exists in the .tscn.
#
# THE HALL DOOR. Gym Security 1 stands in front of it until the player pays the $100
# entry at Gym Receptionist 1 (MapManager npc_type "gym_registrar"), which needs the
# Medal of Elders. The door itself is locked by BaseMapScene._locked_door_text() until
# then too, so slipping past the guard changes nothing. Paying calls
# refresh_hall_access(), which walks the guard aside live -- his two spots and lines are
# the two rules in Gym_Challenge_Reception.json.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Gym_Challenge_Reception.tscn"
const GUARD_NAME := "Gym Security 1"
## TWEAKABLE: seconds the guard takes to step aside after the player pays.
const GUARD_STEP_ASIDE_TIME := 0.6


func get_scene_path() -> String:      return SCENE_PATH
func get_time_bgm() -> Dictionary:    return SoundManagerScript.TIME_BGM_GYM_PLAZA
func get_map_data_name() -> String: return "Gym_Challenge_Reception"

func _scene_setup():
	# If arriving from the plaza (not from the hall), flag the audience for partial regen
	if GameState.entering_from != "Gym_Challenge_Hall":
		GameState.progress["gym_challenge_audience_from_plaza"] = true


## Called by MapManager the moment the entry fee is paid: re-reads the guard's entry for
## right now (the flag has changed, so his rule has) and walks him to it.
func refresh_hall_access() -> void:
	var guard: Node2D = null
	for actor in get_tree().get_nodes_in_group("npcs"):
		if "npc_name" in actor and actor.npc_name == GUARD_NAME:
			guard = actor
			break
	if guard == null:
		return
	var cast: Dictionary = CharacterSchedule.cast_for(get_map_data_name(),
			GameState.get_date(), GameState.get_time(), MapManager.evaluate_condition)
	for entry: Dictionary in cast.get("npcs", []):
		if String(entry.get("name", "")) != GUARD_NAME:
			continue
		if not MapManager.evaluate_condition(entry.get("condition", {})):
			continue
		guard.meet_text = entry.get("meet_text", guard.meet_text)
		guard.repeat_text = entry.get("repeat_text", guard.repeat_text)
		guard.movement_pattern = entry.get("pattern", guard.movement_pattern)
		if entry.has("position"):
			var target := Vector2(entry["position"]["x"], entry["position"]["y"])
			var tween := guard.create_tween()
			tween.tween_property(guard, "position", target, GUARD_STEP_ASIDE_TIME)
			tween.tween_callback(func():
				if guard.has_method("resume_movement"):
					guard.resume_movement()
				if guard.has_method("_on_restore_facing"):
					guard._on_restore_facing())
		return
