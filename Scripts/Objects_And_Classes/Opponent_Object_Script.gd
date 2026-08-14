extends WorldObjectBase

# ============================================================
# OPPONENT NPC
# ============================================================

var opponent_name: String = ""
var music: String = ""
var deck: String = ""
var prize_cards: int = 6
var meet_text: String = ""
var repeat_text: String = ""
var first_win_text: String = ""
var rematch_win_text: String = ""
var loss_text: String = ""
var coin_reward: String = ""
var cash_reward: String = ""

# Message box colour theme for this opponent — a key from MessageBoxTheme.THEMES, set on their
# entry in All_NPC_Constant_Data.json. Empty falls back to MessageBoxTheme.DEFAULT_THEME.
var message_colour: String = ""

# Deck restrictions block (optional). Schema documented in
# Deck_Validation_Helper.gd. Empty dict = no restrictions.
var restrictions: Dictionary = {}

# Match-wide rule modifiers block (optional). Schema documented in
# Match_Effects.gd. Empty array = no special rules.
var match_effects: Array = []

# Optional. When non-empty the opponent is a multi-game series —
# intermediate games skip the outro and bounce back to the intro,
# only the deciding game shows rewards / loss flavour.
# Currently supported: "best_of_3"
var match_format: String = ""
var sleeve: String = ""

func _ready():
	add_to_group("opponents")
	super._ready()

func _get_bubble_texture() -> Texture2D:
	if GameState.has_beaten_opponent(opponent_name):
		return load("res://Image_Assets/Icons/Message_Icons/old_battle.png")
	else:
		return load("res://Image_Assets/Icons/Message_Icons/new_battle.png")

# Body text only. The name, deck and prize count used to be baked into this
# string; they are now info chips above the message box (see
# MapManager._actor_chips), so the label carries nothing but what the
# opponent actually says.
func get_greeting_text() -> String:
	return repeat_text if GameState.has_beaten_opponent(opponent_name) else meet_text

func get_result_text(player_won: bool) -> String:
	if player_won:
		return first_win_text if not GameState.has_beaten_opponent(opponent_name) else rematch_win_text
	return loss_text
