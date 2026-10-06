class_name SpeechEmote
extends Sprite2D

## A "!" or "?" popping up over a character's head for about a second, with its sound --
## the beat BEFORE a line ("[!]Oh, it's you!") or AFTER one ("See you around.[?]").
## Never shown alongside a message: the caller takes the box down first.
##
##   await SpeechEmote.play(npc, "!")
##
## Written into dialogue as a tag at the very START or very END of a line; MapManager
## strips the tag and plays this (see MapManager.split_emote_tags). Works on anything
## with a global_position -- an overworld NPC or opponent, a CutsceneActor.

const ICONS := {
	"!": "res://Image_Assets/Icons/Message_Icons/exclamation.png",
	"?": "res://Image_Assets/Icons/Message_Icons/Question.png",
}
const SOUNDS := {
	"!": "res://Audio/SFX/Exclamation.ogg",
	"?": "res://Audio/SFX/Question.ogg",
}

## TWEAKABLE -- world px and seconds.
const Y_OFFSET := -19.0     ## same spot as the talk bubble (WorldObjectBase.BUBBLE_Y_OFFSET)
const POP_TIME := 0.12      ## scale 0 -> POP_OVERSHOOT -> 1
const POP_OVERSHOOT := 1.35
const HOLD_TIME := 0.75
const FADE_TIME := 0.15
const RISE := 2.0           ## drifts up this much while it holds
const Z := 101              ## just over the talk bubble


## Plays the emote over `target` and returns when it has gone. `kind` is "!" or "?".
static func play(target: Node2D, kind: String) -> void:
	if target == null or not is_instance_valid(target) or not ICONS.has(kind):
		return
	var emote := SpeechEmote.new()
	emote.texture = load(ICONS[kind])
	emote.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emote.z_index = Z
	emote.position = Vector2(0.0, Y_OFFSET)
	emote.scale = Vector2.ZERO
	# The talk bubble sits in exactly this spot; it steps aside for the beat.
	var bubble_was: bool = false
	var bubble: Sprite2D = null
	if "_bubble_sprite" in target:
		bubble = target.get("_bubble_sprite") as Sprite2D
	if bubble != null and is_instance_valid(bubble):
		bubble_was = bubble.visible
		bubble.visible = false
	target.add_child(emote)
	if ResourceLoader.exists(SOUNDS[kind]):
		SoundManagerScript.play_sfx_from_path(SOUNDS[kind])

	var tw := emote.create_tween()
	tw.tween_property(emote, "scale", Vector2.ONE * POP_OVERSHOOT, POP_TIME * 0.6)
	tw.tween_property(emote, "scale", Vector2.ONE, POP_TIME * 0.4)
	tw.tween_property(emote, "position:y", Y_OFFSET - RISE, HOLD_TIME)
	tw.tween_property(emote, "modulate:a", 0.0, FADE_TIME)
	# A tree timer, not the tween: if the speaker is freed mid-beat (a map change) the
	# tween dies with it and would never report finished.
	await target.get_tree().create_timer(POP_TIME + HOLD_TIME + FADE_TIME).timeout
	if is_instance_valid(emote):
		emote.queue_free()
	if bubble_was and bubble != null and is_instance_valid(bubble):
		bubble.visible = true
