class_name FishingMinigame
extends Node2D

## The whole fishing sequence: pulling the rod out, the cast, a silhouette fish creeping
## up on the bobber, the bite window, the tug-of-war, and the catch.
##
## Built and owned by MapManager.start_fishing(); it frees itself and calls
## MapManager.finish_fishing() when it is done.
##
## Style note: like the overworld Pokémon templates this uses NO tweens. Every motion is
## hand-integrated against a per-state `_time` accumulator, with sin(PI*t) for hops and
## linear ramps for deceleration, so it moves the same way the rest of the overworld does.
##
## The player is locked for the whole sequence with BOTH _player.lock_movement() and
## MapManager.cutscene_active. That pair is load-bearing: _hide_message() restores
## can_move as `not cutscene_active`, which is what lets a "the line snapped" box be
## dismissed WITHOUT handing movement back while the rod is still reeling in.

# ---- tweakables -------------------------------------------------------------
## The user thinks in on-screen pixels; the camera is at 2.5x, so world = screen * 0.4.
const SCREEN_TO_WORLD := 0.4

## Rod pull-out. Every beat below is multiplied by PULL_OUT_TIME_SCALE, so the whole
## sequence can be sped up or slowed down with one number. 1.0 was the original pace;
## 4.0 quartered the speed to inspect it frame by frame; 0.8 is 5x faster than that.
## The three turns and the flick come to about 0.43s in total at 0.8.
const PULL_OUT_TIME_SCALE := 0.8
const SHAKE_TIME := 0.2 * PULL_OUT_TIME_SCALE   ## facing away from the water, shaking
const SHAKE_STEPS := [-1.0, 1.0, 0.0]           ## sprite x offsets: left 1, right 2, left 1
const TURN_TIME := 0.12 * PULL_OUT_TIME_SCALE   ## per counterclockwise quarter turn
## 0 = the rod starts launching the instant the player lands on the water's direction.
const FLICK_PAUSE := 0.0 * PULL_OUT_TIME_SCALE
const FLICK_TIME := 0.1 * PULL_OUT_TIME_SCALE

## Sprite scales. The art is pixel-for-pixel world px at 1.0; the rod reads far too big
## against a 32px player at that size.
const ROD_SCALE := 0.5
const BOBBER_SCALE := 1.0
const FISH_SCALE := 1.0

## Where the rod handle sits relative to the player origin, per facing, in world px.
## Right hand for every direction.
##
## Measured off 1pokemontrainer_playerm.png: a 64px cell drawn centred at 0.5 scale, art
## from cell y=14 to y=59, so the sprite spans -9 (top of the head) to +13.5 (feet) in
## world px.
##
## These sprites are CHIBI, so the widest row of the silhouette is the HEAD, not the
## shoulders -- taking the widest row put the handle on the player's chin. The arms are a
## SECOND bulge further down: the front frame widens back out to 34px over world y +6 to
## +9.5, and both side frames bulge over +7 to +10.5. So the hand is at y=+8.5, roughly
## hip height, and x just inside the outer edge of that bulge.
const HAND_OFFSET := {
	"down": Vector2(-7.5, 8.5),
	"up": Vector2(7.5, 8.5),
	"left": Vector2(-3.0, 8.5),
	"right": Vector2(3.0, 8.5),
}

## Rod angles in DEGREES, Godot convention: clockwise-positive, 0 = the rod as drawn
## (vertical rod points straight up, horizontal rod points up-and-out at ~19 degrees).
## "raised" is the over-the-shoulder pose it is pulled out in and yanked back to;
## "rest" is where it flicks to for the cast.
## NOTE the sign on "left": the rod is MIRRORED for that facing (scale.x < 0), which
## reverses which way a positive rotation tips the tip. -45 there pointed it at the floor.
const ROD_RAISED_ANGLE := {"up": 40.0, "down": -40.0, "left": 45.0, "right": -45.0}
const ROD_REST_ANGLE := {"up": 0.0, "down": 180.0, "left": 0.0, "right": 0.0}
## Facings where the rod is held on the far side of the body, so the rig draws behind the
## player rather than in front of them.
const ROD_BEHIND_FACINGS := ["up", "left"]

## The rod, the line and the hauled-up Pokémon all draw ABOVE the map's scenery -- the
## harbour's fences and railings are z 9-11 and the tallest thing on the map is z 20, so
## a line cast out over a railing was disappearing behind it.
##
## ROD_Z is absolute, which beats the sibling ordering _apply_depth() uses: the rod now
## draws in front of the PLAYER as well as the fence, including the "up" and "left"
## facings where it is held on the far side of the body. That is the deliberate trade for
## having it clear the railing.
const ROD_Z := 21
const LINE_Z := 22
const CAUGHT_Z := 23
const DRIP_Z := 24
const NAME_TAG_Z := 25

## Cast. CAST_DISTANCE is only the FALLBACK for a map with no Fishing_Zone rectangle --
## normally the throw is half the zone's span along the cast (see _resolve_bounds).
const CAST_DISTANCE := 400.0 * SCREEN_TO_WORLD
const CAST_TIME := 0.55
## Sideways casts arc downwards as well as outwards.
const CAST_DROP := 0.4
const SPLASH_COUNT := 54
const SPLASH_SPEED := 0.8
## The rings that spread from a bobber landing or a Pokémon going back in.
const SPLASH_RIPPLE := 18.0
const SPLASH_RINGS := 1.3

## The music drops away the instant Space is pressed and is timed to land on silence at
## about the moment the bobber does -- the pull-out plus the cast comes to just under a
## second. It only comes back when the player clears the catch/failure message.
## Ducks bgm_player only -- never the Music bus, which carries the player's own slider.
const BGM_FADE_OUT := 1.0
const BGM_FADE_IN := 1.0
## ...but not straight away. A chain fisher casting again inside this window never hears
## the track come back at all, because the next cast's fade to 0 cancels the pending one.
const BGM_FADE_IN_DELAY := 2.0
## The sea bed (owned by FishingZone) comes UP to full as the music goes down, and back
## to its idle half when the message is cleared.
const SEA_FISHING_LEVEL := 1.0

## Water thrown up at the hooked fish's mouth, by what is happening to it. `interval` is
## seconds between bursts; 0 means it is only ever fired as a one-off.
##   big     it takes the bait under
##   wrong   the player is pulling the wrong way -- it is winning, and thrashing
##   correct the player has it under control, so it barely breaks the surface
##   tired   out of energy / being reeled in: almost nothing
##   huge    the moment it comes out of the water
## `ripple`/`rings` are the spreading surface rings that go with the thrown pixels: how
## far out they reach in world px, and how hard they are drawn (which also decides how
## many there are). See WaterRipples.
const FIGHT_SPLASH := {
	"big": {"interval": 0.0, "count": 34, "speed": 1.6, "width": 10.0, "ripple": 20.0, "rings": 1.4},
	"wrong": {"interval": 0.12, "count": 16, "speed": 1.3, "width": 8.0, "ripple": 14.0, "rings": 1.0},
	"correct": {"interval": 0.35, "count": 5, "speed": 0.55, "width": 3.0, "ripple": 8.0, "rings": 0.5},
	"tired": {"interval": 1.2, "count": 2, "speed": 0.25, "width": 1.5, "ripple": 5.0, "rings": 0.3},
	"huge": {"interval": 0.0, "count": 120, "speed": 2.2, "width": 6.0, "ripple": 30.0, "rings": 2.0},
}
## Same height as the line, so a splash out past a railing isn't swallowed by it.
const SPLASH_Z := 22

## Bobber animation, in FishingArt's 14-frame table (0-based; the user counts 1-14).
## Frames 0-6 are the cast row, 7-13 the floating row -- see Fishing_Art.gd.
##
##   splash  the moment it hits the water: straight down the cast row 1..7, then back up
##           the floating row 14..8, and it is left sitting at 8
##   idle    8 9 10 11 10 9, round and round, while it waits
##   bite    taken under: 8 up to 14, a flash of 7, then gone. With the "!" removed this
##           is the ONLY cue the player gets that a fish is on, so it is quick but whole.
const BOBBER_CAST_FRAME := 0
const BOBBER_SPLASH_SEQUENCE := [0, 1, 2, 3, 4, 5, 6, 13, 12, 11, 10, 9, 8, 7]
const BOBBER_SPLASH_FPS := 42.0
const BOBBER_IDLE_FRAMES := [7, 8, 9, 10, 9, 8]
const BOBBER_IDLE_FPS := 4.0
const BOBBER_BITE_SEQUENCE := [7, 8, 9, 10, 11, 12, 13, 6]
## Coming back OUT: the cast row played backwards, 7 down to 1, so it ends on the same
## fully-out-of-the-water frame the throw starts from. It has to be the cast row -- those
## frames have the pale grey weight on the bottom of the bobber, which is what it looks
## like in the air; the floating row's bottom is the dark submerged one.
const BOBBER_SURFACE_SEQUENCE := [6, 5, 4, 3, 2, 1, 0]
const BOBBER_BITE_FPS := 45.0

## Fish approach. Distances are measured out from the BOBBER, away from the player.
const FISH_SPAWN_DISTANCE := 200.0 * SCREEN_TO_WORLD
const FISH_SPAWN_LATERAL := 100.0 * SCREEN_TO_WORLD
## Underwater silhouettes read better slightly see-through. This is the alpha a fully
## faded-in fish sits at; _fish_alpha stays a 0-1 fade PROGRESS and is scaled by it, so
## the fade still takes FISH_FADE_IN seconds however transparent the fish ends up.
const FISH_ALPHA := 0.8
const FISH_FADE_IN := 1.0
## 50% up on the original 8-16: the creep up on the bait was a long wait.
const FISH_SPEED_MIN := 12.0
const FISH_SPEED_MAX := 24.0
## How much faster it swims as it closes the last of the gap.
const FISH_CLOSING_BOOST := 0.2
const FISH_ANIM_FPS := 4.0
## Tail speed relative to the calm approach: it thrashes once hooked, and idles while it
## is out of energy and getting its breath back.
const FISH_ANIM_FIGHT_SCALE := 6.0
const FISH_ANIM_TIRED_SCALE := 0.25
## Swim cycles, as (frame, mirrored) pairs. The small fish never mirror -- they have
## five frames of their own, three straight and two darting.
const FISH_CALM_FRAMES := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 0), Vector2i(2, 0)]
const FISH_FAST_FRAMES := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0), Vector2i(1, 0),
		Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0), Vector2i(2, 0)]
## The BIG fish only has four frames, so the second half of its cycle is the first half
## MIRRORED: 1 2 3 2 1, then 2 3 2 flipped, back to 1. The fast cycle is the same with
## the dart (frame 4) dropped in after each 3.
const FISH_BIG_CALM_FRAMES := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 0),
		Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 1), Vector2i(0, 0)]
const FISH_BIG_FAST_FRAMES := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(1, 0), Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(1, 1), Vector2i(0, 0)]
## How fast it can swing its nose round, in radians per second. It used to snap: a
## turn at the end of a run flipped the sprite through 180 degrees in one frame, which
## reads as the fish mirroring itself across the line rather than turning. At 7.0 a full
## about-face takes a bit under half a second.
const FISH_TURN_RATE := 7.0
const FISH_FLEE_SPEED := 90.0
const FISH_FLEE_FADE := 0.6

const BITE_DELAY_MIN := 0.1
const BITE_DELAY_MAX := 2.0
const BITE_WINDOW := 1.0

## Tug-of-war. Line strength runs -100 (slack, about to be dropped) to +100 (snapped).
## Only MISTAKES load the line now: countering correctly holds it wherever it is and just
## tires the fish out, so the fight is about reading the fish's run rather than rationing
## a pull. A wrong hold snaps it in under a second and letting go goes slack in one, so
## there is no resting -- the right key has to be held nearly all of the time.
const TENSION_DECAY := 100.0     ## per second with no input
const TENSION_CORRECT := 0.0     ## countering the right way costs the line nothing
## A SLACK line (negative tension) is taken back up to neutral while the player counters
## correctly, at a middling rate -- so pulling the right way also recovers a line that was
## nearly dropped, instead of leaving it sitting in the blue.
const TENSION_CORRECT_RECOVER := 55.0
const TENSION_WRONG := 120.0     ## per second pulling the wrong way
## One hit per REEL press made while the fish still has fight in it. Enough that
## panic-mashing early costs, not so much that a couple of hopeful presses end the fight.
const TENSION_WRONG_PRESS := 17.5
## While the fish is blown, the line settles back to neutral from EITHER side at this rate
## per second -- that is what the mashing window is for: it hands you a clean line for the
## next run.
const TENSION_REST_RECOVER := 120.0
const ENERGY_DRAIN := 40.0       ## per second of correct input
## The fish also tires on its own, at a flat fraction of its whole bar every second,
## whatever the player is doing. At 0.05 a fish that is never countered still blows in
## 20 seconds, so a fight always moves forwards.
const ENERGY_BLEED_FRACTION := 0.05
## Speed and tail scale while it is blown and getting its breath back.
const TIRED_SPEED_FACTOR := 0.25
## What the player's input does to the fish's speed: countering correctly slows it,
## pulling the wrong way lets it run.
const FIGHT_INPUT_SLOW := 0.8
const FIGHT_INPUT_FAST := 1.2
## The run out to `initial_distance` after the strike is swum at the fish's FIGHTING
## speed (its `lateral_speed`, the same one it runs side to side at), not at the crawl it
## crept up on the bait with -- a hooked fish bolting is the fastest it ever moves. The
## fight proper does not start until it arrives; see _process_fight.
## The fish is on a LEASH at whatever range it has been reeled to. It surges out to
## FIGHT_SURGE beyond that and comes back to it, over and over, but can never get further
## in than the leash -- so ground won by reeling is never given back, and the only thing
## that shortens the fight is mashing during a rest.
const FIGHT_SURGE := 55.0        ## world px it can run out beyond the leash
const FIGHT_SURGE_SPEED_MIN := 30.0
const FIGHT_SURGE_SPEED_MAX := 70.0
## How long it holds one direction before turning. Long: a fish that changes its mind
## twice a second is a flicker, not a run the player can read and counter.
const FIGHT_SWITCH_MIN := 2.5    ## seconds before the fish turns and dashes back
const FIGHT_SWITCH_MAX := 5.0
## The fish runs inside a CONE opening out from the player, so it thrashes right across
## the screen while it is still out at sea and is drawn in towards dead ahead as it is
## landed. Running into the wall of the cone does NOT turn it round: it keeps swimming
## that way and simply stops making ground, which reads as a fish straining against the
## line rather than one bouncing between two invisible walls.
##
## The room it has is measured against WHERE THE BOBBER LANDED, not against the far wall:
## FIGHT_CONE_MIN at the catch line, FIGHT_CONE_MIN + FIGHT_CONE_AT_CAST out at the cast,
## and it keeps opening past that (the Fishing_Zone's own side walls bound it in the end).
## FIGHT_CONE_POWER above 1 is what makes it pinch in towards the player instead of
## tapering in a straight line.
##
## These three are FITTED to the shape the user drew over a screenshot, sampled at eight
## depths; the curve is within a couple of world px of that drawing the whole way down.
const FIGHT_CONE_MIN := 24.0      ## world px of sideways room AT the catch line
const FIGHT_CONE_AT_CAST := 250.0 ## extra room out where the bobber landed
const FIGHT_CONE_POWER := 2.2     ## >1 pinches it in towards the player
## Reeling is a MASH, not a hold: every Space/Enter press drags the leash in by the
## fish's `reel_step`. How much ground a rest wins is down to how fast the player can
## hit it.
## FALLBACK only: with a Fishing_Zone rectangle the catch line is that rectangle's edge
## nearest the player (see _resolve_bounds), not a fixed distance.
const CATCH_DISTANCE := 200.0 * SCREEN_TO_WORLD
const CATCH_PAUSE := 0.1

## Retract (a miss, a break-off, or Escape).
const RETRACT_SPEED := 360.0
## The catch is hauled in at half that: the Pokémon swinging up the line is the payoff
## shot and it was over before it registered.
const CATCH_YANK_SPEED := 180.0
const RETRACT_HOLD := 0.2

## The caught Pokémon's hop back into the water, mirroring PokemonSkittish. It JUMPS UP
## off the rod first and only then dives away: for the first HOP_RISE of the hop it
## climbs and barely travels, and after that it drops fast and covers the ground. A
## single sin() arc with steady travel just slid it off the line.
const HOP_TIME := 0.55
const HOP_HEIGHT := 26.0
const HOP_SPEED := 260.0
const HOP_RISE := 0.35
## It leaves the rod still facing the player and only turns to face the way it is
## actually travelling once it is clear.
const HOP_TURN_TIME := 0.2

## Water running off the Pokémon while it hangs on the line. One pixel every
## DRIP_INTERVAL from somewhere along its underside, falling away and fading out.
const DRIP_INTERVAL := 0.09
const DRIP_LIFE := 0.55

## DEBUG ONLY (DebugMode.is_enabled()): the rolled species' name, floated above the
## silhouette so it is obvious which fish is on the line while the fight is being tuned.
## World px above the fish's head, which is the silhouette's own origin.
const NAME_TAG_OFFSET := 9.0
const NAME_TAG_FONT_SIZE := 8
const NAME_TAG_WIDTH := 160.0
const NAME_TAG_COLOUR := Color(1.0, 0.95, 0.6)
const SINK_TIME := 0.5
const WATER_CLEAR_ROWS := 5.0
const WATER_FADE_ROWS := 8.0

## Line.
## Exactly one world pixel, the same width as the bobber's antenna -- 0.8 rendered two
## screen pixels against the antenna's two-and-a-half and sat visibly off to one side.
const LINE_WIDTH := 1.0
const LINE_SLACK_FAR := Color8(18, 38, 110)    ## -100
const LINE_SLACK_NEAR := Color8(90, 200, 230)  ## -50
const LINE_NEUTRAL := Color.WHITE              ## 0
const LINE_TIGHT_NEAR := Color8(240, 120, 120) ## +50
const LINE_TIGHT_FAR := Color8(130, 10, 10)    ## +100

## Camera follow on the bobber.
const CAMERA_LERP := 6.0

## Sound. _sfx() checks the file is there before it loads, so one that has not been
## imported yet is silent rather than a crash. Move these to preloaded constants in
## Sound_Manager_Script.gd once they are all settled (a preload of a missing file won't
## compile).
const SFX := {
	"cast": "res://Audio/SFX/FishRodCast.ogg",
	"splash": "res://Audio/SFX/FishBobberSplash.ogg",
	"bite": "res://Audio/SFX/FishBite.ogg",
	"splash_good": "res://Audio/SFX/FishSplashGood.ogg",
	"splash_good2": "res://Audio/SFX/FishSplashGood2.ogg",
	"splash_bad": "res://Audio/SFX/FishSplashBad.ogg",
	"caught": "res://Audio/SFX/FishSplashCaught.ogg",
	"jingle": "res://Audio/SFX/FishCaughtJingle.ogg",
}

## Water noise during the fight. A splash every so often, picked from the two "good"
## files at random when the player is countering or doing nothing and the one "bad" file
## when they are pulling the wrong way, each at a random pitch (which also shifts its
## tempo) so the same handful of samples never settles into a rhythm.
const FIGHT_SFX_GOOD_MIN := 0.5
const FIGHT_SFX_GOOD_MAX := 2.0
const FIGHT_SFX_BAD_MIN := 0.4
const FIGHT_SFX_BAD_MAX := 1.0
const FIGHT_SFX_PITCH := 0.1

## The catch: its own cry first, and the jingle timed to land as the cry runs out. The
## lead shaves a sliver off so the two meet rather than leaving a gap. A species with no
## cry file gets the jingle straight away.
const JINGLE_AFTER_CRY_LEAD := 0.06

## PER-SPECIES STATS. These six are NOT constants: they are the rolled species' own,
## read from the Pokemon registry (OverworldPokemonData.fish_stats, edited in
## DEL -> FISH TABLE), so a Magikarp fights a Magikarp's fight on every map and at every
## time of day. Their defaults are exactly the numbers this file used before they were
## tunable, so a species with none of them set fights the way it always did.
##
##   _stats.energy            stamina bar; correct input drains it at ENERGY_DRAIN/s
##   _stats.line_strength     +/- limit the line snaps at (the -100..+100 of old)
##   _stats.recharge_time     seconds blown -- the reel-in window, then full energy again
##   _stats.reel_step         world px hauled in per reel press
##   _stats.initial_distance  world px the hook runs it out PAST the bobber (0 = no run)
##   _stats.lateral_speed     world px/s of its run across the cast

## One line per way of losing a fish, so the player is told WHICH mistake they made
## rather than being left to work it out: the line ran red (too much wrong input), the
## line ran blue (no tension at all), the strike window closed, or it simply outran them.
## ESCAPED_MESSAGE is the fallback for a fish that goes away without a reason of its own.
const BREAK_MESSAGE := "The line snapped!"
const SLACK_MESSAGE := "No tension on rod, the fish broke free!"
const TOO_LATE_MESSAGE := "You reeled in too late, the fish stole the bait!"
## Run all the way out to the far edge of the Fishing_Zone rectangle.
const BROKE_FREE_MESSAGE := "The fish was able to swim away!"
const ESCAPED_MESSAGE := "It got away..."
# -----------------------------------------------------------------------------

enum State {
	SHAKE, TURN_AWAY, TURN_BACK, FLICK, CAST, WAIT, SINK, BITE, FIGHT,
	CATCH_PAUSE_STATE, CATCH_YANK, CATCH_MESSAGE, CATCH_HOP, CATCH_SINK, RETRACT, DONE
}

var map_data: String = ""
## Which way the WATER is: the direction the player ends up facing.
var water_dir: String = "down"

var _player: CharacterBody2D = null
var _rod: Sprite2D = null
var _bobber: Sprite2D = null
var _line: Line2D = null
var _fish: Sprite2D = null
var _caught: Sprite2D = null
var _drips: DripLayer = null
var _name_tag: NameTag = null

var _state: int = State.SHAKE
var _time: float = 0.0
var _facing: String = "down"
var _vertical_rod: bool = true

var _rod_angle: float = 0.0

var _bobber_frame: int = 0
var _bobber_anim: float = 0.0
var _bobber_pos: Vector2 = Vector2.ZERO
## The cast ARC, which tilts downwards for a sideways throw. Only the throw uses it --
## every distance, edge and leash in the fight is measured along _axis.
var _cast_dir: Vector2 = Vector2.DOWN
var _cast_speed: float = 0.0
## The straight line out from the player towards the water, and how far the bobber is
## thrown along it. _cast_distance is half the Fishing_Zone rectangle's span on this axis.
var _axis: Vector2 = Vector2.DOWN
var _cast_distance: float = CAST_DISTANCE

## A one-shot bobber animation (the splash-down, or being taken under), played on top of
## whatever state is running. Empty when nothing is playing.
var _bobber_seq: Array = []
var _bobber_seq_time: float = 0.0
var _bobber_seq_fps: float = 1.0
var _bite_anim: bool = false

## The Fishing_Zone rectangle and what it works out to for this cast, all measured from
## the player: _catch_radial is its nearest edge (reel the fish over it and it is landed),
## _lost_radial the edge opposite the player (reach it and the fish breaks free), and
## _side_min/_side_max the two walls it turns round at. Left at the fallbacks when the
## map has no Fishing_Zone shape.
var _bounds: Rect2 = Rect2()
var _catch_radial: float = CATCH_DISTANCE
var _lost_radial: float = INF
## Radial distance of the splashdown. The cone's width is measured against this, so the
## fight is shaped by how far the player actually cast rather than by the size of the sea.
## Seeded from the zone and then corrected to where the bobber really landed.
var _cast_radial: float = CATCH_DISTANCE + CAST_DISTANCE
var _side_min: float = -INF
var _side_max: float = INF

var _fish_species: String = ""
## The rolled species' six fight numbers -- see the PER-SPECIES STATS note above. Always
## fully populated (fish_stats fills every key), so it can be read without a .get.
var _stats: Dictionary = OverworldPokemonData.fish_stats("")
var _fish_frame: int = 0
## Which silhouette set the rolled species uses, whether the current frame is mirrored,
## and the multiplier the species' `fish_size` puts on it.
var _fish_big: bool = false
var _fish_flip: bool = false
var _fish_size: float = FISH_SCALE
var _fish_anim: float = 0.0
var _fish_speed: float = 0.0
var _fish_start_gap: float = 1.0
var _fish_fleeing: bool = false
var _fish_alpha: float = 0.0
var _fish_aim: Vector2 = Vector2.UP
## Where it is TRYING to point. _fish_aim is where it has actually got to so far.
var _fish_aim_target: Vector2 = Vector2.UP

var _bite_delay: float = 0.0

var _tension: float = 0.0
var _energy: float = 0.0
var _fight_side: float = 1.0
var _fight_switch: float = 0.0
## Seconds of "blown" left. Above zero the fish is resting, the line is recovering and
## mashing reels it in; it is the only window in which reeling does anything.
var _rest_left: float = 0.0
## Radial distance from the player the fish is tethered at -- the closest it has been
## reeled. It never gets back inside this.
var _leash: float = 0.0
## Which way along the cast axis it is currently surging, and how fast on this leg.
var _surge_dir: float = 1.0
var _surge_speed: float = 0.0
var _perp: Vector2 = Vector2.RIGHT
## True while the strike is still dragging the fish out to its initial_distance.
var _yanking: bool = false

var _hop_dir: Vector2 = Vector2.DOWN
var _hop_turned: bool = false
var _drip_timer: float = 0.0
var _water_y: float = 0.0
var _sink_from: float = 0.0
var _sink_distance: float = 0.0
var _water_material: ShaderMaterial = null
var _caught_cell: Vector2 = Vector2.ONE
var _caught_scale: float = 0.5

## A failure retract runs its animation and its message box at the same time; control
## comes back only once BOTH are finished.
var _splash_timer: float = 0.0
## Counts down to the next fight splash SOUND, which runs on its own timing (and its own
## random interval) rather than with the splash particles.
var _fight_sfx_timer: float = 0.0
## Seconds until the catch jingle, counted down from the length of the cry. Negative
## means there is no jingle pending.
var _jingle_left: float = -1.0

## The map's FishingZone, which owns the looping sea bed.
var _zone: FishingZone = null
## Which row of the caught Pokémon's sheet is on screen. The sink shader's waterline is
## measured inside that row, so it has to follow the hop's turn -- reading `water_dir`
## after the turn is what killed the blue-from-the-bottom fade.
var _caught_row: int = 1
## The opaque bounding box of the caught Pokémon's current frame, in texture pixels
## relative to its cell's top-left. Most of a 64px cell is empty, so hanging the sprite
## by its CENTRE put the Pokémon nowhere near the end of the line.
var _caught_bbox: Rect2 = Rect2()

var _message_open: bool = false
var _retract_done: bool = false
var _finished: bool = false


# ============================================================
# SETUP
# ============================================================

func setup(player: CharacterBody2D, direction: String, map_key: String) -> void:
	_player = player
	water_dir = direction
	map_data = map_key


func _ready() -> void:
	_facing = _opposite(water_dir)
	_vertical_rod = _facing == "up" or _facing == "down"
	_perp = Vector2.RIGHT if (water_dir == "up" or water_dir == "down") else Vector2.DOWN
	_resolve_bounds()

	_build_rod()
	_build_line()
	_build_bobber()

	# _face() applies the depth order too.
	_face(_facing)
	_rod_angle = _raised_angle()
	_apply_rod()
	_snap_bobber_to_tip()
	# The player is locked for the whole sequence, which normally kills the mouse wheel
	# too. Fishing is long enough that they want to be able to pull the camera in on the
	# bobber, so the zoom is let through for the duration -- see Player_Object_Script.
	if _player != null:
		_player.zoom_while_locked = true
	# Straight away, not at the cast: the pull-out plus the throw comes to just under a
	# second, so the music lands on silence at about the moment the bobber does. The sea
	# comes up to full underneath it.
	SoundManagerScript.fade_bgm(0.0, BGM_FADE_OUT)
	if _zone != null and is_instance_valid(_zone):
		_zone.set_ambience(SEA_FISHING_LEVEL, BGM_FADE_OUT)
	_set_state(State.SHAKE)


## Works the whole cast out of the map's Fishing_Zone rectangle: how far to throw, where
## the catch line is, where the fish breaks free, and the two walls it turns round at.
## A map without one keeps the old fixed numbers.
func _resolve_bounds() -> void:
	_axis = _dir_vector(water_dir)
	_catch_radial = CATCH_DISTANCE
	_lost_radial = INF
	_side_min = -INF
	_side_max = INF
	_cast_distance = CAST_DISTANCE
	_zone = FishingZone.find_in(get_parent())
	_bounds = _zone.bounds_rect() if _zone != null else Rect2()
	if _player == null or _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return
	# Project all four corners onto the two axes: whichever way round the player is
	# standing, the nearest projection is the catch line and the furthest is the far wall.
	var radial: Array[float] = []
	var across: Array[float] = []
	for corner in [_bounds.position, _bounds.position + Vector2(_bounds.size.x, 0.0),
			_bounds.position + Vector2(0.0, _bounds.size.y), _bounds.end]:
		var from_player: Vector2 = corner - _player.global_position
		radial.append(from_player.dot(_axis))
		across.append(from_player.dot(_perp))
	_catch_radial = maxf(1.0, float(radial.min()))
	_lost_radial = float(radial.max())
	_side_min = float(across.min())
	_side_max = float(across.max())
	# "Measure the height of the box and throw half of it" -- which is the span between
	# the two edges, not the distance to the far one.
	_cast_distance = maxf(8.0, (_lost_radial - _catch_radial) * 0.5)
	_cast_radial = _catch_radial + _cast_distance


func _build_rod() -> void:
	_rod = Sprite2D.new()
	_rod.texture = FishingArt.rod_texture(_vertical_rod)
	_rod.centered = false
	# In front of the fence the player is standing behind -- see ROD_Z.
	_rod.z_as_relative = false
	_rod.z_index = ROD_Z
	_rod.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The node origin becomes the handle, so rotation pivots there.
	_rod.offset = -FishingArt.rod_pivot(_vertical_rod)
	add_child(_rod)


func _build_bobber() -> void:
	_bobber = Sprite2D.new()
	_bobber.centered = false
	_bobber.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bobber.scale = Vector2(BOBBER_SCALE, BOBBER_SCALE)
	add_child(_bobber)
	_set_bobber_frame(0)


func _build_line() -> void:
	_line = Line2D.new()
	_line.width = LINE_WIDTH
	_line.default_color = LINE_NEUTRAL
	_line.texture_mode = Line2D.LINE_TEXTURE_NONE
	_line.joint_mode = Line2D.LINE_JOINT_SHARP
	# Over the map scenery, so a cast out across a railing is not cut in half by it.
	_line.z_as_relative = false
	_line.z_index = LINE_Z
	add_child(_line)


## Whenever the player is facing AWAY from us the rod and bobber go BEHIND them; every
## other facing they go in front. Re-applied on every turn rather than once from
## water_dir, because the pull-out spins the player through all four directions and the
## rod has to sit correctly in each of them.
##
## Done by sibling order, not z_index: equal z_index draws in tree order, and the rig
## stays after the tilemaps either way, so it can never sink under the ground the way a
## negative z_index would.
func _apply_depth() -> void:
	# Facing up OR left: the rod is in the right hand, which is the far side of the body
	# in both of those, so the whole rig sits behind the player.
	var behind := _facing in ROD_BEHIND_FACINGS
	# The fish is under water and always stays at the bottom.
	var order: Array = []
	if _fish != null and is_instance_valid(_fish):
		order.append(_fish)
	if behind:
		order.append_array([_bobber, _line, _rod])
	else:
		order.append_array([_rod, _line, _bobber])
	for i in order.size():
		move_child(order[i], i)
	var parent := get_parent()
	if parent == null or _player == null or not is_instance_valid(_player):
		return
	# Only move when we are on the wrong side of the player. Moving unconditionally is
	# NOT idempotent: once the rig sits before the player, the player's index is the
	# rig's + 1, so "move to the player's index" pushes the rig back in front of them --
	# which is why two "behind" beats in a row ended up facing the wrong way round.
	var player_index := _player.get_index()
	if behind and get_index() > player_index:
		parent.move_child(self, player_index)
	elif not behind and get_index() < player_index:
		parent.move_child(self, parent.get_child_count() - 1)


# ============================================================
# MAIN LOOP
# ============================================================

func _process(delta: float) -> void:
	_time += delta
	match _state:
		State.SHAKE: _process_shake()
		State.TURN_AWAY, State.TURN_BACK: _process_turn()
		State.FLICK: _process_flick()
		State.CAST: _process_cast(delta)
		State.WAIT: _process_wait(delta)
		State.SINK: _process_sink(delta)
		State.BITE: _process_bite(delta)
		State.FIGHT: _process_fight(delta)
		State.CATCH_PAUSE_STATE: _process_catch_pause()
		State.CATCH_YANK: _process_catch_yank(delta)
		State.CATCH_MESSAGE: pass
		State.CATCH_HOP: _process_catch_hop(delta)
		State.CATCH_SINK: _process_catch_sink()
		State.RETRACT: _process_retract(delta)
	_tick_jingle(delta)
	_update_fish_anim(delta)
	_tick_name_tag()
	_tick_drips(delta)
	_update_line()
	_update_camera(delta)


func _set_state(next: int) -> void:
	_state = next
	_time = 0.0


func _input(event: InputEvent) -> void:
	if _state == State.DONE:
		return
	# The catch / failure box owns Space and Escape while it is up.
	if MapManager.wants_message_input():
		return
	if UIInput.is_cancel(event):
		# Bail out any time before the fish is actually on the bank.
		if _state in [State.CAST, State.WAIT, State.SINK, State.BITE, State.FIGHT]:
			get_viewport().set_input_as_handled()
			_scare_fish()
			_begin_retract("")
		return
	if not UIInput.is_accept(event):
		return
	get_viewport().set_input_as_handled()
	match _state:
		State.CAST, State.WAIT, State.SINK:
			# Yanked too early: the fish bolts, nothing is lost but the cast.
			_scare_fish()
			_begin_retract("")
		State.BITE:
			_hook()
		State.FIGHT:
			# Reeling is a mash. A press lands a notch while the fish is blown, and is a
			# costly mistake at any other time -- the player can always try, and pays for
			# it if the fish still has fight in it.
			if _rest_left > 0.0:
				_reel_step()
			else:
				_tension += TENSION_WRONG_PRESS


# ============================================================
# 1 -- ROD PULL-OUT
# ============================================================

func _process_shake() -> void:
	var step := int(_time / (SHAKE_TIME / float(SHAKE_STEPS.size())))
	_set_shake(SHAKE_STEPS[clampi(step, 0, SHAKE_STEPS.size() - 1)])
	if _time >= SHAKE_TIME:
		_set_shake(0.0)
		_face(_counterclockwise(_facing))
		_set_state(State.TURN_AWAY)


func _process_turn() -> void:
	if _time < TURN_TIME:
		return
	if _state == State.TURN_AWAY:
		# The second turn lands on the water's own direction, which is the beat the cast
		# reads as starting -- the whole throw runs off the back of this sound.
		_face(_counterclockwise(_facing))
		_sfx("cast")
		_set_state(State.TURN_BACK)
	else:
		_set_state(State.FLICK)


func _process_flick() -> void:
	if _time < FLICK_PAUSE:
		return
	var t := clampf((_time - FLICK_PAUSE) / FLICK_TIME, 0.0, 1.0)
	_rod_angle = lerpf(_raised_angle(), _rest_angle(), t)
	_apply_rod()
	_snap_bobber_to_tip()
	if t >= 1.0:
		_start_cast()


func _set_shake(offset: float) -> void:
	if _player != null and _player.animated_sprite != null:
		_player.animated_sprite.position.x = offset


## Turns the player and moves the rod to whichever hand position that facing uses.
func _face(direction: String) -> void:
	_facing = direction
	if _player != null:
		_player.set_direction(direction)
	var want_vertical := direction == "up" or direction == "down"
	if want_vertical != _vertical_rod:
		_vertical_rod = want_vertical
		_rod.texture = FishingArt.rod_texture(_vertical_rod)
		_rod.offset = -FishingArt.rod_pivot(_vertical_rod)
	_rod_angle = _raised_angle()
	_apply_depth()
	_apply_rod()
	_snap_bobber_to_tip()


func _apply_rod() -> void:
	if _player == null:
		return
	_rod.global_position = _player.global_position + HAND_OFFSET.get(_facing, Vector2.ZERO)
	# A negative x scale mirrors the rod about its handle, which is what "flip it so the
	# red tip points left" means. Scale is applied before rotation, so the angle below
	# still reads clockwise on screen either way.
	_rod.scale = Vector2(-ROD_SCALE if _facing == "left" else ROD_SCALE, ROD_SCALE)
	_rod.rotation_degrees = _rod_angle


func _raised_angle() -> float:
	return float(ROD_RAISED_ANGLE.get(_facing, 0.0))


func _rest_angle() -> float:
	return float(ROD_REST_ANGLE.get(_facing, 0.0))


## Where the line leaves the rod: the red tip, in global space.
func _rod_tip() -> Vector2:
	return _rod.to_global(FishingArt.rod_tip(_vertical_rod) + _rod.offset)


# ============================================================
# 2 -- THE CAST
# ============================================================

func _start_cast() -> void:
	_cast_dir = _dir_vector(water_dir)
	if water_dir == "left" or water_dir == "right":
		_cast_dir = (_cast_dir + Vector2.DOWN * CAST_DROP).normalized()
	# Fast out of the rod, coasting to a stop: distance = speed * time / 2.
	_cast_speed = 2.0 * _cast_distance / CAST_TIME
	_place_bobber_by_top(_rod_tip())
	_cast_radial = _catch_radial + _cast_distance
	_set_state(State.CAST)


func _process_cast(delta: float) -> void:
	var t := clampf(_time / CAST_TIME, 0.0, 1.0)
	_bobber_pos += _cast_dir * _cast_speed * (1.0 - t) * delta
	_place_bobber(_bobber_pos)
	if t >= 1.0:
		_land_bobber()


func _land_bobber() -> void:
	# The cone is measured against where the line actually went, so take it from the
	# splashdown rather than from the throw's nominal length.
	_cast_radial = maxf(_catch_radial + 1.0,
			(_bobber_pos - _player.global_position).dot(_axis))
	# The bobber is positioned by its WATERLINE, so this point is already the surface --
	# which is where the splash belongs, not up at the top of the antenna.
	_splash(_bobber_pos)
	_sfx("splash")
	# Straight down the cast row and back up the floating row, all inside a third of a
	# second, leaving it sitting at its floating frame.
	_play_bobber_seq(BOBBER_SPLASH_SEQUENCE, BOBBER_SPLASH_FPS)
	_spawn_fish()
	_set_state(State.WAIT)


func _splash(at: Vector2) -> void:
	# Rings first so they draw UNDER the pixels: the surface reacting, with the water
	# thrown into the air on top of it.
	WaterRipples.fire(get_parent(), at, SPLASH_RIPPLE, SPLASH_RINGS, SPLASH_Z - 1)
	PixelBurst.fire(get_parent(), at, PokemonSurfacer.SPLASH_COLOURS,
			SPLASH_COUNT, SPLASH_SPEED, 6.0, SPLASH_Z)


## Moves the bobber so its WATERLINE -- the bottom edge of the frame -- lands on
## `global_point`. Every frame of the sink art is drawn hanging off that same waterline,
## so this is the one anchor that keeps a sinking bobber still in the water.
func _place_bobber(global_point: Vector2) -> void:
	_bobber_pos = global_point
	_bobber.global_position = global_point


## Hangs the bobber so its TIE-ON POINT is at `global_point` -- what "dangling off the
## rod tip" means, in the air and on the way back in.
func _place_bobber_by_top(global_point: Vector2) -> void:
	_place_bobber(global_point + Vector2(0.0, _bobber_drop()))


## How far the waterline anchor sits below the tie-on point in the current frame.
func _bobber_drop() -> float:
	return FishingArt.bobber_anchor(_bobber_frame).y - FishingArt.bobber_top(_bobber_frame).y


func _set_bobber_frame(frame: int) -> void:
	_bobber_frame = clampi(frame, 0, FishingArt.BOBBER_FRAMES - 1)
	_bobber.texture = FishingArt.bobber_texture(_bobber_frame)
	_bobber.offset = -FishingArt.bobber_anchor(_bobber_frame)


func _snap_bobber_to_tip() -> void:
	_place_bobber_by_top(_rod_tip())


## Where the line ties on: the top pixel of the current frame. It shares its x with the
## bobber's own origin, so the line runs exactly down the middle of the antenna.
func _bobber_tie() -> Vector2:
	return _bobber.to_global(FishingArt.bobber_top(_bobber_frame) + _bobber.offset)


## Where a fish aims, and where a splash belongs: the bobber at the surface.
func _bobber_waterline() -> Vector2:
	return _bobber.global_position


## The bobber's BOTTOM visible pixel -- the end of the line, which is what a caught
## Pokémon hangs from. Not the same as the waterline: the frame's rect runs a little
## past the art in the frames that are still riding high.
func _bobber_low() -> Vector2:
	return _bobber.to_global(FishingArt.bobber_low(_bobber_frame) + _bobber.offset)


## Where the bobber parks when it is reeled all the way home.
func _tip_park() -> Vector2:
	return _rod_tip() + Vector2(0.0, _bobber_drop())


## Starts a one-shot bobber animation. It is advanced by _advance_bobber_seq() from
## whichever state is running.
func _play_bobber_seq(seq: Array, fps: float) -> void:
	_bobber_seq = seq
	_bobber_seq_time = 0.0
	_bobber_seq_fps = fps
	if not seq.is_empty():
		_set_bobber_frame(int(seq[0]))


## True while the sequence is still running; false the frame it finishes (and from then
## on, until another one is started).
func _advance_bobber_seq(delta: float) -> bool:
	if _bobber_seq.is_empty():
		return false
	_bobber_seq_time += delta * _bobber_seq_fps
	var i := int(_bobber_seq_time)
	if i >= _bobber_seq.size():
		_bobber_seq = []
		return false
	_set_bobber_frame(int(_bobber_seq[i]))
	return true


## The floating bob: 8 9 10 11 10 9, round and round.
func _tick_bobber_idle(delta: float) -> void:
	_bobber_anim += delta * BOBBER_IDLE_FPS
	_set_bobber_frame(int(BOBBER_IDLE_FRAMES[int(_bobber_anim) % BOBBER_IDLE_FRAMES.size()]))


# ============================================================
# 3 -- THE FISH
# ============================================================

func _spawn_fish() -> void:
	_fish_species = FishingData.pick_fish(map_data)
	_stats = OverworldPokemonData.fish_stats(_fish_species)
	if _fish_species == "":
		return  # nothing lives here at this hour; the player reels in by hand
	_fish_big = OverworldPokemonData.species_big_fish(_fish_species)
	_fish_size = FISH_SCALE * float(_stats["fish_size"])
	_fish_flip = false
	_fish = Sprite2D.new()
	_fish.centered = false
	_fish.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fish.modulate.a = 0.0
	add_child(_fish)
	move_child(_fish, 0)  # always under the rod, the line and the bobber
	_set_fish_frame(0)
	_apply_fish_scale()
	var lateral := _perp * randf_range(-FISH_SPAWN_LATERAL, FISH_SPAWN_LATERAL)
	_fish.global_position = _bobber_pos + _axis * FISH_SPAWN_DISTANCE + lateral
	# Never outside its own water, and never right on the far wall -- that is the line it
	# breaks free on, and it must not be sitting on it before the fight has begun.
	if _bounds.size.x > 0.0 and _bounds.size.y > 0.0:
		var inner := _bounds.grow(-2.0)
		_fish.global_position = _fish.global_position.clamp(inner.position, inner.end)
	_fish_speed = randf_range(FISH_SPEED_MIN, FISH_SPEED_MAX)
	_fish_start_gap = maxf(1.0, _fish.global_position.distance_to(_bobber_waterline()))
	_fish_alpha = 0.0
	_aim_fish(_bobber_waterline() - _fish.global_position)
	_show_name_tag()


func _set_fish_frame(frame: int) -> void:
	_fish_frame = frame
	_fish.texture = FishingArt.fish_texture(frame, _fish_big)
	# Origin = the head, so it swims and turns about its nose -- and so mirroring with a
	# negative x scale mirrors it about the SWIM AXIS rather than shifting it sideways.
	_fish.offset = -FishingArt.fish_head(frame, _fish_big)


func _apply_fish_scale() -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	_fish.scale = Vector2(-_fish_size if _fish_flip else _fish_size, _fish_size)


## Points the fish's head along `direction`. The art swims "up" at rotation 0.
##
## `snap` is for the one-off beats that are MEANT to be instant -- the hook, bolting. Left
## false, the fish only starts turning that way and _turn_fish() walks it round over the
## next few frames, which is what stops a change of direction reading as the sprite
## mirroring itself across the line.
func _aim_fish(direction: Vector2, snap: bool = true) -> void:
	if direction.length_squared() <= 0.0001:
		return
	_fish_aim_target = direction.normalized()
	if not snap:
		return
	_fish_aim = _fish_aim_target
	_fish.rotation = Vector2.UP.angle_to(_fish_aim)


## Walks the fish round towards wherever it is heading, at FISH_TURN_RATE. _fish_aim is
## kept in step with the rotation, so anything reading it (the flee, the line) sees the
## direction the sprite is actually pointing.
func _turn_fish(delta: float) -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	var want := Vector2.UP.angle_to(_fish_aim_target)
	_fish.rotation = rotate_toward(_fish.rotation, want, FISH_TURN_RATE * delta)
	_fish_aim = Vector2.UP.rotated(_fish.rotation)


func _update_fish_anim(delta: float) -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	# Calm on the way in, thrashing once it is hooked, idling while it is out of energy.
	var anim_scale := 1.0
	if _state == State.FIGHT or _state == State.CATCH_PAUSE_STATE:
		anim_scale = FISH_ANIM_TIRED_SCALE if _energy <= 0.0 else FISH_ANIM_FIGHT_SCALE
	_turn_fish(delta)
	_fish_anim += delta * FISH_ANIM_FPS * anim_scale
	var fast := _fish_fleeing or (_state == State.FIGHT and _energy > 0.0)
	var frames: Array
	if _fish_big:
		frames = FISH_BIG_FAST_FRAMES if fast else FISH_BIG_CALM_FRAMES
	else:
		frames = FISH_FAST_FRAMES if fast else FISH_CALM_FRAMES
	var want: Vector2i = frames[int(_fish_anim) % frames.size()]
	if want.x != _fish_frame:
		_set_fish_frame(want.x)
	var flip := want.y != 0
	if flip != _fish_flip:
		_fish_flip = flip
		_apply_fish_scale()


func _process_wait(delta: float) -> void:
	# The splash-down plays out first; the idle bob takes over the moment it finishes.
	if not _advance_bobber_seq(delta):
		_tick_bobber_idle(delta)
	if _fish == null or not is_instance_valid(_fish):
		return
	_fish_alpha = minf(1.0, _fish_alpha + delta / FISH_FADE_IN)
	_fish.modulate.a = _fish_alpha * FISH_ALPHA

	var target := _bobber_waterline()
	var to_target := target - _fish.global_position
	var gap := to_target.length()
	_aim_fish(to_target, false)
	# Speeds up a little as it closes -- 100% of its rolled speed at the far end,
	# FISH_CLOSING_BOOST faster by the time it arrives.
	var closed := clampf(1.0 - gap / _fish_start_gap, 0.0, 1.0)
	var speed := _fish_speed * (1.0 + FISH_CLOSING_BOOST * closed)
	if gap <= speed * delta:
		_fish.global_position = target
		_bite_delay = randf_range(BITE_DELAY_MIN, BITE_DELAY_MAX)
		_bite_anim = false
		_bobber_seq = []
		_set_state(State.SINK)
		return
	_fish.global_position += to_target.normalized() * speed * delta


# ============================================================
# 4/5 -- THE BITE
# ============================================================

## The fish is at the bait. After its own little delay it takes the bobber under, and
## the bobber vanishing is the ONLY cue the player gets -- there is no "!" any more.
func _process_sink(delta: float) -> void:
	if _time < _bite_delay:
		_tick_bobber_idle(delta)
		return
	if not _bite_anim:
		_bite_anim = true
		_sfx("bite")
		_play_bobber_seq(BOBBER_BITE_SEQUENCE, BOBBER_BITE_FPS)
	if _advance_bobber_seq(delta):
		return
	# Gone. One big boil of water at its mouth, and the window to strike opens.
	_bobber.visible = false
	_fish_splash("big")
	_set_state(State.BITE)


func _process_bite(_delta: float) -> void:
	if _time < BITE_WINDOW:
		return
	# The strike window closed: it has taken the bait and gone.
	_scare_fish()
	_begin_retract(TOO_LATE_MESSAGE)


## Hooked in time: the line runs straight to the fish (the bobber is already under).
func _hook() -> void:
	_tension = 0.0
	_energy = float(_stats["energy"])
	_fight_side = 1.0 if randf() < 0.5 else -1.0
	_fight_switch = randf_range(FIGHT_SWITCH_MIN, FIGHT_SWITCH_MAX)
	_rest_left = 0.0
	_yanking = false
	_fight_sfx_timer = randf_range(FIGHT_SFX_GOOD_MIN, FIGHT_SFX_GOOD_MAX)
	if _fish != null and is_instance_valid(_fish):
		# The fish's own `initial_distance` is how far past THE BOBBER the strike runs it
		# out -- added to wherever the cast landed, not measured from the player, because
		# the throw is half the Fishing_Zone rectangle and differs from spot to spot. That
		# is where the leash starts: it works in and out from there and only ever gets
		# closer by being reeled. It swims out there at its fighting speed, never teleports.
		# Clamped into the zone: a leash outside the water would be unreelable, or would
		# be sitting on the break-free line before the fight had started.
		var bobber_radial := (_bobber_pos - _player.global_position).dot(_axis)
		_leash = clampf(bobber_radial + float(_stats["initial_distance"]), _catch_radial,
				maxf(_catch_radial, _lost_radial - FIGHT_SURGE))
		_set_surge(1.0)
		var radial := (_fish.global_position - _player.global_position).dot(_axis)
		_yanking = radial < _leash
		if not _yanking:
			_clamp_to_leash()
		# Turns on the spot about its head, which is what the hook is through. The
		# target has to come with it, or _turn_fish() simply walks it back round.
		_fish.rotation += PI
		_fish_aim = -_fish_aim
		_fish_aim_target = _fish_aim
	_set_state(State.FIGHT)


# ============================================================
# 6 -- TUG OF WAR
# ============================================================

func _process_fight(delta: float) -> void:
	if _fish == null or not is_instance_valid(_fish):
		_begin_retract(ESCAPED_MESSAGE)
		return

	# The strike's run for open water. It swims out at its FIGHTING speed and nothing else
	# happens until it gets there: no side-to-side run to counter, no line load either
	# way, no energy burnt. It is the "it's running!" beat, and the fight starts when it
	# stops running.
	if _yanking:
		var out_now := (_fish.global_position - _player.global_position).dot(_axis)
		var step_out := minf(float(_stats["lateral_speed"]) * delta, _leash - out_now)
		if step_out > 0.0:
			_fish.global_position += _axis * step_out
			_aim_fish(_axis, false)
			_clamp_to_cone()
			_tick_fight_splashes(delta, "correct")
			_tick_fight_sfx(delta, false)
			return
		# Arrived: it turns and the fight begins from here.
		_yanking = false
		_fight_switch = randf_range(FIGHT_SWITCH_MIN, FIGHT_SWITCH_MAX)

	var resting := _rest_left > 0.0
	if resting:
		_rest_left -= delta
		if _rest_left <= 0.0:
			# Second wind: back to full energy and off it goes again.
			_energy = float(_stats["energy"])
			_fight_switch = randf_range(FIGHT_SWITCH_MIN, FIGHT_SWITCH_MAX)

	_fight_switch -= delta
	if _fight_switch <= 0.0:
		_fight_side = -_fight_side
		_fight_switch = randf_range(FIGHT_SWITCH_MIN, FIGHT_SWITCH_MAX)

	# The player counters the way the fish is TRAVELLING, not where it happens to be:
	# running left means pull right. _fight_side is its current direction along _perp.
	var pulled := _axis_input()
	var correct := pulled != 0.0 and pulled == -_fight_side
	if resting:
		# The whole point of the rest: the line settles back to neutral from either side
		# while the player mashes, so the next run starts from a clean slate.
		_tension = move_toward(_tension, 0.0, TENSION_REST_RECOVER * delta)
	elif pulled != 0.0 and not correct:
		_tension += TENSION_WRONG * delta
	elif correct:
		# Costs a tight line nothing; a SLACK one is taken back up towards neutral, so
		# countering also recovers a line that was nearly dropped.
		if _tension < 0.0:
			_tension = move_toward(_tension, 0.0, TENSION_CORRECT_RECOVER * delta)
		else:
			_tension += TENSION_CORRECT * delta
		_energy -= ENERGY_DRAIN * delta
	else:
		_tension -= TENSION_DECAY * delta
	# It tires whatever the player does: a flat slice of its own bar every second, so a
	# fish always blows inside twenty seconds even if it is never countered once.
	if not resting:
		_energy -= float(_stats["energy"]) * ENERGY_BLEED_FRACTION * delta
		if _energy <= 0.0:
			_rest_left = float(_stats["recharge_time"])
	# Blown beats everything: a fish with nothing left barely ripples the surface.
	var pulling_wrong := pulled != 0.0 and not correct
	if resting:
		_tick_fight_splashes(delta, "tired")
	else:
		_tick_fight_splashes(delta, "wrong" if pulling_wrong else "correct")
	_tick_fight_sfx(delta, pulling_wrong and not resting)

	if absf(_tension) >= float(_stats["line_strength"]):
		_scare_fish()
		# Which end of the line gave: red (pulled the wrong way until it snapped) or
		# blue (let it go slack until the hook fell out).
		_begin_retract(BREAK_MESSAGE if _tension > 0.0 else SLACK_MESSAGE)
		return

	# Side to side across the cast, and in and out along it between the leash and
	# FIGHT_SURGE beyond it. Countering slows the whole run down, pulling the wrong way
	# lets it go faster, and a blown fish barely moves.
	var tired := TIRED_SPEED_FACTOR if resting else 1.0
	var input_factor := 1.0
	if pulled != 0.0:
		input_factor = FIGHT_INPUT_SLOW if correct else FIGHT_INPUT_FAST
	var run := _perp * _fight_side * float(_stats["lateral_speed"]) \
			+ _axis * _surge_dir * _surge_speed
	_fish.global_position += run * tired * input_factor * delta
	_aim_fish(run, false)
	# Pinned against a wall it keeps swimming, it just stops making ground.
	_clamp_to_cone()
	if not _yanking:
		_clamp_to_leash()
	_check_broke_free()


## One Space/Enter press while the fish is blown: drags the leash in a notch and hauls the
## fish in with it. Pressing at any other time is a mistake, handled in _input().
func _reel_step() -> void:
	var step := float(_stats["reel_step"])
	_leash = maxf(0.0, _leash - step)
	_fish.global_position -= _axis * step
	_yanking = false
	_clamp_to_cone()
	_clamp_to_leash()
	if _leash <= _catch_radial:
		_start_catch()


## The fish has run all the way out to the edge of its water opposite the player: it is
## gone, and there is nothing the player can do about it. Returns true when it fires.
func _check_broke_free() -> bool:
	if is_inf(_lost_radial) or _fish == null or not is_instance_valid(_fish):
		return false
	if (_fish.global_position - _player.global_position).dot(_axis) < _lost_radial:
		return false
	_scare_fish()
	_begin_retract(BROKE_FREE_MESSAGE)
	return true


## Holds the fish between its leash and FIGHT_SURGE beyond it, turning it round at either
## end so it works in and out rather than drifting away for good.
func _clamp_to_leash() -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	var radial := (_fish.global_position - _player.global_position).dot(_axis)
	if radial < _leash:
		_fish.global_position += _axis * (_leash - radial)
		_set_surge(1.0)
	elif radial > _leash + FIGHT_SURGE:
		_fish.global_position -= _axis * (radial - _leash - FIGHT_SURGE)
		_set_surge(-1.0)


func _set_surge(direction: float) -> void:
	_surge_dir = direction
	_surge_speed = randf_range(FIGHT_SURGE_SPEED_MIN, FIGHT_SURGE_SPEED_MAX)


## DEBUG ONLY: floats the rolled species' name over the silhouette the moment it spawns,
## so there is no guessing which fish is being fought. Never built outside debug mode.
func _show_name_tag() -> void:
	if not DebugMode.is_enabled() or _fish_species == "":
		return
	_name_tag = NameTag.new()
	_name_tag.text = OverworldPokemonData.display_name(_fish_species)
	_name_tag.width = NAME_TAG_WIDTH
	_name_tag.font_size = NAME_TAG_FONT_SIZE
	_name_tag.colour = NAME_TAG_COLOUR
	_name_tag.z_as_relative = false
	_name_tag.z_index = NAME_TAG_Z
	add_child(_name_tag)
	_tick_name_tag()


## Keeps the tag over the fish's head. It is a child of THIS node rather than of the
## fish, so it never picks up the silhouette's rotation or its mirroring -- a name tag
## swinging round and drawing backwards would be worse than no name tag.
func _tick_name_tag() -> void:
	if _name_tag == null or not is_instance_valid(_name_tag):
		return
	var on := _fish != null and is_instance_valid(_fish) and _fish.visible
	_name_tag.visible = on
	if on:
		_name_tag.global_position = _fish.global_position + Vector2(0.0, -NAME_TAG_OFFSET)


## Water running off the Pokémon while it hangs on the rod, from the moment it comes out
## until it is dropped back in. Nothing drips once it is on its way back to the sea.
func _tick_drips(delta: float) -> void:
	if _state != State.CATCH_YANK and _state != State.CATCH_MESSAGE:
		return
	if _caught == null or not is_instance_valid(_caught):
		return
	_drip_timer += delta
	if _drip_timer < DRIP_INTERVAL:
		return
	_drip_timer = 0.0
	if _drips == null or not is_instance_valid(_drips):
		_drips = DripLayer.new()
		_drips.z_as_relative = false
		_drips.z_index = DRIP_Z
		add_child(_drips)
	var half_w := _caught_cell.x * _caught_scale * 0.5
	var half_h := _caught_cell.y * _caught_scale * 0.5
	var from := _caught.global_position \
			+ Vector2(randf_range(-half_w * 0.55, half_w * 0.55), half_h * 0.5)
	var colours: Array = PokemonSurfacer.SPLASH_COLOURS
	_drips.spawn(from, colours[randi() % colours.size()], DRIP_LIFE)


## One burst of water at the hooked fish's mouth (its head is the sprite's origin).
func _fish_splash(tier: String) -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	var cfg: Dictionary = FIGHT_SPLASH.get(tier, {})
	if cfg.is_empty():
		return
	# Rings under the pixels, both from the fish's mouth -- its head IS the sprite origin.
	WaterRipples.fire(get_parent(), _fish.global_position,
			float(cfg.get("ripple", 10.0)), float(cfg.get("rings", 1.0)), SPLASH_Z - 1)
	PixelBurst.fire(get_parent(), _fish.global_position, PokemonSurfacer.SPLASH_COLOURS,
			int(cfg["count"]), float(cfg["speed"]), float(cfg["width"]), SPLASH_Z)


## The splash SOUNDS, which run on their own random interval -- longer and calmer while
## the player is countering (or leaving it alone), short and busy while they are pulling
## the wrong way and the fish is winning.
func _tick_fight_sfx(delta: float, wrong: bool) -> void:
	_fight_sfx_timer -= delta
	if _fight_sfx_timer > 0.0:
		return
	if wrong:
		_sfx("splash_bad", _splash_pitch())
		_fight_sfx_timer = randf_range(FIGHT_SFX_BAD_MIN, FIGHT_SFX_BAD_MAX)
	else:
		_sfx("splash_good" if randf() < 0.5 else "splash_good2", _splash_pitch())
		_fight_sfx_timer = randf_range(FIGHT_SFX_GOOD_MIN, FIGHT_SFX_GOOD_MAX)


func _splash_pitch() -> float:
	return 1.0 + randf_range(-FIGHT_SFX_PITCH, FIGHT_SFX_PITCH)


## The jingle waits out the Pokémon's cry and then plays, wherever the catch sequence has
## got to by then -- it is chasing the cry, not the animation.
func _tick_jingle(delta: float) -> void:
	if _jingle_left < 0.0:
		return
	_jingle_left -= delta
	if _jingle_left > 0.0:
		return
	_jingle_left = -1.0
	_sfx("jingle")


## Keeps the fish boiling the water while it is hooked, at whatever rate `tier` asks for.
func _tick_fight_splashes(delta: float, tier: String) -> void:
	var cfg: Dictionary = FIGHT_SPLASH.get(tier, {})
	var interval := float(cfg.get("interval", 0.0))
	if interval <= 0.0:
		return
	_splash_timer += delta
	if _splash_timer < interval:
		return
	_splash_timer = 0.0
	_fish_splash(tier)


## Keeps the fish inside the cone opening out from the player, and inside the
## Fishing_Zone's own side walls.
##
## It does NOT turn the fish round. A fish pinned against either wall goes on swimming
## that way and just stops getting anywhere -- swimming on the spot until its own switch
## timer runs out -- which is what a fish on a line actually does. Bouncing it off the
## wall made it flick back and forth several times a second.
func _clamp_to_cone() -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	var from_player := _fish.global_position - _player.global_position
	var radial := from_player.dot(_axis)
	var across := from_player.dot(_perp)
	# How far out it is as a fraction of the cast. Floored at 0 but NOT capped at 1: past
	# the splashdown the cone carries on opening, and the zone's side walls take over.
	var out := maxf(0.0, (radial - _catch_radial) / maxf(1.0, _cast_radial - _catch_radial))
	var room := FIGHT_CONE_MIN + FIGHT_CONE_AT_CAST * pow(out, FIGHT_CONE_POWER)
	# The cone and the Fishing_Zone rectangle, whichever is tighter on each side. The
	# rectangle's walls are not symmetrical about the player, so they are kept apart.
	var low := maxf(-room, _side_min)
	var high := minf(room, _side_max)
	if across >= low and across <= high:
		return
	_fish.global_position += _perp * (clampf(across, low, high) - across)


## -1 / 0 / +1 along the axis across the cast. Mirrors the player's own WASD + arrows.
func _axis_input() -> float:
	var low := "left" if _perp == Vector2.RIGHT else "up"
	var high := "right" if _perp == Vector2.RIGHT else "down"
	var value := 0.0
	if _held(high):
		value += 1.0
	if _held(low):
		value -= 1.0
	return value


func _held(direction: String) -> bool:
	match direction:
		"left":
			return Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A)
		"right":
			return Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D)
		"up":
			return Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W)
		"down":
			return Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)
	return false


# ============================================================
# THE CATCH
# ============================================================

func _start_catch() -> void:
	_aim_fish(_player.global_position - _fish.global_position)
	_fish_fleeing = false
	# Its own cry the moment it is landed, with the jingle queued up behind it.
	var cry := SoundManagerScript.cry_length(_fish_species)
	if cry > 0.0 and SoundManagerScript.play_cry(_fish_species):
		_jingle_left = maxf(0.0, cry - JINGLE_AFTER_CRY_LEAD)
	else:
		_jingle_left = 0.0
	# Hand the line over from the fish to the bobber HERE, at the spot it was landed.
	# _update_line() stops following the fish the moment the state leaves FIGHT, and the
	# bobber has been parked out at the original cast splashdown since the hook -- so
	# leaving this until after the pause snapped the line out to full cast range for a
	# tenth of a second.
	_place_bobber(_fish.global_position)
	_set_state(State.CATCH_PAUSE_STATE)


func _process_catch_pause() -> void:
	if _time < CATCH_PAUSE:
		return
	_rod_angle = _raised_angle()
	_apply_rod()
	_build_caught()
	# It comes out of the water where it was landed -- the bobber was already moved onto
	# the fish in _start_catch().
	if _fish != null and is_instance_valid(_fish):
		_fish_splash("huge")
		_sfx("caught")
		_place_bobber(_fish.global_position)
		_fish.visible = false
	# Chinchou, Lanturn, Finneon and Lumineon carry a lure light, lit the instant they
	# are out of the water. Every other species gets null back and nothing happens.
	PokemonGlow.attach(self, _caught, _fish_species)
	_bobber.visible = true
	_set_bobber_frame(BOBBER_CAST_FRAME)
	_carry_caught()
	_set_state(State.CATCH_YANK)


func _build_caught() -> void:
	_caught = Sprite2D.new()
	_caught.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Hauled up out of the water in front of everything.
	_caught.z_as_relative = false
	_caught.z_index = CAUGHT_Z
	_caught.centered = true
	var sheet: Texture2D = load(OverworldPokemonData.sheet_path(_fish_species))
	if sheet == null:
		return
	_caught_cell = Vector2(sheet.get_width() / 4.0, sheet.get_height() / 4.0)
	# A flat half scale: the sprites are already drawn the size they want to be, and the
	# species' `scale` belongs to its overworld spawns, not to what comes off a line.
	_caught_scale = 0.5
	_caught.scale = Vector2(_caught_scale, _caught_scale)
	_set_caught_row(1)  # idle_left
	# Hauled out sideways: the left-facing frame turned a quarter turn clockwise.
	_caught.rotation_degrees = 90.0
	add_child(_caught)
	if _fish != null and is_instance_valid(_fish):
		_caught.global_position = _fish.global_position


func _set_caught_row(row: int) -> void:
	if _caught == null:
		return
	_caught_row = row
	var atlas := AtlasTexture.new()
	atlas.atlas = load(OverworldPokemonData.sheet_path(_fish_species))
	atlas.region = Rect2(0.0, row * _caught_cell.y, _caught_cell.x, _caught_cell.y)
	atlas.filter_clip = true
	_caught.texture = atlas
	_scan_caught_bbox()


## The opaque bounding box of the row now on screen, in texture pixels measured from the
## cell's top-left. Scanned once per row change -- it is what _carry_caught() hangs the
## Pokémon by, and a 64px cell of mostly empty space makes the difference obvious.
func _scan_caught_bbox() -> void:
	_caught_bbox = Rect2(Vector2.ZERO, _caught_cell)
	var sheet: Texture2D = load(OverworldPokemonData.sheet_path(_fish_species))
	if sheet == null:
		return
	var img := sheet.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var cell_w := int(_caught_cell.x)
	var cell_h := int(_caught_cell.y)
	var top := int(_caught_row) * cell_h
	var lo := Vector2i(cell_w, cell_h)
	var hi := Vector2i(-1, -1)
	for y in cell_h:
		for x in cell_w:
			if top + y >= img.get_height() or x >= img.get_width():
				continue
			if img.get_pixel(x, top + y).a <= 0.0:
				continue
			lo.x = mini(lo.x, x)
			lo.y = mini(lo.y, y)
			hi.x = maxi(hi.x, x)
			hi.y = maxi(hi.y, y)
	if hi.x < 0:
		return
	# Continuous coordinates: pixel n covers [n, n+1).
	_caught_bbox = Rect2(Vector2(lo.x, lo.y), Vector2(hi.x - lo.x + 1, hi.y - lo.y + 1))


func _process_catch_yank(delta: float) -> void:
	# Bobber flies home; the Pokémon hangs off the bottom of it.
	var tip := _tip_park()
	var to_tip := tip - _bobber_pos
	var step := CATCH_YANK_SPEED * delta
	if to_tip.length() <= step:
		_place_bobber(tip)
		_carry_caught()
		_show_catch_message()
		return
	_place_bobber(_bobber_pos + to_tip.normalized() * step)
	_carry_caught()


## Hangs the Pokémon so the TOP of its visible pixels sits on the BOTTOM of the bobber's,
## centred under it. The sprite cell is mostly empty and is turned a quarter turn while
## it is being hauled up, so neither the cell's centre nor its edge is anywhere near the
## fish -- the bounding box has to be rotated and scaled with the sprite and measured.
func _carry_caught() -> void:
	if _caught == null or not is_instance_valid(_caught):
		return
	var target := _bobber_low()
	var basis := Transform2D(_caught.rotation, Vector2.ZERO)
	var centre := _caught_cell * 0.5
	var lo_x := INF
	var hi_x := -INF
	var top_y := INF
	for corner in [_caught_bbox.position,
			Vector2(_caught_bbox.end.x, _caught_bbox.position.y),
			Vector2(_caught_bbox.position.x, _caught_bbox.end.y),
			_caught_bbox.end]:
		var offset: Vector2 = basis.basis_xform((corner - centre) * _caught_scale)
		lo_x = minf(lo_x, offset.x)
		hi_x = maxf(hi_x, offset.x)
		top_y = minf(top_y, offset.y)
	_caught.global_position = target - Vector2((lo_x + hi_x) * 0.5, top_y)


func _show_catch_message() -> void:
	_message_open = true
	_set_state(State.CATCH_MESSAGE)
	var species_name := OverworldPokemonData.display_name(_fish_species)
	MapManager.show_message_then("You caught a %s!" % species_name,
			Callable(self, "_on_catch_message_ok"))


func _on_catch_message_ok() -> void:
	# _on_ok_pressed() hands a pending callback the press and returns WITHOUT closing the
	# box -- a chain is expected to put the next line up. This is the end of the chain, so
	# it closes it (the same thing Player_House_Upstairs does). can_move stays false:
	# _hide_message() restores it as `not cutscene_active`, which is still true here.
	MapManager._hide_message()
	_restore_sound()
	_message_open = false
	if _caught == null or not is_instance_valid(_caught):
		_finish()
		return
	# Back to a normal standing sprite, still facing the player, and it hops back in --
	# it only turns to face the way it is going once it is clear of the rod.
	_caught.rotation_degrees = 0.0
	_hop_dir = _dir_vector(water_dir)
	_hop_turned = false
	_set_caught_row(int(OverworldPokemon.ROWS.get(_opposite(water_dir), 0)))
	# Standing upright now, and on a different row: re-hang it before it jumps, or the
	# hop starts from wherever the sideways pose happened to leave it.
	_carry_caught()
	_line.visible = false
	_bobber.visible = false
	_set_state(State.CATCH_HOP)


func _process_catch_hop(delta: float) -> void:
	var t := clampf(_time / HOP_TIME, 0.0, 1.0)
	# Two halves. Up off the rod, easing to the top and hardly travelling at all, then a
	# quickening drop that carries it away -- so a downward hop reads as "jumped up off
	# the line and dived in", not "slid off the end of it".
	var height := 0.0
	var travel := 0.0
	if t < HOP_RISE:
		height = HOP_HEIGHT * sin(PI * 0.5 * (t / HOP_RISE))
		travel = 0.15
	else:
		var fall := (t - HOP_RISE) / maxf(0.01, 1.0 - HOP_RISE)
		height = HOP_HEIGHT * (1.0 - fall * fall)
		travel = 0.15 + 0.85 * fall
	_caught.offset.y = -height / maxf(_caught_scale, 0.01)
	_caught.global_position += _hop_dir * HOP_SPEED * travel * delta
	if not _hop_turned and _time >= HOP_TURN_TIME:
		_hop_turned = true
		_set_caught_row(int(OverworldPokemon.ROWS.get(water_dir, 0)))
	if t >= 1.0:
		_enter_water()


## The same sink PokemonSkittish uses when it bolts into the sea -- shared shader, shared
## splash colours -- so a Pokémon going under looks the same wherever it happens.
func _enter_water() -> void:
	_caught.offset.y = 0.0
	var half := _caught_cell.y * _caught_scale * 0.5
	_water_y = _caught.global_position.y + half
	_sink_from = _caught.global_position.y
	_sink_distance = (_caught_cell.y + WATER_CLEAR_ROWS + WATER_FADE_ROWS) * _caught_scale
	_water_material = ShaderMaterial.new()
	_water_material.shader = PokemonSurfacer.water_shader()
	_water_material.set_shader_parameter("water_colour", PokemonSurfacer.WATER_COLOUR)
	_water_material.set_shader_parameter("deep_colour", PokemonSurfacer.DEEP_COLOUR)
	_water_material.set_shader_parameter("tint_rows", 8.0)
	_water_material.set_shader_parameter("above_tint", 0.0)
	_water_material.set_shader_parameter("fade_rows", WATER_FADE_ROWS)
	# The top-down reveal is the surfacing template's trick; push it past the sheet.
	_water_material.set_shader_parameter("reveal_row", _caught_cell.y * 4.0)
	_water_material.set_shader_parameter("reveal_soft", 1.0)
	_caught.material = _water_material
	_update_waterline()
	_splash(Vector2(_caught.global_position.x, _water_y))
	# The same big splash it came OUT on. A whole Pokémon going back under is not the
	# little plop a bobber makes -- that stays for the cast and for a skittish one bolting.
	_sfx("caught")
	_set_state(State.CATCH_SINK)


func _process_catch_sink() -> void:
	var t := clampf(_time / SINK_TIME, 0.0, 1.0)
	# Snapped to whole art rows so the blue creeps up a row at a time.
	_caught.global_position.y = _sink_from + snappedf(_sink_distance * t, _caught_scale)
	_update_waterline()
	if t >= 1.0:
		_finish()


func _update_waterline() -> void:
	if _water_material == null:
		return
	var rows_from_cell_top := (_water_y - _caught.global_position.y
			+ _caught_cell.y * _caught_scale * 0.5) / _caught_scale
	# _caught_row, NOT a row worked out from water_dir: the hop turns the sprite round
	# part way through, and measuring the waterline inside the wrong row of the sheet is
	# what stopped the blue creeping up it.
	var waterline: float = _caught_row * _caught_cell.y + rows_from_cell_top
	_water_material.set_shader_parameter("waterline_row", waterline)
	_water_material.set_shader_parameter("bottom_row",
			waterline + WATER_CLEAR_ROWS + WATER_FADE_ROWS)


# ============================================================
# FAILURE / CANCEL
# ============================================================

## The fish bolts and fades out, on the darting frames.
func _scare_fish() -> void:
	if _fish == null or not is_instance_valid(_fish):
		return
	_fish_fleeing = true
	_fish.visible = true
	var away := (_fish.global_position - _player.global_position)
	if away.length_squared() <= 0.0001:
		away = _cast_dir
	_aim_fish(away)


## Starts the retract. `message` is shown at the SAME TIME, over the running animation --
## control comes back once both have finished.
func _begin_retract(message: String) -> void:
	if _state == State.RETRACT or _state == State.DONE:
		return
	# A message means the player still has something to read: the music waits for them to
	# clear it. A silent bail-out (Escape, or a yank before the fish was on) has nothing
	# to wait for, so it comes straight back.
	if message == "":
		_restore_sound()
	# The line comes back from where it actually WAS. While the fish is on, that is the
	# fish -- the bobber has been under water since the bite and is still parked out at
	# the splashdown, which is what made a break look like a jump to nowhere. It also
	# surfaces on the way out: the bite sequence, played backwards.
	var was_under := not _bobber.visible
	if was_under and _fish != null and is_instance_valid(_fish):
		_place_bobber(_fish.global_position)
	_bobber.visible = true
	if was_under:
		_play_bobber_seq(BOBBER_SURFACE_SEQUENCE, BOBBER_BITE_FPS)
	else:
		_bobber_seq = []
	_retract_done = false
	_set_state(State.RETRACT)
	if message != "":
		_message_open = true
		MapManager.show_message_then(message, Callable(self, "_on_fail_message_ok"))


func _on_fail_message_ok() -> void:
	# End of the chain -- see _on_catch_message_ok().
	MapManager._hide_message()
	_restore_sound()
	_message_open = false
	if _retract_done:
		_finish()


func _process_retract(delta: float) -> void:
	# The bobber popping back up to the surface runs over the top of the reel-in.
	_advance_bobber_seq(delta)
	if _fish != null and is_instance_valid(_fish) and _fish_fleeing:
		_fish.global_position += _fish_aim * FISH_FLEE_SPEED * delta
		_fish.modulate.a = maxf(0.0, _fish.modulate.a - delta * FISH_ALPHA / FISH_FLEE_FADE)

	if _retract_done:
		if _time >= RETRACT_HOLD and not _message_open:
			_finish()
		return

	# Rod snaps back up as the line comes in.
	_rod_angle = _raised_angle()
	_apply_rod()
	var tip := _tip_park()
	var to_tip := tip - _bobber_pos
	var step := RETRACT_SPEED * delta
	if to_tip.length() <= step:
		_place_bobber(tip)
		_retract_done = true
		_time = 0.0
		return
	_place_bobber(_bobber_pos + to_tip.normalized() * step)


# ============================================================
# LINE / CAMERA / SOUND
# ============================================================

func _update_line() -> void:
	if _line == null or not _line.visible:
		return
	var from := _rod_tip()
	var to := from
	if _state == State.FIGHT and _fish != null and is_instance_valid(_fish):
		to = _fish.global_position
	else:
		to = _bobber_tie()
	_line.points = PackedVector2Array([to_local(from), to_local(to)])
	_line.default_color = _line_colour()


## White at rest, cooling to a dark blue as the line goes slack and heating to a dark red
## as it is about to snap.
func _line_colour() -> Color:
	if _state != State.FIGHT:
		return LINE_NEUTRAL
	var t := clampf(_tension / maxf(1.0, float(_stats["line_strength"])), -1.0, 1.0)
	var near := LINE_TIGHT_NEAR
	var far := LINE_TIGHT_FAR
	if t < 0.0:
		t = -t
		near = LINE_SLACK_NEAR
		far = LINE_SLACK_FAR
	if t <= 0.5:
		return LINE_NEUTRAL.lerp(near, t * 2.0)
	return near.lerp(far, (t - 0.5) * 2.0)


## Frames whatever the player is watching -- the bobber, then the hooked fish -- by
## offsetting the player's own camera, the way the placement tool does.
func _update_camera(delta: float) -> void:
	if _player == null or _player.camera == null:
		return
	var focus := _player.global_position
	if _state == State.FIGHT and _fish != null and is_instance_valid(_fish):
		focus = _fish.global_position
	elif _state in [State.CAST, State.WAIT, State.SINK, State.BITE]:
		focus = _bobber.global_position
	var want := focus - _player.global_position
	_player.camera.offset = _player.camera.offset.lerp(want, clampf(CAMERA_LERP * delta, 0.0, 1.0))


func _sfx(key: String, pitch: float = 1.0) -> void:
	var path: String = SFX.get(key, "")
	if path != "" and ResourceLoader.exists(path):
		SoundManagerScript.play_sfx_from_path(path, pitch)


## Music back up, sea back down to the level the player's own position asks for. Safe to
## call more than once -- both ends are "fade towards", not "start a fade".
func _restore_sound() -> void:
	SoundManagerScript.fade_bgm(1.0, BGM_FADE_IN, BGM_FADE_IN_DELAY)
	if _zone != null and is_instance_valid(_zone):
		_zone.clear_ambience()


# ============================================================
# DEBUG NAME TAG
# ============================================================

## The species' name in a small outlined string. Drawn rather than a Label so it sits in
## world space with everything else, the same way PokemonSpawnMarker draws its id.
## An inner class is its OWN script and cannot see the outer one's constants, so the
## three numbers are handed to it when it is built rather than read from up here.
class NameTag extends Node2D:
	var text: String = ""
	var width: float = 160.0
	var font_size: int = 8
	var colour: Color = Color.WHITE

	func _draw() -> void:
		if text == "":
			return
		var font := ThemeDB.fallback_font
		var at := Vector2(-width * 0.5, 0.0)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width,
				font_size, 2, Color.BLACK)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width,
				font_size, colour)


# ============================================================
# DRIP LAYER
# ============================================================

## Single pixels of sea water running off a Pokémon held up on the line, falling away
## and fading out. Its own Node2D so it can sit at DRIP_Z above everything; drawn the
## same hand-rolled way PixelBurst is, since a particle system cannot express "fade out
## where it happens to be".
class DripLayer extends Node2D:
	const GRAVITY := 130.0

	var _drops: Array = []

	func spawn(global_point: Vector2, colour: Color, life: float) -> void:
		_drops.append({
			"pos": to_local(global_point),
			"vel": Vector2(randf_range(-3.0, 3.0), randf_range(2.0, 14.0)),
			"life": life,
			"max_life": maxf(life, 0.01),
			"colour": colour,
		})

	func _process(delta: float) -> void:
		var alive: Array = []
		for drop in _drops:
			drop["vel"].y += GRAVITY * delta
			drop["pos"] += drop["vel"] * delta
			drop["life"] -= delta
			if drop["life"] > 0.0:
				alive.append(drop)
		_drops = alive
		queue_redraw()

	func _draw() -> void:
		for drop in _drops:
			var colour: Color = drop["colour"]
			colour.a = clampf(drop["life"] / float(drop["max_life"]), 0.0, 1.0)
			draw_rect(Rect2(drop["pos"], Vector2.ONE), colour)


# ============================================================
# HELPERS / TEARDOWN
# ============================================================

static func _opposite(direction: String) -> String:
	match direction:
		"up": return "down"
		"down": return "up"
		"left": return "right"
		"right": return "left"
	return "down"


## up -> left -> down -> right -> up, the way the player turns while pulling the rod out.
static func _counterclockwise(direction: String) -> String:
	match direction:
		"up": return "left"
		"left": return "down"
		"down": return "right"
		"right": return "up"
	return "down"


static func _dir_vector(direction: String) -> Vector2:
	return OverworldPokemon.DIR_VECTORS.get(direction, Vector2.DOWN)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_set_state(State.DONE)
	_set_shake(0.0)
	if _player != null and is_instance_valid(_player):
		_player.zoom_while_locked = false
	# Belt and braces: the cast ducks the music and raises the sea, and every ending puts
	# both back, but a sequence torn down some other way must not leave the overworld
	# silent or roaring.
	_restore_sound()
	if _player != null and _player.camera != null:
		_player.camera.offset = Vector2.ZERO
	MapManager.finish_fishing()
	queue_free()
