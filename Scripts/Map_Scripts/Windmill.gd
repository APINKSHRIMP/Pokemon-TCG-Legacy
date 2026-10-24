extends BaseMapScene

# ============================================================
# WINDMILL — secret interior
# ============================================================
# Reached through the hidden entrance in Verdant Forest. A single-room interior
# holding one secret opponent, Mewtwo, who is there whenever the player finds the
# way in (NPC_and_Opponent_Data/Characters/Windmill.json).
#
# The moment the player is back from beating him he says one word -- "MEW" -- and
# vanishes, raising VANISHED_FLAG, which keeps him out of the room for good (his entry
# requires it unset). Quit before that plays and he is still standing there next time,
# with a talk bubble: talking to him plays it instead.
# ============================================================

const SCENE_PATH = "res://Scenes/Map_Scenes/Windmill.tscn"

const MEWTWO_NAME := "Mewtwo"
const VANISHED_FLAG := "mewtwo_vanished"
const LAST_WORD := "MEW"
const TALK_BUBBLE := "res://Image_Assets/Icons/Message_Icons/new_talk.png"

# TWEAKABLE — the vanish: he flares white, squeezes into a thin line and is gone.
const VANISH_PAUSE := 0.4      # after the box closes, before he starts to go
const VANISH_FLASH := 0.25     # flare up to white
const VANISH_SQUEEZE := 0.35   # narrow to nothing
const VANISH_STRETCH := 1.6    # how tall the line gets as he narrows
const AFTER_BATTLE_PAUSE := 0.8   # back from beating him: the beat before "MEW"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_CALM_BATTLE_2
func get_map_data_name() -> String: return "Windmill"


func _ready() -> void:
	# Read before super._ready(): MapManager.initialise() consumes the battle-return flag.
	var back_from_mewtwo: bool = GameState.returning_from_battle and GameState.current_opponent_name == MEWTWO_NAME
	if back_from_mewtwo:
		_player.lock_movement()
	await super._ready()
	if not GameState.has_beaten_opponent(MEWTWO_NAME) or GameState.has_flag(VANISHED_FLAG):
		if back_from_mewtwo:
			_player.unlock_movement()   # he won: nothing more happens
		return
	var mewtwo := _find_mewtwo()
	if mewtwo == null:
		_player.unlock_movement()
		return
	mewtwo.bubble_override = load(TALK_BUBBLE)
	# Talking to him also does it -- the way back if the player quit before it played.
	MapManager.opponent_interact_overrides[MEWTWO_NAME] = func(opponent: Node) -> void:
		_say_last_word(opponent)
	if back_from_mewtwo:
		# Straight after the win: let the map fade in and any post-battle line close first.
		await get_tree().create_timer(AFTER_BATTLE_PAUSE).timeout
		while is_inside_tree() and MapManager.message_panel != null and is_instance_valid(MapManager.message_panel) \
				and MapManager.message_panel.visible:
			await get_tree().process_frame
		if is_inside_tree() and is_instance_valid(mewtwo) and not GameState.has_flag(VANISHED_FLAG):
			mewtwo.pause_and_face(_player.global_position)
			_say_last_word(mewtwo)


func _say_last_word(mewtwo: Node2D) -> void:
	var cs := Cutscene.new()
	cs.install(self)
	var speaker := cs.speaker_for(MEWTWO_NAME)
	speaker["node"] = mewtwo
	await cs.say(speaker, LAST_WORD)
	cs.close_box()
	# Raised before he goes: a quit mid-vanish must not bring him back.
	GameState.set_flag(VANISHED_FLAG)
	MapManager.opponent_interact_overrides.erase(MEWTWO_NAME)
	await cs.wait(VANISH_PAUSE)
	if is_instance_valid(mewtwo):
		mewtwo.hide_bubble()
		var tween := create_tween()
		tween.tween_property(mewtwo, "modulate", Color(4.0, 4.0, 4.0, 1.0), VANISH_FLASH)
		tween.tween_property(mewtwo, "scale", Vector2(0.0, VANISH_STRETCH), VANISH_SQUEEZE) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		await tween.finished
		if is_instance_valid(mewtwo):
			mewtwo.queue_free()
	cs.finish()


func _find_mewtwo() -> Node2D:
	for n in get_tree().get_nodes_in_group("opponents"):
		if is_instance_valid(n) and str(n.get("opponent_name")) == MEWTWO_NAME:
			return n as Node2D
	return null
