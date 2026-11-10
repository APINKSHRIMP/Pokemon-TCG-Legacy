extends BaseMapScene

## The Celeste Harbour Town Hall interior. Home of the three Card Elders, who stand in
## front of the three card mats along the top wall, with their spectators gathered
## round. The Card Elder Challenge starts on day 4 (busy Morning/Afternoon, battling
## from the Evening); the whole cast lives in NPC_and_Opponent_Data/Characters/TownHall.json.
##
## THE STAIRS. Three states, read from two story flags:
##   Gym Challenge not complete -> rope shown, stair collision ("Stand") on.
##   Complete, not a club member -> rope gone, collision still on, the Town Hall Security
##                                  guard stands in front of the stairs.
##   Club member                 -> rope gone, collision off, guard beside the stairs.
## refresh_club_access() is called again by MapManager the moment membership is paid for,
## so the guard steps aside without the player having to leave and come back.
##
## THE CROWD. adjust_cast() hands each slot's cast to TownHallCrowd before it spawns: one
## Elder is busy with a challenger, nobody spawns on the player. See Town_Hall_Crowd.gd.
## Beating the third Elder grants the Medal of Elders; its notice is shown from here.

const SCENE_PATH = "res://Scenes/Map_Scenes/TownHall.tscn"
const GUARD_NAME := "Town Hall Security"
## TWEAKABLE: seconds the guard takes to step aside after the player pays.
const GUARD_STEP_ASIDE_TIME := 0.6

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_TOWN_HALL
func get_map_data_name() -> String:   return "TownHall"


func _scene_setup() -> void:
	refresh_club_access(false)
	_announce_medal_of_elders()   # runs on; waits for the way back from the match


## MapManager hands the slot's cast over before spawning it: TownHallCrowd puts Elders in
## matches with challengers and keeps everyone off the player.
func adjust_cast(cast: Dictionary) -> Dictionary:
	var player_pos = null
	var container := _get_opponents_container()
	if _player != null and container != null:
		player_pos = container.to_local(_player.global_position)
	return TownHallCrowd.apply(cast, GameState.get_date(), GameState.get_time(), player_pos)


## TWEAKABLE: pause after the match-return overlay clears before the medal notice.
const MEDAL_NOTICE_DELAY := 0.4

## The third Card Elder has just been beaten (GameState.mark_opponent_beaten granted the
## medal): "You received the Medal of Elders", once anything already on screen is read.
func _announce_medal_of_elders() -> void:
	if not GameState.has_flag(GameState.MEDAL_OF_ELDERS_UNSEEN):
		return
	await get_tree().process_frame
	while MatchTransition.is_returning():
		await get_tree().process_frame
	await get_tree().create_timer(MEDAL_NOTICE_DELAY).timeout
	while MapManager.message_panel != null and is_instance_valid(MapManager.message_panel) \
			and MapManager.message_panel.visible:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	GameState.set_flag(GameState.MEDAL_OF_ELDERS_UNSEEN, false)
	SoundManagerScript.play_sfx(SoundManagerScript.SFX_gift_received)
	MapManager._show_large_message_with_ok("You received the " + GameState.MEDAL_OF_ELDERS_LABEL)


## Rope, stair collision and (when `animate_guard`) the guard's spot, from the flags.
func refresh_club_access(animate_guard: bool = true) -> void:
	var gym_done := GameState.has_flag(GameState.GYM_CHALLENGE_COMPLETE_FLAG)
	var member := GameState.has_flag(GameState.TOWN_HALL_CLUB_FLAG)
	var rope := get_node_or_null("Tile_Maps/Rope") as CanvasItem
	if rope != null:
		rope.visible = not gym_done
	var stair_block := get_node_or_null("Collision/Stand") as CollisionShape2D
	if stair_block != null:
		stair_block.set_deferred("disabled", member)
	if animate_guard:
		_move_guard_to_schedule()


## Re-reads the guard's entry for right now (the flags have changed, so his rule has) and
## walks him to it, taking his new lines and facing with him.
func _move_guard_to_schedule() -> void:
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
