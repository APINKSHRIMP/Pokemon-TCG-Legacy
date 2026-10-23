extends BaseMapScene

## The Celeste Harbour Card Mart interior. The shopkeeper's opening week lives in
## Shopkeeper_Script.gd; Ellie and Alexander's day-2 visit in Card_Mart_Duo_Cutscene.gd.

const SCENE_PATH = "res://Scenes/Map_Scenes/Card_Mart.tscn"


func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_SHOP_1
func get_map_data_name() -> String: return "Card_Mart"


func _ready() -> void:
	await super._ready()
	# Back from the pack screen with Ellie and Alexander still in: their pull chat.
	if CardMartDuoCutscene.bonus_due():
		var cs := CardMartDuoCutscene.new()
		cs.install(self)
		cs.run()
