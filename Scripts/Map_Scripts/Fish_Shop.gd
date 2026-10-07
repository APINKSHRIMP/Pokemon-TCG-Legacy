extends BaseMapScene

## The Fish Shop interior, off the Celeste Harbour road. A mart-shaped room: a counter
## with a shopkeeper behind it and aquariums along the walls (their fish come from
## Pokemon/Spawns/Fish_Shop.json -- see the fish_tank spawn template).
##
## Who is behind the counter is Olly or Alexander on an 8-day rota that loops with
## Celeste Harbour's calendar -- see NPC_and_Opponent_Data/Characters/Fish_Shop.json.
## What they say is FishShopDialogue. The first visit ever plays Olly's opening scene
## (FishShopIntroCutscene).

const SCENE_PATH = "res://Scenes/Map_Scenes/Fish_Shop.tscn"

## The downstairs is closed off (tiles + collision) until Verdant Forest opens.
const DOWNSTAIRS_BLOCK := "MART/DownstairsBlock"

func get_scene_path() -> String:      return SCENE_PATH
func get_bgm_path() -> String:        return SoundManagerScript.BGM_FISH_SHOP
func get_map_data_name() -> String: return "Fish_Shop"


func _ready() -> void:
	# A cutscene that is about to take over must not give the player a frame or two of
	# free movement while the room fades in.
	var intro_due := FishShopIntroCutscene.should_run()
	if intro_due:
		_player.lock_movement()
	await super._ready()
	if intro_due:
		var cutscene := FishShopIntroCutscene.new()
		cutscene.install(self)
		cutscene.run()


## Reads the REAL date, like Celeste_Harbour.apply_permanent_unlocks: once open it
## stays open, whatever day the calendar loop resolves to.
##
## Then the shop grows with the fish sent to it: FishShopFloor keeps the Interior_<N>s
## the player has reached (0 always, 25 and 75 added on top, 100 replacing them all),
## drops CollisionToRemove once one above 0 is open, and fills the tanks.
func _scene_setup() -> void:
	if GameState.get_date() >= FishShopDialogue.VERDANT_OPEN_DATE and has_node(DOWNSTAIRS_BLOCK):
		get_node(DOWNSTAIRS_BLOCK).queue_free()
	FishShopFloor.setup(self, get_map_data_name())
