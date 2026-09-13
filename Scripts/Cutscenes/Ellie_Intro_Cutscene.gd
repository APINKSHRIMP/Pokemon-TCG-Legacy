class_name EllieIntroCutscene
extends Cutscene

# ============================================================
# ELLIE — THE FIRST MORNING
# ============================================================
# Day 1, the first time the player steps out of their own front door. Told in two
# halves, with the player free to walk between them, and a forced battle at the end.
#
#   ARRIVAL   Ellie runs in from the east, up to the door, hugs the player, and
#             talks. Ends by challenging them to a race to the pier.
#   DEPARTURE The player stands and watches her go, as they would in any Pokemon
#             game. Control comes back the moment she leaves the camera, and she
#             is quietly parked on her mark at the pier while off screen.
#   PIER      She is waiting whenever the player gets there. Then the catch-up
#             conversation, then the battle. Lose and it restarts until you win.
#   FAREWELL  After the win, she says goodbye and runs back up the path.
#
# The departure was once an actual playable race, with her shoving past a player
# who got in the way. It was a nice idea and it was not fun: it hinges on the
# player guessing that Shift makes them fast enough, and every way of losing it
# ends with them walking the whole pier alone anyway. The shove itself survives as
# CutsceneActor.shove_player for whenever something does want it.
#
# WHERE THE COORDINATES CAME FROM
# -------------------------------
# The two routes were drawn over a screenshot of the map. Every point below is a
# corner of those drawings converted to world space, and they are anchored on
# things already in the data, so they can be sanity-checked rather than trusted:
# the house door spawn is Celeste_Harbour.SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS
# (-597, 1473), the lighthouse maintenance NPC stands at (-800, 2620), and the
# pier-end spot is where Ellie's own entry in the character file put her.
#
# You can draw either route in the editor instead: add a Line2D named
# ELLIE_RUN_PATH_NODE anywhere in Celeste_Harbour.tscn and its points win over
# RUN_PATH below. Same for the trigger zone -- an Area2D (with a rectangle shape), a
# CollisionShape2D or a bare Node2D named PLAYER_END_ZONE_NODE replaces the
# fallback rectangle. (The EllieEnd node in the scene is left over from the race
# and is no longer read by anything.)
# ============================================================

# ------------------------------------------------------------
# STAGE — survives the trip through the battle scene
# ------------------------------------------------------------
# The forced battle unloads the map, and with it this object, so the point the
# cutscene had reached has to live in the save. The map script reads stage() on
# load and calls run() which routes back to the right half.
const STAGE_KEY    := "ellie_intro_stage"
const STAGE_NONE   := ""        # never started
const STAGE_FOLLOW := "follow"  # arrival done; she is waiting at the pier
const STAGE_BATTLE := "battle"  # sent into the match; waiting on the result
const STAGE_DONE   := "done"    # finished, never plays again

const OPPONENT_NAME := "Ellie"
const SPRITE_NAME   := "0Ellie"
const MAP_NAME      := "Celeste_Harbour"

# ------------------------------------------------------------
# TWEAKABLE — speeds, in px/sec
# ------------------------------------------------------------
const ARRIVAL_SPEED   : float = 190.0   # Ellie belting up the street
# She runs off at a jog rather than a sprint -- the player is standing still
# watching her, so this is paced to be watched, not to be chased.
const DEPART_SPEED    : float = 160.0
# How far straight down she runs before she is hidden. Only has to beat
# OFFSCREEN_MARGIN_Y measured from where she is standing (the player's position
# plus PLAYER_STEP_OUT plus HUG_GAP), with room to spare -- she never reaches the
# end of it, because _check_exit() stops her the moment she is out of shot.
const DEPART_RUN_DOWN : float = 220.0
const FAREWELL_SPEED  : float = 150.0
# How she leaves the pier -- see _farewell_route(). CORNERS is how many legs of the
# route home she actually walks (up off the pier, then west clear of the
# lighthouse); RUN_UP is the straight northward run after that, which only has to
# outlast OFFSCREEN_MARGIN_Y since she is stopped the moment she is out of shot.
const FAREWELL_ROUTE_CORNERS: int   = 2
const FAREWELL_RUN_UP       : float = 240.0
# The lean in, and the step back out. Slow, but not SO slow that it stops reading
# as a hug -- at half this it was a lingering drift into the player's face.
const HUG_SPEED       : float = 28.0

# ------------------------------------------------------------
# TWEAKABLE — the arrival
# ------------------------------------------------------------
# The upper of the two paths outside the player's house, which is the one she runs
# in along. She starts this far east of the player: the camera shows about 384px
# either side at its 2.5x zoom, so this is comfortably off screen.
const ARRIVAL_PATH_Y  : float = 1685.0
const ARRIVAL_START_DX: float = 560.0

# The player is walked this far down off the doorstep as she comes in, and she
# stops relative to WHERE THEY END UP, so the whole meeting moves down with them.
#
# This exists for the CAMERA, not the choreography. The camera is centred on the
# player and shows ~216px below them at its 2.5x zoom, so standing on the doorstep
# puts the path she arrives along right on the bottom edge of the screen — she
# would run most of the way in off screen. Stepping the player out first buys the
# view the room to see her coming. Raising ARRIVAL_PATH_Y instead was the obvious
# fix and the wrong one: it walks her off the path and into the garden wall.
const PLAYER_STEP_OUT      : float = 30.0
const PLAYER_STEP_OUT_SPEED: float = 55.0
# A beat on the doorstep before they move, so the scene does not start on a jolt
# the instant the map has faded in.
const STEP_OUT_DELAY       : float = 0.5

# How far below the player she pulls up. This is also the gap she talks across, and
# it has to leave daylight between the two collision boxes (hers is 18x25, the
# player's 16x23, both offset ~2px down) or she shunts them into the doorway the
# moment she sets off running.
const HUG_GAP         : float = 25.0
const HUG_CLOSE       : float = 12.0    # and how far she leans in from there
# ...and this far to the side as she does it, folded into the same move so she
# leans in on a slight diagonal. Squaring straight up to the player put the two
# sprites nose to nose, which did not read as a hug.
const HUG_SIDE_STEP   : float = 4.0
const HUG_HOLD        : float = 0.5     # the hug itself, before she steps back out

# ------------------------------------------------------------
# TWEAKABLE — the route she runs
# ------------------------------------------------------------
# Down from the door, west onto the crossing, over the road, west again before the
# sunflower planter, south to the lighthouse, around the maintenance NPC standing
# there (west, south, east) and out to the end of the pier.
const RUN_PATH: Array = [
	Vector2(-592.0, 1700.0),   # down off the doorstep to the top path
	Vector2(-712.0, 1700.0),   # west to the pedestrian crossing
	Vector2(-712.0, 2151.0),   # south over the road and down the path
	Vector2(-791.0, 2151.0),   # west, just before the sunflower planter
	Vector2(-791.0, 2569.0),   # south to ~50px above the lighthouse maintenance NPC
	Vector2(-839.0, 2569.0),   # west, around him
	Vector2(-839.0, 2690.0),   # south, past him
	Vector2(-708.0, 2690.0),   # east, below the lighthouse
	Vector2(-708.0, 2737.0),   # south to the pier end, just above the fence
]

# Where the two of them end up standing. Ellie finishes wherever the route ends
# (so moving the drawn Line2D's last point moves her, and the post-battle respawn
# still lands on the same spot); the player draws up this far to her WEST, so that
# facing her is facing right -- see the farewell, where they look at each other.
const ELLIE_PIER_SPOT_FALLBACK := Vector2(-708.0, 2737.0)
const PLAYER_SIDE_OFFSET       := Vector2(-27.0, 0.0)

# How far short of the drawn route's last point she actually stops. See
# _pier_route(). The row of lamp posts along the pier end sits at y ~= 2738 and the
# drawn line runs to 2748, so this backs her onto the right side of the fence --
# and lands her on (-708, 2737), which is exactly where she was authored to stand
# in the character file before this was a cutscene. Raise it if she still clips.
const PIER_FINISH_INSET: float = 11.0

# Where the front door is, for trimming the drawn route -- it is drawn as one
# continuous line covering BOTH her run in and her run down, and only the second
# half is the race. Mirrors Celeste_Harbour.SPAWN_FROM_PLAYER_HOUSE_DOWNSTAIRS.
const DOOR_SPOT := Vector2(-597.0, 1473.0)

# ------------------------------------------------------------
# TWEAKABLE — trigger zones (see the header note on overriding these in-editor)
# ------------------------------------------------------------
const PLAYER_END_ZONE_NODE := "StartingCutsceneEnd"
const ELLIE_RUN_PATH_NODE  := "EllieRunPath"

# The pier end. Big enough that the player is inside it wherever they skid to a
# halt, small enough that it cannot be clipped on the way past.
const PLAYER_END_ZONE_FALLBACK := Rect2(-865.0, 2678.0, 250.0, 112.0)


# ------------------------------------------------------------
# TWEAKABLE — timings
# ------------------------------------------------------------
const PIER_SETTLE_PAUSE : float = 2.0   # the beat before she speaks, both facing out to sea
const LOOK_AWAY_PAUSE   : float = 2.0   # her pause mid-conversation before changing the subject
# After the match she is already looking at the player; she holds that, looks out
# to sea for a moment, then turns back and speaks.
const FAREWELL_PAUSE     : float = 1.0
const FAREWELL_LOOK_DOWN : float = 2.0
const TURN_BEAT         : float = 0.35  # box down, both of them turn, box back up
const REMATCH_PAUSE     : float = 0.8   # after a loss, before the match restarts

# Two corners count as square-on (needing no inserted corner) within this many
# pixels -- a drawn line is never pixel-exact, and an 8px drift over a 200px leg
# is invisible. See _enter_route().
const PATH_COLUMN_TOLERANCE: float = 8.0
# Standing this close to a corner counts as being ON it. See _drop_corners_before().
const PATH_SNAP_RADIUS: float = 45.0

# How far past the edge of the view she has to get before she is gone for good.
# The camera shows ~384x216 world px either side of the player at its 2.5x zoom, so
# the Y margin is that edge plus the rest of a sprite: at 216 only the top of her
# head is still showing, and ~18 more takes all of her with it. Any more than that
# and the player stands frozen watching an empty street.
const OFFSCREEN_MARGIN_X: float = 430.0
const OFFSCREEN_MARGIN_Y: float = 234.0

# ------------------------------------------------------------
# DIALOGUE
# ------------------------------------------------------------
const ARRIVAL_LINES: Array = [
	"Hey!!!",
	"I hope the move all went well? I kept an eye on the movers unloading and they seemed to do a good job so hopefully nothing is damaged.",
	"Nothing has changed here since you left but you did just miss a load of Sharpedo passing through the harbour",
	"The storm must have brought them here or something so police are keeping the beach closed for today just in case some are still lurking",
	"Verdant forest has been shut all week too so there's been nothing to do round here I've been so bored!",
	"The pier is still open so let's hang out there for a bit and catch up. I'll race you past the lighthouse!",
	"Last one to the end of the pier is a rotten exeggcute!",
]

# Said facing out to sea, before she turns round.
const PIER_OPENING_LINE := "I can't believe you actually ended up moving back after all these years, it's been so long"

const PIER_LINES_A: Array = [
	"Even Alexander has been asking about you, he was going to unload the moving van himself! He's been helping your dad keep the garden nice these past few months so if it's a mess you can blame him.",
	"Let me know when you plan on visiting your mum and dad and I'll come with you to see how they're doing... if that's okay!!",
]

const PIER_LINES_B: Array = [
	"I've been really getting back into the Pokemon card game recently just like everyone else. I think recently it's become even more popular than ever.",
	"Your mum mentioned that she found some of your old cards lying about, did you find them? Everyone around here plays the game so at least it's something to do while everything is shut this weekend.",
	"Oh haha, you've brought your cards out with you? Hey! In that case let's have a quick match.",
	"I'm sure you'll remember how to play, but I'll show you if you need a hand!",
	"Okay, let's get started",
]

const FAREWELL_LINES: Array = [
	"Just like old times hey, I said nothing has changed since you left. Well I'll leave you to it for now, I've gotta go and help Alexander with something and I'm already late.",
	"If you can't be bothered unpacking everything right now or got nothing better to do, most of the people round here are into cards and will play with you if you just ask them.",
	"You'll be able to tell when someone is looking for a match you can see it in their eyes!.",
	"They won't take it as easy on you as I did! I'll catch you in a bit and we can play another match if you get any better!.",
	"Ciao!",
]

# ------------------------------------------------------------
# STATE
# ------------------------------------------------------------
var _ellie: CutsceneActor = null
var _speaker: Dictionary = {}
var _player_zone: Rect2 = Rect2()

# What happens once she has run off the edge of the camera. Empty when she is not
# running off anywhere. See _on_exit_complete().
const WATCH_TO_PIER := "to_pier"   # hand control back; she waits at the pier
const WATCH_FINISH  := "finish"    # end the cutscene and free her
var _watching_exit: String = ""

# Set while she is stood at the pier and the player is free to walk down to her.
var _watching_pier: bool = false


# ============================================================
# STAGE HELPERS — the map script asks these before installing
# ============================================================

static func stage() -> String:
	return str(GameState.progress.get(STAGE_KEY, STAGE_NONE))

static func _set_stage(new_stage: String) -> void:
	GameState.progress[STAGE_KEY] = new_stage
	GameState.save_progress()

## True when this map load should hand over to the cutscene at all.
## `entering_from` is GameState.entering_from, which Base_Map_Scene clears during
## _ready() -- read it in _scene_setup(), which runs before that.
static func should_run(entering_from: String) -> bool:
	match stage():
		STAGE_DONE:
			return false
		STAGE_NONE:
			# The very first time the player walks out of their own front door.
			return entering_from == "Player_House_Downstairs"
		_:
			# Mid-cutscene: always resume, however the player got back here.
			return true


# ============================================================
# ENTRY POINT
# ============================================================

func run() -> void:
	_speaker = speaker_for(OPPONENT_NAME)
	_player_zone = zone_rect(PLAYER_END_ZONE_NODE, PLAYER_END_ZONE_FALLBACK)

	match stage():
		STAGE_NONE:
			await _play_arrival()
		STAGE_FOLLOW:
			# She ran off some time ago -- possibly several map loads ago. She is
			# simply waiting at the pier whenever the player turns up.
			_resume_at_pier()
		STAGE_BATTLE:
			await _handle_battle_result()
		_:
			finish()


# ============================================================
# ARRIVAL
# ============================================================

func _play_arrival() -> void:
	# Where the player will be standing by the time she gets here. Worked out up
	# front so her run can aim at it while they are still walking to it.
	var meet: Vector2 = player.global_position + Vector2(0.0, PLAYER_STEP_OUT)

	_ellie = spawn(OPPONENT_NAME, SPRITE_NAME,
		Vector2(meet.x + ARRIVAL_START_DX, ARRIVAL_PATH_Y), "left")

	# Both at once: she comes up the street while the player steps out of the
	# doorway. Her walk is deliberately NOT awaited here — awaiting the player's
	# short walk first is what makes the two overlap instead of queueing.
	# Physics walking for her, so she follows the path rather than the garden wall.
	_ellie.walk_path([
		Vector2(meet.x, ARRIVAL_PATH_Y),
		Vector2(meet.x, meet.y + HUG_GAP),
	], ARRIVAL_SPEED)

	await wait(STEP_OUT_DELAY)
	await player_walk_to(meet, PLAYER_STEP_OUT_SPEED, "down")
	player_face("down")

	if _ellie.is_walking():
		await _ellie.path_finished

	# The hug. Gliding, not walking: the two collision boxes are wider than the
	# gap being closed, so physics movement would jam against the player instead.
	# Both halves cycle the walk frames (CutsceneActor's no-sliding rule makes ten
	# pixels enough to show a step) -- it is a lean in and a step back, not a drift.
	await _ellie.glide_to(
		Vector2(meet.x - HUG_SIDE_STEP, meet.y + HUG_GAP - HUG_CLOSE), HUG_SPEED, "up")
	await wait(HUG_HOLD)
	# And back out again STILL FACING THE PLAYER -- facing is pinned to "up" so she
	# steps backwards rather than turning her back on them. The sidestep unwinds
	# here too, so she ends up square on for the conversation.
	await _ellie.glide_to(Vector2(meet.x, meet.y + HUG_GAP), HUG_SPEED, "up")

	await say_all(_speaker, ARRIVAL_LINES)
	close_box()

	_start_departure()


# ============================================================
# THE RACE
# ============================================================

func _start_departure() -> void:
	_set_stage(STAGE_FOLLOW)
	# STRAIGHT DOWN, not along the route. The route's first corner is at the top
	# path and turns west from there -- but by the time she reaches it only a few
	# pixels of her hair are still on screen, so the turn was a character pivoting
	# out of sight at the very bottom edge of the frame. She only has to leave the
	# picture; where she goes after that is nobody's business, and she is teleported
	# onto her mark at the pier the moment she is gone.
	_ellie.walk_path([
		_ellie.global_position + Vector2(0.0, DEPART_RUN_DOWN),
	], DEPART_SPEED)
	# Not awaited, and the player stays LOCKED: they stand and watch her go.
	# _check_exit() hands control back the moment she is off the camera.
	_watching_exit = WATCH_TO_PIER


# ------------------------------------------------------------
# THE ROUTE
# ------------------------------------------------------------
# The Line2D in the map is drawn as ONE continuous stroke covering both halves of
# her morning -- the run IN along the top path, and then the race back down. Only
# the second half is the route she races, so the drawn line is cut at the front
# door and everything before it thrown away. Without that she sets off from the
# player's doorstep by running diagonally back to where she first came on screen.

## The route as authored -- the Line2D in the map when there is one, RUN_PATH when
## there is not.
func _run_path() -> Array:
	return path_from_line(ELLIE_RUN_PATH_NODE, RUN_PATH)


## The canonical route: front door -> end of the pier.
##
## The drawn line's last point is a few pixels INTO the pier fence -- it is drawn
## as a route, and a route naturally gets drawn to the edge of the thing it ends
## at. Walked literally she grinds against the fence instead of arriving, and a
## restart mid-race respawned her standing inside it. So the final point is backed
## off by PIER_FINISH_INSET, which is also what the post-battle respawn and the
## player's spot beside her are measured from.
func _pier_route() -> Array:
	var route: Array = _drop_corners_before(_run_path(), DOOR_SPOT)
	if route.is_empty():
		return route
	var last: Vector2 = route[route.size() - 1]
	var pulled_back := Vector2(last.x, last.y - PIER_FINISH_INSET)
	# Never pull back past the corner before it -- that would reverse the last leg.
	if route.size() >= 2 and pulled_back.y <= (route[route.size() - 2] as Vector2).y:
		return route
	route[route.size() - 1] = pulled_back
	return route


## Enter `route` from wherever the walker actually is.
##
## Two corrections, and both matter every time this is used:
##   - corners already behind them are dropped, so they do not double back;
##   - if the first remaining corner is not square-on, a corner is inserted so the
##     first leg is straight. A character setting off diagonally across a path
##     reads as a pathfinding glitch even when the destination is right.
func _enter_route(route: Array, start: Vector2) -> Array:
	var trimmed: Array = _drop_corners_before(route, start)
	if trimmed.is_empty():
		return trimmed
	var first: Vector2 = trimmed[0]
	# Square up on whichever axis has the SMALLER error -- that is the one the
	# walker is already nearly aligned on, so the inserted corner is the short leg.
	if absf(first.x - start.x) > PATH_COLUMN_TOLERANCE \
			and absf(first.y - start.y) > PATH_COLUMN_TOLERANCE:
		if absf(first.x - start.x) < absf(first.y - start.y):
			trimmed.push_front(Vector2(first.x, start.y))
		else:
			trimmed.push_front(Vector2(start.x, first.y))
	return trimmed


## Everything from the corner nearest `from` onwards. The nearest corner itself is
## dropped too when the walker is effectively standing on it -- keeping it would
## mean a first "leg" of a couple of pixels, which is a stutter, not a step.
func _drop_corners_before(route: Array, from: Vector2) -> Array:
	var result: Array = route.duplicate()
	if result.size() < 2:
		return result
	var nearest: int = 0
	var nearest_d: float = INF
	for i in result.size():
		var d: float = (result[i] as Vector2).distance_to(from)
		if d < nearest_d:
			nearest_d = d
			nearest = i
	var cut: int = nearest + 1 if nearest_d <= PATH_SNAP_RADIUS else nearest
	cut = mini(cut, result.size() - 1)
	for _i in cut:
		result.pop_front()
	return result


func _ellie_pier_spot() -> Vector2:
	var route: Array = _pier_route()
	return route.back() if not route.is_empty() else ELLIE_PIER_SPOT_FALLBACK


func _player_pier_spot() -> Vector2:
	return _ellie_pier_spot() + PLAYER_SIDE_OFFSET


## How she leaves the pier: the first couple of corners of the route home, then
## straight up and out of shot.
##
## Unlike the departure she cannot simply walk north from where she stands -- the
## lighthouse is directly above her, which is the whole reason the drawn route
## hooks west in the first place. So she takes the legs that get her clear of it
## and nothing more. The drawn line jogs back EAST above the lighthouse and
## carries on; walking that far put a second, pointless-looking turn on screen,
## and she is out of the picture before any of it matters. The column she ends up
## running up (x ~= -827) is clear for well past the point she vanishes -- the
## nearest thing in it is a lamp post ~80px further north again.
func _farewell_route() -> Array:
	var route: Array = _pier_route()
	route.reverse()
	route = _enter_route(route, _ellie.global_position)
	var exit_path: Array = route.slice(0, FAREWELL_ROUTE_CORNERS)
	var last: Vector2 = exit_path.back() if not exit_path.is_empty() else _ellie.global_position
	exit_path.append(Vector2(last.x, last.y - FAREWELL_RUN_UP))
	return exit_path


## Resumed on a later map load: she got to the pier some time ago and is waiting.
func _resume_at_pier() -> void:
	_ellie = spawn(OPPONENT_NAME, SPRITE_NAME, _ellie_pier_spot(), "down")
	_watching_pier = true
	release_player()


func _process(_delta: float) -> void:
	if _watching_exit != "":
		_check_exit()
	elif _watching_pier:
		_check_pier()


# ------------------------------------------------------------
# WATCHING HER GO
# ------------------------------------------------------------
# Used by both exits -- off to the pier after the arrival, and off home after the
# battle. WATCH_* says what to do once she is gone, because the two differ only in
# that: one hands the player back their legs, the other ends the cutscene.

func _check_exit() -> void:
	if _ellie == null or not is_instance_valid(_ellie) or player == null:
		_on_exit_complete()
		return
	var offset: Vector2 = _ellie.global_position - player.global_position
	if absf(offset.x) < OFFSCREEN_MARGIN_X and absf(offset.y) < OFFSCREEN_MARGIN_Y:
		return
	_on_exit_complete()


func _on_exit_complete() -> void:
	var next: String = _watching_exit
	_watching_exit = ""

	if next == WATCH_FINISH:
		# finish() frees the actors it spawned, so she goes for good rather than
		# carrying on up the road behind the player for the rest of the morning.
		finish()
		return

	# She has run on ahead. Stop the walk and park her on her mark at the pier --
	# she is off camera, so the jump is never seen, and it means the player can
	# take as long as they like getting down there and she will be waiting.
	if _ellie != null and is_instance_valid(_ellie):
		_ellie.stop_walking()
		_ellie.global_position = _ellie_pier_spot()
		_ellie.face("down")
	_watching_pier = true
	release_player()


## The player reaching the pier end is the whole trigger now. Tested per-frame
## rather than with an area-entered signal, because on a resumed save they can
## already be standing inside the zone when it is armed, and "entered" never fires
## for someone who was never outside.
func _check_pier() -> void:
	if player == null or not is_instance_valid(player):
		return
	if not _player_zone.has_point(player.global_position):
		return
	_watching_pier = false
	_play_pier_meeting()


func _play_pier_meeting() -> void:
	reclaim_player()
	_ellie.shove_player = false
	_ellie.collision_mask = 1

	# She is already parked on her mark -- _on_exit_complete() put her there while
	# she was off camera. Re-asserting it is cheap insurance against her having been
	# nudged since, and the whole conversation is framed around these two spots.
	if _ellie.is_walking():
		_ellie.stop_walking()
	_ellie.global_position = _ellie_pier_spot()
	_ellie.face("down")

	# The player draws up alongside her and looks out to sea too.
	await player_walk_to(_player_pier_spot(), PLAYER_SLOW_WALK_SPEED)
	player_face("down")

	await wait(PIER_SETTLE_PAUSE)

	await say(_speaker, PIER_OPENING_LINE)

	# She turns to the player, and they turn to her. The box comes down for the
	# turn so the two of them are visibly looking at each other before she goes on.
	close_box()
	_ellie.face_position(player.global_position)
	player_face_position(_ellie.global_position)
	await wait(TURN_BEAT)

	await say_all(_speaker, PIER_LINES_A)

	# A beat looking back out to sea before she changes the subject to cards.
	close_box()
	_ellie.face("down")
	await wait(LOOK_AWAY_PAUSE)
	_ellie.face_position(player.global_position)
	await wait(TURN_BEAT)

	await say_all(_speaker, PIER_LINES_B)

	_start_battle()


# ============================================================
# THE BATTLE
# ============================================================

func _start_battle() -> void:
	_set_stage(STAGE_BATTLE)
	var entry := CharacterSchedule.find_opponent(
		MAP_NAME, OPPONENT_NAME,
		GameState.get_date(), GameState.get_time(), MapManager.evaluate_condition)
	if entry.is_empty():
		push_error("EllieIntroCutscene: no '%s' entry in %s's character file" % [OPPONENT_NAME, MAP_NAME])
		_set_stage(STAGE_DONE)
		finish()
		return
	MapManager.start_forced_battle(entry)


## Reached on the map load AFTER the match. The outro has already shown its own
## win/loss dialogue by this point.
func _handle_battle_result() -> void:
	# Both of them are exactly where the battle interrupted them: the player is
	# respawned on the position saved when the match started, and she is put back
	# on her mark.
	_ellie = spawn(OPPONENT_NAME, SPRITE_NAME, _ellie_pier_spot(), "down")
	player.global_position = _player_pier_spot()
	player_face("right")
	# They come back out of the match still looking at each other, the way they went
	# in. Facing her out to sea here and turning her round afterwards read as her
	# losing interest the moment the game ended.
	_ellie.face_position(player.global_position)

	if not GameState.has_beaten_opponent(OPPONENT_NAME):
		# Straight back in. She is not letting them off.
		await wait(REMATCH_PAUSE)
		_start_battle()
		return

	await _play_farewell()


# ============================================================
# FAREWELL
# ============================================================

func _play_farewell() -> void:
	# She holds the player's eye a moment after the match, looks out to sea while
	# she thinks, then turns back to say goodbye.
	_ellie.face_position(player.global_position)
	player_face("right")
	await wait(FAREWELL_PAUSE)

	_ellie.face("down")
	await wait(FAREWELL_LOOK_DOWN)

	_ellie.face_position(player.global_position)
	await wait(TURN_BEAT)

	await say_all(_speaker, FAREWELL_LINES)
	close_box()

	_set_stage(STAGE_DONE)

	# Not awaited: she is hidden the moment she leaves the view, long before she
	# reaches the end of the path.
	_ellie.walk_path(_farewell_route(), FAREWELL_SPEED)

	# The player watches her go.
	player_face("up")
	_watching_exit = WATCH_FINISH
