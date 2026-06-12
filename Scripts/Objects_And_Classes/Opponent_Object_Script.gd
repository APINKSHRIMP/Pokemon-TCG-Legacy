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

func _ready():
	add_to_group("opponents")
	super._ready()

func _get_bubble_texture() -> Texture2D:
	if GameState.has_beaten_opponent(opponent_name):
		return load("res://image_assets/misc/old_battle.png")
	else:
		return load("res://image_assets/misc/new_battle.png")

func get_greeting_text() -> String:
	var body := repeat_text if GameState.has_beaten_opponent(opponent_name) else meet_text
	# Pre-battle prompt includes a deck/prize-cards footer so the player knows
	# what they're up against. The post-battle result text (get_result_text)
	# intentionally omits this — by then the match is over.
	return "[font_size=27][b]%s:[/b][/font_size]\n%s\n[font_size=8] [/font_size]\n[font_size=17][b](%s | %d prize cards)[/b][/font_size]" % [opponent_name, body, deck, prize_cards]

func get_result_text(player_won: bool) -> String:
	var raw: String
	if player_won:
		raw = first_win_text if not GameState.has_beaten_opponent(opponent_name) else rematch_win_text
	else:
		raw = loss_text
	return "[b]%s:[/b] %s" % [opponent_name, raw]
