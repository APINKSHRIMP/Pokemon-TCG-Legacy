"""
ATTACK VFX BUILDER -- generates the three data files Attack_VFX.gd plays from.

    py -I "Scripts/Utilities/attack_vfx_build.py"

Reads   Image_Assets/Attack_Effects/**.png   (the Mystery Dungeon move effects)
        Card_Set_Data/*.json                 (every attack in the game)
Writes  Attack_Animation_Data/vfx_manifest.json   part -> frame files + frame size
        Attack_Animation_Data/vfx_recipes.json    recipe id -> body motion + effect steps,
                                                  plus the per-type fallbacks
        Attack_Animation_Data/attack_vfx_map.json attack name -> recipe id (+ how it was chosen)
        Attack_Animation_Data/attack_vfx_report.txt   human-readable list, grouped by recipe

THIS FILE IS THE SOURCE OF TRUTH. Hand-edits to the JSON are overwritten on the next run --
change a recipe in RECIPES, or pin an attack to a recipe in EXACT, then re-run.

------------------------------------------------------------------------------------------
RECIPE FORMAT
    "body":  attacker motion -- "lunge" (physical: tilt, dart forward, bump the defender)
             "hop" (jumps on the spot) | "sway" (side to side) | "shake" | "none"
    "hops":  hop count for "hop" (default 2)
    "steps": effects, played in order. Each step:
        fx      part path under Image_Assets/Attack_Effects ("FireBlast/000", "Ember")
        at      self | target | travel (attacker -> defender) | return (defender -> attacker)
                drop (falls from above onto the defender) | screen (between the two Actives)
                bench (each of the DEFENDER's Benched) | quake (no fx: shakes every Pokemon
                but the attacker)
        size    longest frame side as a fraction of the card's width (sensible default per `at`)
        anchor  "bottom": the frame's bottom edge sits on the anchor point (bolts, pillars, rain)
        off     [x, y] offset in card widths/heights (x mirrors on the opponent's turn)
        dur     seconds for one run of the frames (default: from the frame count)
        loops   runs of the frames (travel steps loop for the whole flight anyway)
        range   [first, last] frame indices to use
        orient  rotate/mirror the frames to face along the attack (frames face RIGHT)
        mirror  false = never flip (text, music notes); default flips on the opponent's turn
        spin    degrees per second
        arc     px a travel step rises at its midpoint (lobbed rocks, eggs, bones)
        time    seconds a travel/drop takes (default 0.42)
        count / stagger / jitter   several copies, `stagger` seconds apart, scattered by
                `jitter` card widths
        par     start together with the previous step instead of after it
        delay   seconds to wait before starting
        hue     hue shift in degrees (recolours an effect: fire -> blue flame, etc.)
        tint    "#rrggbb" multiply colour
        fade    seconds to fade out over the end of the step
        impact  the defender reacts (flash / knock-back) when this step starts. Without one,
                the first target-side step after any travel is the impact.
------------------------------------------------------------------------------------------
"""
import json, os, re, glob, collections

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX_DIR = os.path.join(ROOT, 'Image_Assets', 'Attack_Effects')
CARD_DIR = os.path.join(ROOT, 'Card_Set_Data')
OUT_DIR = os.path.join(ROOT, 'Attack_Animation_Data')

# ========================================================================================
# STEP HELPERS
# ========================================================================================
def _st(at, fx, **kw):
    d = {'fx': fx, 'at': at}
    d.update(kw)
    return d
def S(fx, **kw): return _st('self', fx, **kw)
def T(fx, **kw): return _st('target', fx, **kw)
def P(fx, **kw): return _st('travel', fx, **kw)
def R(fx, **kw): return _st('return', fx, **kw)
def D(fx, **kw): return _st('drop', fx, **kw)
def SC(fx, **kw): return _st('screen', fx, **kw)
def B(fx, **kw): return _st('bench', fx, **kw)
def Q(dur=0.6, **kw):
    d = {'at': 'quake', 'dur': dur}
    d.update(kw)
    return d
def rec(body, *steps, **kw):
    d = {'body': body, 'steps': list(steps)}
    d.update(kw)
    return d
L, H, W, K, N = 'lunge', 'hop', 'sway', 'shake', 'none'

# Hue shifts used to recolour effects.
ICE_HUE = 180      # fire -> icy cyan
PURPLE = 270
BLUE_FIRE = 200

# ========================================================================================
# RECIPES
# ========================================================================================
RECIPES = {
    # ---------------- NORMAL / PHYSICAL HITS ----------------
    'Tackle':           rec(L, T('SimpleAttack')),
    'Pound':            rec(L, T('QuickPunch', size=0.7)),
    'QuickAttack':      rec(L, T('QuickSwipe', orient=True), T('SmallSlash', par=True, delay=0.05)),
    'Headbutt':         rec(L, T('QuickBurst', size=1.1), T('SimpleAttack', par=True)),
    'PowerfulHit':      rec(L, T('PowerfulHit')),
    'BodySlam':         rec(L, T('Slam', size=1.3), Q(0.35, par=True)),
    'TakeDown':         rec(L, T('GigaImpact/000', size=1.0), T('GigaImpact/016', par=True, size=1.1)),
    'GigaImpact':       rec(L, P('GigaImpact/010', orient=True, time=0.22), T('GigaImpact/016', size=1.3),
                            T('GigaImpact/000', par=True, size=1.2), Q(0.4, par=True)),
    'Stomp':            rec(L, T('Slam', size=1.1), T('SandAttack', par=True, size=0.7, off=[0, 0.3])),
    'Trample':          rec(L, T('Slam', size=1.1, count=2, stagger=0.18, jitter=0.25), Q(0.5, par=True)),
    'Rollout':          rec(L, T('SpiralSpinIn', size=0.8, hue=30, tint='#e0b070'), T('Slam', size=1.1)),
    'Spin':             rec(L, T('SpinningSlash', size=1.0), T('SimpleAttack', par=True, delay=0.15, size=0.8)),
    'Thrash':           rec(L, T('Slam', count=3, stagger=0.15, jitter=0.25, size=1.0), T('PowerfulHit', size=0.9)),
    'Wrap':             rec(W, T('VineWrap', tint='#e8d8b0', size=1.1, loops=1, dur=0.6)),
    'Constrict':        rec(W, T('VineWrap', hue=PURPLE, size=1.1, dur=0.6), T('GrabCrush', size=0.9)),
    'Squeeze':          rec(L, T('GrabCrush', size=1.1)),
    'Bind':             rec(W, T('VineWrap', tint='#b0b0b0', size=1.1, dur=0.6)),
    'Lick':             rec(L, T('Lick', size=0.7, count=2, stagger=0.2, jitter=0.15)),
    'TailWhip':         rec(W, T('Swagger', size=0.6, count=2, stagger=0.2, jitter=0.2)),
    'TailSlap':         rec(L, T('OneSlap', size=0.9)),
    'Slap':             rec(L, T('DoubleSlap', size=0.8)),
    'DoubleSlap':       rec(L, T('DoubleSlap', size=0.8, count=2, stagger=0.22, jitter=0.18)),
    'Scratch':          rec(L, T('QuickSwipe', orient=True, size=0.9)),
    'FurySwipes':       rec(L, T('MultipleClawAttack/000', size=0.9, count=3, stagger=0.16, jitter=0.2),
                            T('MultipleClawAttack/008', size=1.0)),
    'Slash':            rec(L, T('SwipeAttack', size=1.0)),
    'DoubleClaw':       rec(L, T('DoubleClaw', size=1.0)),
    'DoubleSlash':      rec(L, T('DoubleSlash', size=1.0), T('SmallSlash', par=True, delay=0.15)),
    'CrossCut':         rec(L, T('DarkSlash', hue=-60, size=1.0)),
    'SpinningSlash':    rec(L, T('SpinningSlash', size=1.1)),
    'LightSlash':       rec(L, T('LightSlash', orient=True, size=1.0), T('SmallSlash', par=True, delay=0.1)),
    'Peck':             rec(L, T('SmallSlash', size=0.7)),
    'DrillPeck':        rec(L, T('SmallSlash', size=0.8, count=3, stagger=0.1, jitter=0.12), T('QuickBurst', size=0.8)),
    'FuryAttack':       rec(L, T('SmallSlash', size=0.7, count=4, stagger=0.12, jitter=0.25)),
    'HornAttack':       rec(L, T('ViceGrip', size=0.9)),
    'HornDrill':        rec(L, T('SpinningSlash', size=0.9), T('PowerfulHit', size=1.1)),
    'Megahorn':         rec(L, T('ViceGrip', size=1.1), T('PowerfulHit', size=1.2, par=True, delay=0.1), Q(0.3, par=True)),
    'WingAttack':       rec(L, T('Feathers', size=1.0), T('SimpleAttack', par=True, size=0.7)),
    'BraveBird':        rec(L, P('BraveBird', orient=True, time=0.22, size=0.7), T('PowerfulHit', size=1.2)),
    'Fly':              rec(L, S('FeatherFall', size=1.0), T('PowerfulHit', size=1.0)),
    'Gust':             rec(W, T('Gust', size=1.1)),
    'Whirlwind':        rec(W, T('GustWithFeathers', size=1.2)),
    'Twister':          rec(W, T('Gust', size=1.2, hue=120, tint='#a0ffc0'), T('Gust', size=1.0, par=True, delay=0.2, off=[0.2, 0.0])),
    'Hurricane':        rec(W, SC('Gust', size=1.6), T('GustWithFeathers', size=1.2, par=True, delay=0.2)),
    'AirCutter':        rec(W, T('AirCutter', size=1.4)),
    'AirSlash':         rec(W, T('AirSlash', size=1.0, count=2, stagger=0.15, jitter=0.15)),
    'RazorWind':        rec(H, P('RazorWind/Effect', spin=720, size=0.55), T('RazorWind/Projectile', size=0.8, spin=540)),
    'Sonicboom':        rec(W, P('HarshSound', orient=True, size=0.7), T('QuickBurst', size=0.9)),
    'Swift':            rec(H, P('SpinningStar', spin=540, size=0.25, count=5, stagger=0.08, jitter=0.15), T('StarShine', size=1.0)),
    'StarStrike':       rec(H, D('StarStrikeBlue', size=0.9, time=0.3), T('Twinkle', size=0.9)),
    'ShootingStar':     rec(H, D('StarStrikeRed', size=0.8, time=0.3, count=3, stagger=0.12, jitter=0.2), T('StarShine', size=1.0)),
    'StarBeam':         rec(H, P('StarBeam', orient=True, size=0.7), T('TwinklingStar', size=0.8)),
    'Wish':             rec(H, S('Wish', size=1.2, off=[0, -0.35]), S('Twinkle', size=0.8)),
    'PayDay':           rec(L, T('SimpleAttack'), T('Twinkle', size=0.6, count=3, stagger=0.1, jitter=0.25)),
    'Explosion':        rec(K, S('Explosion', size=2.2), T('Explosion', size=2.0, par=True, delay=0.15), Q(0.7, par=True)),
    'Selfdestruct':     rec(K, S('Selfdestruct', size=2.0), T('SmallBomb', size=1.2, par=True, delay=0.15), Q(0.5, par=True)),
    'EggBomb':          rec(H, P('EggBomb/000', arc=90, spin=360, size=0.25), T('EggBomb/001', size=1.1)),
    'Barrage':          rec(H, P('Barrage/001', arc=70, size=0.25, count=3, stagger=0.15), T('Barrage/000', size=0.9, count=2, stagger=0.12, jitter=0.15)),
    'SmallBomb':        rec(H, T('SmallBomb', size=1.2)),
    'MiniExplosions':   rec(H, T('MiniExplosions', size=0.8, count=3, stagger=0.12, jitter=0.25)),
    'HyperBeam':        rec(K, S('PowerUpAbsorb', size=1.0, dur=0.6), P('AuraSphere', size=0.6, hue=-150, time=0.3),
                            T('Explosion', size=1.6), Q(0.5, par=True)),
    'HyperVoice':       rec(K, S('HyperVoice', size=1.2), P('HarshSound', orient=True, size=0.8, count=2, stagger=0.15), T('Uproar', size=1.2)),
    'Screech':          rec(K, S('HarshSound', orient=True, size=0.8, off=[0.5, 0]), T('MetalSound', size=1.1, hue=-30)),
    'Supersonic':       rec(K, P('PsyWave', orient=True, size=0.5, count=3, stagger=0.1), T('ConfusingHit', size=1.0)),
    'Growl':            rec(K, S('Growl', size=1.2, off=[0.45, 0])),
    'Roar':             rec(K, S('Uproar', size=1.4), T('Growl', size=1.0, par=True, delay=0.2)),
    'Sing':             rec(W, S('SingingToSelf', size=0.5, off=[0.1, -0.35], mirror=False), T('Sing', size=1.0, mirror=False, par=True, delay=0.15)),
    'DarkSing':         rec(W, T('DarkSing', size=1.0, mirror=False)),
    'PerishSong':       rec(W, T('PerishSong', size=1.0, mirror=False)),
    'HealingSong':      rec(W, S('HealingCall', size=1.0, mirror=False)),
    'Whisper':          rec(W, T('Whispering', size=0.6, mirror=False, count=2, stagger=0.2, jitter=0.2)),
    'Attract':          rec(W, P('Heart', size=0.25, count=3, stagger=0.12), T('Attract', size=1.0, mirror=False)),
    'Charm':            rec(W, T('LotsOfLove', size=1.0)),
    'SweetKiss':        rec(W, T('SweetKiss', size=0.9)),
    'EvilKiss':         rec(W, T('EvilKiss', size=1.0)),
    'Flatter':          rec(W, S('ClapFlatter/000', size=0.6, off=[0, -0.3]), T('Flatter', size=1.0, anchor='bottom', off=[0, 0.35])),
    'Swagger':          rec(W, T('Swagger', size=0.6, count=3, stagger=0.1, jitter=0.2)),
    'Clap':             rec(H, S('HandClapPowerUp', size=1.0)),
    'Encore':           rec(H, S('ClapPowerUp', size=1.0), T('ClapFlatter/001', anchor='bottom', size=1.2, off=[0, 0.35])),
    'Metronome':        rec(W, S('Metronome', size=0.7, mirror=False), T('ConfusingHit', size=0.9)),
    'Conversion':       rec(H, S('Conversion', size=0.6)),
    'TriAttack':        rec(H, P('TriAttack/001', spin=540, size=0.45), T('TriAttack/000', size=1.1)),
    'Substitute':       rec(H, S('Substitute', size=0.9)),
    'Teleport':         rec(H, S('Teleport', anchor='bottom', off=[0, 0.45], size=1.4)),
    'TeleportBeam':     rec(H, T('TeleportBeam', anchor='bottom', off=[0, 0.45], size=1.4)),
    'Spotlight':        rec(H, T('SpotLightsRainbow', anchor='bottom', off=[0, 0.45], size=1.4)),
    'FollowMe':         rec(H, S('FollowMe', size=0.5)),
    'CallForFamily':    rec(H, S('CallingBell', size=0.9), S('FollowMe', size=0.4, par=True, delay=0.3, off=[0.3, -0.2])),
    'ChantingBell':     rec(H, S('ChantingBell', size=1.1, mirror=False)),
    'Recover':          rec(H, S('Heal1', size=0.9), S('AquaRing', size=0.9, par=True, delay=0.2, hue=-60)),
    'Softboiled':       rec(H, S('Softboiled', size=1.0)),
    'MilkDrink':        rec(H, S('MilkDrink', size=0.9)),
    'Rest':             rec(H, S('Nightmare', size=0.5, off=[0.3, -0.3], mirror=False, tint='#c0d8ff'), S('Heal1', size=0.9)),
    'Heal':             rec(H, S('Heal1', size=0.9)),
    'HealBench':        rec(H, S('HealingCall', size=1.0, mirror=False), _st('own_bench', 'Heal1', size=0.7)),
    'Agility':          rec(H, S('QuickPowerUp', size=1.0)),
    'SwordsDance':      rec(H, S('SwordsDance', size=0.5, count=2, stagger=0.15, jitter=0.25)),
    'PowerUp':          rec(H, S('PoweringUp', size=1.0)),
    'PowerUpRings':     rec(H, S('PowerUpRings', size=1.0)),
    'PowerUpLights':    rec(H, S('PowerUpLights', size=1.0)),
    'Focus':            rec(H, S('PowerUpSpinningCircles', size=0.9), S('GlowGrowShrink/002', size=0.6, par=True, delay=0.2)),
    'Harden':           rec(H, S('DefenceCurl', size=0.7), S('SelfPolishPowerUp', size=1.0, par=True)),
    'IronDefense':      rec(H, S('SelfPolishPowerUp', size=1.0), S('GlowGrowShrink/000', size=0.8, par=True, tint='#d0e0ff')),
    'Withdraw':         rec(H, S('ShellArmour', size=0.9)),
    'Protect':          rec(H, S('Protect', size=1.1)),
    'Barrier':          rec(H, S('Protect', size=1.1, hue=150)),
    'Block':            rec(W, T('Block', size=0.9)),
    'Endure':           rec(H, S('PowerUpRings', size=1.0, hue=-160)),
    'Minimize':         rec(H, S('GenericSelfPulseIn', size=1.0), S('GenericSelfPulseIn2', size=0.7, par=True, delay=0.15)),
    'Detect':           rec(H, S('MiniIcons/Alert', size=0.5, off=[0.25, -0.35]), S('Glow1', size=0.6)),
    'Foresight':        rec(W, T('Foresight', size=0.6, mirror=False)),
    'LockOn':           rec(W, T('LockOn', size=1.0)),
    'MindReader':       rec(W, T('MindReader/000', size=0.6), T('MindReader/001', size=1.3, par=True, delay=0.25)),
    'MeanLook':         rec(W, T('MeanLook', size=0.8)),
    'Glare':            rec(W, S('MindReader/000', size=0.5, off=[0, -0.2]), T('MeanLook', size=0.8, par=True, delay=0.2)),
    'ScaryFace':        rec(W, T('ScaryFace', size=0.9)),
    'Taunt':            rec(W, S('Taunt/000', size=0.5, off=[0.3, -0.3]), T('Taunt/001', size=0.5, off=[0.25, -0.3])),
    'Torment':          rec(W, T('Torment', size=1.0)),
    'Question':         rec(W, T('MiniIcons/Questioning', size=0.4, off=[0, -0.35], mirror=False)),
    'Exclaim':          rec(H, S('MiniIcons/000', size=0.4, off=[0, -0.35], mirror=False)),
    'Cheer':            rec(H, S('MiniIcons/LoudCheer', size=0.6, off=[0, -0.4], mirror=False), S('MiniIcons/HappyCheer', size=0.5, off=[0, -0.4], mirror=False)),
    'Sweat':            rec(W, S('MiniIcons/Phew', size=0.4, off=[0.25, -0.35], mirror=False)),
    'Anger':            rec(K, S('MiniIcons/Aggravated', size=0.5, off=[0.25, -0.35]), S('MiniRedPowerup', size=0.9, par=True)),
    'Cry':              rec(W, S('Crying', size=0.8, off=[0, -0.2], mirror=False)),
    'Panic':            rec(W, S('Panic', size=0.8, off=[0, -0.25], mirror=False)),
    'Bounce':           rec(L, T('CatKick', size=0.6), T('SimpleAttack', par=True, size=0.8)),
    'Hidden Power':     rec(H, T('FallingLetters', size=1.1, mirror=False), T('PsychicAttack', size=0.8)),
    'BeatUp':           rec(L, T('BeatUp', size=1.0)),
    'GangUp':           rec(L, T('MultiPunch', size=0.8, count=3, stagger=0.12, jitter=0.25)),
    'Pickup':           rec(H, S('Twinkle', size=0.6, off=[0, 0.3])),
    'Search':           rec(H, S('Foresight', size=0.5, mirror=False, off=[0.2, -0.25])),
    'Draw':             rec(H, S('Glow3', size=0.6, off=[0, -0.2])),
    'Present':          rec(H, P('EggBomb/000', arc=90, spin=360, size=0.25, tint='#ffd0e0'), T('SpotLightsRainbow', anchor='bottom', off=[0, 0.45], size=1.2)),
    'Fling':            rec(H, P('RockThrow', arc=80, spin=540, size=0.3), T('SimpleAttack', size=0.9)),
    'Smokescreen':      rec(W, T('Smoke', size=1.2), T('Smoke', size=0.9, par=True, delay=0.15, off=[0.2, 0.15])),
    'SmokeEscape':      rec(H, S('SmokeBombEscape', size=1.0)),
    'Switch':           rec(H, S('SmokePuff', size=0.6), S('GenericPulseOut', size=0.9, par=True)),
    'Copy':             rec(W, T('MirrorShot/000', size=1.0), S('MirrorShot/001', size=0.9)),
    'Counter':          rec(L, S('MirrorShot/002', size=0.4), T('PowerfulHit', size=1.0)),
    'MirrorShot':       rec(H, P('MirrorShot/002', size=0.3), T('MirrorShot/001', size=0.9)),
    'Moonlight':        rec(H, S('Moonlight/001', size=1.0, off=[0, -0.3]), S('Moonlight/000', size=0.8, par=True, delay=0.3)),
    'MoonAttack':       rec(H, S('Moonlight/001', size=0.8, off=[0, -0.4], dur=0.5), P('Moonlight/002', size=0.5), T('Twinkle', size=1.0)),
    'SunnyDay':         rec(H, SC('SunnyDay', size=1.6, off=[0, -0.45])),
    'Glitter':          rec(H, S('Twinkle', size=0.8), S('TwinklingStar', size=0.5, par=True, delay=0.15, off=[0.25, -0.2])),
    'Flash':            rec(H, T('Flash', size=1.2)),
    'LightBall':        rec(H, P('WhiteBallOrb', size=0.35), T('Flash', size=1.0)),
    'EnergyOut':        rec(K, S('HugeEnergyOut', size=1.3)),
    'EnergyRings':      rec(H, S('EnergyRings', size=0.8)),
    'EnergyUp':         rec(H, S('EnergyUpLarge', size=0.9), S('PowerUpAbsorb', size=0.9, par=True)),
    'EnergyUpSmall':    rec(H, S('EnergyUpMid', size=0.8)),
    'Absorb':           rec(W, T('AbsorbingLights', size=1.0), R('LightPowerUpMini', size=0.4), S('Heal1', size=0.7)),
    'GenericBeam':      rec(H, P('ElectroShock', size=0.45, hue=-200), T('GenericPulseOut', size=1.0)),
    'ShieldBreak':      rec(W, T('ShieldBreak/000', size=0.7), T('ShieldBreak/001', size=1.0)),
    'EnergyRemove':     rec(W, T('ShieldBreak/001', size=1.0), R('LightPowerUpMini', size=0.4)),
    'Devolve':          rec(W, T('SpiralSpinIn', size=0.9), T('GenericSelfPulseIn', size=1.1, par=True)),
    'DataStrike':       rec(H, T('FuturisticDataStrike', size=1.1)),
    'Misc':             rec(W, T('GenericPulseOut2', size=1.0)),

    # ---------------- FIGHTING ----------------
    'Punch':            rec(L, T('MiniPunch', size=0.6), T('QuickBurst', size=0.7, par=True, delay=0.05)),
    'MegaPunch':        rec(L, T('MegaPunch', size=1.3)),
    'MegaKick':         rec(L, T('MegaKick', size=1.3)),
    'Kick':             rec(L, T('DoubleKick', size=0.45), T('QuickBurst', size=0.8, par=True, delay=0.05)),
    'DoubleKick':       rec(L, T('DoubleKick', size=0.45, count=2, stagger=0.2, jitter=0.2), T('QuickBurst', size=0.8)),
    'TripleKick':       rec(L, T('DoubleKick', size=0.45, count=3, stagger=0.15, jitter=0.25), T('MegaKick', size=1.0)),
    'CatKick':          rec(L, T('CatKick', size=0.6)),
    'CometPunch':       rec(L, T('MultiPunch', size=1.0)),
    'RapidPunches':     rec(L, T('RapidPunches', size=1.0)),
    'DynamicPunch':     rec(L, T('DynamicPunch', size=1.1)),
    'DizzyPunch':       rec(L, T('DizzyPunch', size=1.0)),
    'DrainPunch':       rec(L, T('DrainPunch', size=1.0), R('LightPowerUpMini', size=0.4)),
    'SteelPunch':       rec(L, T('SteelRockPunch', size=1.2)),
    'FistSlam':         rec(L, T('FistSlam', size=1.0)),
    'GrabCrush':        rec(L, T('GrabCrush', size=1.1)),
    'CrossChop':        rec(L, T('CrossChop', size=0.9), T('PowerfulHit', size=0.9, par=True, delay=0.1)),
    'KarateChop':       rec(L, T('CrossChop', size=0.8)),
    'ForcePalm':        rec(L, T('ForcePalm', size=0.9)),
    'Palm':             rec(L, T('Palm', size=0.5), T('QuickBurst', size=0.8, par=True)),
    'OneSlap':          rec(L, T('OneSlap', size=0.9)),
    'WakeUpSlap':       rec(L, T('WakeUpSlap', size=1.0)),
    'SeismicToss':      rec(L, T('Slam', size=1.2), Q(0.5, par=True), T('SandAttack', size=0.9, par=True, delay=0.2, off=[0, 0.3])),
    'Submission':       rec(L, T('GrabCrush', size=1.1), T('Slam', size=1.0, par=True, delay=0.4)),
    'RockSmash':        rec(L, T('MegaPunch', size=1.0), T('RockSmash', size=1.1, par=True, delay=0.1)),
    'RockThrow':        rec(H, P('RockThrow', arc=80, spin=540, size=0.3), T('RockSmash', size=1.0)),
    'RockSlide':        rec(H, D('RockfallMed', anchor='bottom', size=1.2, time=0.0, off=[0, 0.4]), T('RockSmash', size=1.0)),
    'Avalanche':        rec(K, T('RockFall2', anchor='bottom', size=1.3, off=[0, 0.4]), T('RockSmash', size=1.1), Q(0.5, par=True)),
    'RockTomb':         rec(H, T('RockTomb', size=1.3)),
    'StoneEdge':        rec(H, T('StoneEdge', anchor='bottom', size=1.2, off=[0, 0.45])),
    'AncientPower':     rec(H, S('AncientPower', size=1.0), P('RockThrow', arc=60, spin=360, size=0.3), T('RockSmash', size=1.0)),
    'RockBlast':        rec(H, S('RockBlast/PowerUp', size=0.7), P('RockBlast/Projectile', spin=360, size=0.4), T('RockBlast/Explosion', size=1.2)),
    'Earthquake':       rec(K, Q(1.0), T('SandTomb', size=1.2, par=True), B('SandAttack', size=0.7, par=True)),
    'Magnitude':        rec(K, Q(0.8), T('Bomb', size=1.0, par=True, delay=0.2)),
    'Fissure':          rec(K, Q(1.0), T('SandFall', anchor='bottom', size=1.4, off=[0, 0.45], par=True)),
    'Dig':              rec(H, S('SandAttack', size=0.9, off=[0, 0.3]), T('Bomb', size=1.1, delay=0.15), T('SandAttack', size=0.9, par=True, off=[0, 0.3])),
    'SandAttack':       rec(W, P('SandAttack', size=0.4), T('SandAttack', size=1.1)),
    'Sandstorm':        rec(W, T('SandTomb', size=1.2), T('Gust', size=1.1, par=True, tint='#e0b070')),
    'SandTomb':         rec(W, T('SandTomb', size=1.2)),
    'MudSlap':          rec(W, P('Octazooka/001', size=0.25, tint='#a07040', count=2, stagger=0.1), T('Bomb', size=1.0)),
    'MudSport':         rec(H, T('Bomb', size=0.9, count=3, stagger=0.15, jitter=0.25)),
    'Bonemerang':       rec(H, P('Bonemerang/000', arc=-60, spin=900, size=0.35), T('Bonemerang/001', size=0.8),
                            R('Bonemerang/000', arc=60, spin=900, size=0.35, par=True)),
    'BoneClub':         rec(L, T('Bonemerang/000', size=0.5, spin=720, dur=0.3), T('Bonemerang/001', size=0.9)),
    'BoneRush':         rec(L, T('Bonemerang/000', size=0.45, spin=720, count=3, stagger=0.15, jitter=0.2), T('Bonemerang/001', size=0.9)),

    # ---------------- FIRE ----------------
    'Ember':            rec(H, P('MiniEmber', size=0.2, orient=True), T('Ember', size=0.9)),
    'Flare':            rec(H, T('Ember', size=1.0), T('MiniCombustion', size=0.4, par=True, delay=0.1, count=2, stagger=0.1, jitter=0.2)),
    'Fireball':         rec(H, P('Fireball', size=0.35), T('FireballCombust', size=0.9)),
    'BigFireball':      rec(H, P('Fireball', size=0.55, grow=[0.6, 1.0]), T('Combustion2', size=1.1), T('FireBursts', size=1.0, par=True, delay=0.1)),
    'Flamethrower':     rec(H, P('FireBullet', orient=True, size=0.55, count=5, stagger=0.07), T('FireBursts', size=1.1)),
    'FireBlast':        rec(H, P('FireBlast/000', spin=720, size=0.5), T('FireBlast/001', size=1.3)),
    'FireSpin':         rec(W, T('FireSpin', size=1.1), T('FireSpinningTower', anchor='bottom', size=1.0, off=[0, 0.4], par=True, delay=0.3)),
    'FlamePillar':      rec(H, T('UpwardShootingFire', anchor='bottom', size=1.4, off=[0, 0.45]), T('Ember', size=0.9, par=True)),
    'FlameWheel':       rec(L, T('FlameWheel', size=1.0, spin=360)),
    'FirePunch':        rec(L, T('MegaPunch', size=1.0), T('FireBursts', size=1.0, par=True, delay=0.05)),
    'BlazeKick':        rec(L, T('BlazeKick', size=1.0)),
    'FireFang':         rec(L, T('FireFang', size=1.0)),
    'FireClaw':         rec(L, T('FireSwipes', orient=True, size=1.0), T('FireSweep', par=True, size=0.7, delay=0.1)),
    'FireTail':         rec(L, T('FireSweep', size=0.9), T('Ember', size=0.8, par=True, delay=0.1)),
    'Inferno':          rec(K, T('Inferno', size=1.2)),
    'Eruption':         rec(K, T('Eruption', size=1.4), Q(0.6, par=True)),
    'HotRocks':         rec(H, P('HotRocks/000', arc=90, size=0.45), T('HotRocks/001', size=1.1)),
    'Magma':            rec(K, P('HotRocks/000', arc=90, size=0.45), T('HotRocks/001', size=1.1), T('FireBursts', size=1.0, par=True)),
    'FireWall':         rec(H, T('FireSpinningTower', anchor='bottom', size=1.2, off=[0, 0.45]), T('UpwardShootingFire', anchor='bottom', size=1.2, off=[0.25, 0.45], par=True, delay=0.1)),
    'FireBurst':        rec(H, T('FireBurst', size=1.2)),
    'Combustion':       rec(K, T('Combustion2', size=1.2), T('MiniExplosions', size=0.8, par=True, delay=0.15)),
    'Sunburn':          rec(H, SC('SunnyDay', size=1.4, off=[0, -0.45]), T('FireBursts', size=1.0)),
    'WillOWisp':        rec(W, P('DarkFlame/DarkFlame2', size=0.35), T('Willowisp', size=0.9)),
    'BlueFlame':        rec(H, P('BlueFireBall', orient=True, size=0.5), T('DarkFlame/DarkFlame', size=1.0, hue=-70)),
    'DarkFlame':        rec(H, P('DarkFlame/DarkFlame2', size=0.35), T('DarkFlame/DarkFlame', size=1.1)),
    'SacredFire':       rec(H, P('FireBlast/000', spin=720, size=0.5, hue=30), T('UpwardShootingFire', anchor='bottom', size=1.4, off=[0, 0.45]),
                            T('FireBlast/001', size=1.2, par=True, delay=0.15)),
    'FlameStar':        rec(H, P('FlameStar', spin=720, size=0.4), T('Combustion2', size=1.0)),
    'HeatWave':         rec(W, T('FireSpin', size=1.2), T('Smoke', size=0.8, par=True, tint='#ffb080')),

    # ---------------- WATER ----------------
    'Bubble':           rec(H, P('BubblePop', range=[0, 0], size=0.3, count=3, stagger=0.1), T('BubblePop', size=0.9)),
    'Bubblebeam':       rec(H, P('BubblePop', range=[0, 0], size=0.3, count=6, stagger=0.06), T('BubblePop', size=1.0), T('WaterSplash', size=0.9, par=True)),
    'WaterGun':         rec(H, P('WaterPulse1', orient=True, size=0.4, count=3, stagger=0.08), T('SplashAttack/001', size=0.9)),
    'WaterPulse':       rec(H, P('WaterPulse', orient=True, size=0.5), T('SplashAttack/002', size=1.0), T('SplashAttack/001', size=0.9, par=True)),
    'HydroPump':        rec(H, P('WaterPulse', orient=True, size=0.6, count=5, stagger=0.07), T('SplashAttack/000', size=1.2),
                            T('WaterSportSplash', size=1.3, par=True, delay=0.1)),
    'Splash':           rec(H, S('SplashAttack/001', size=0.8, off=[0, 0.25]), S('WaterSplash', size=0.8, par=True)),
    'SplashHit':        rec(L, T('SplashAttack/001', size=1.0)),
    'WaterSlash':       rec(L, T('QuickSwipe', orient=True, size=1.0, tint='#80c0ff'), T('SplashAttack/001', size=0.8, par=True, delay=0.1)),
    'Waterfall':        rec(L, T('DownPour', anchor='bottom', size=1.2, off=[0, 0.4], dur=0.6), T('SplashAttack/000', size=1.1)),
    'Surf':             rec(W, SC('WaterSportSplash', size=1.8), T('SplashAttack/000', size=1.3, par=True, delay=0.2), B('SplashAttack/001', size=0.7, par=True, delay=0.3)),
    'TidalWave':        rec(K, SC('WaterSportSplash', size=2.2), T('SplashAttack/000', size=1.4, par=True, delay=0.15),
                            T('DownPour', anchor='bottom', size=1.3, off=[0, 0.4], par=True, delay=0.1), Q(0.6, par=True)),
    'Rain':             rec(H, T('DownPour', anchor='bottom', size=1.3, off=[0, 0.4])),
    'Whirlpool':        rec(W, T('Gust', size=1.1, hue=170, tint='#80c0ff'), T('AquaRing', size=1.0, par=True)),
    'AquaRing':         rec(H, S('AquaRing', size=1.0)),
    'Octazooka':        rec(H, P('Octazooka/001', size=0.3), T('Octazooka/000', size=1.0)),
    'Clamp':            rec(L, T('Clamp', size=1.0)),
    'Crabhammer':       rec(L, T('ViceGrip', size=1.0), T('SplashAttack/001', size=0.8, par=True, delay=0.15)),
    'ViceGrip':         rec(L, T('ViceGrip', size=1.0)),
    'Guillotine':       rec(L, T('Guillotine', size=1.2)),
    'Steam':            rec(W, T('BlueSmoke', size=1.1, tint='#e0f0ff'), T('Smoke', size=0.9, par=True, delay=0.15)),

    # ---------------- ICE (mostly built from other effects -- there is no proper ice beam) ----------------
    'IceBeam':          rec(H, P('IcyWind/000', size=0.35, count=4, stagger=0.06), T('IceCrash/000', size=1.0), T('IceAttack/000', size=1.2, par=True)),
    'AuroraBeam':       rec(H, P('PsyWave', orient=True, size=0.5, count=3, stagger=0.08, hue=-110), T('RockTombBlueIce', size=1.1)),
    'IcyWind':          rec(W, P('IcyWind/000', size=0.35, count=3, stagger=0.1), T('IcyWind/001', size=1.1, anchor='bottom', off=[0, 0.35])),
    'PowderSnow':       rec(W, T('IceAttack/001', size=0.9, count=2, stagger=0.2, jitter=0.2)),
    'Blizzard':         rec(K, SC('Gust', size=1.8, tint='#d0f0ff'), T('IceAttack/001', size=1.0, par=True, count=3, stagger=0.15, jitter=0.3),
                            T('IceAttack/000', size=1.3, par=True, delay=0.3), B('IceAttack/001', size=0.7, par=True, delay=0.3)),
    'Freeze':           rec(W, T('RockTombBlueIce', size=1.2)),
    'IceShard':         rec(H, P('IceCrash/001', orient=True, size=0.35), T('IceCrash/000', size=1.0)),
    'Icicle':           rec(H, T('IcicleAttack', size=1.0), T('IceCrash/000', size=0.9, delay=0.0)),
    'Hail':             rec(H, D('IceCrash/001', size=0.3, count=4, stagger=0.1, jitter=0.3, time=0.3), T('IceCrash/000', size=1.0)),
    'IcePunch':         rec(L, T('MegaPunch', size=1.0), T('IceCrash/000', size=1.0, par=True, delay=0.05)),
    'IceFang':          rec(L, T('IceFang', size=1.0)),
    'IceWing':          rec(L, T('Feathers', size=1.0, hue=ICE_HUE, tint='#c0f0ff'), T('IceAttack/001', size=0.8, par=True, delay=0.1)),
    'SheerCold':        rec(K, T('RockTombBlueIce', size=1.3), T('IceAttack/000', size=1.4, par=True, delay=0.3)),

    # ---------------- LIGHTNING ----------------
    'Spark':            rec(H, T('Spark', size=0.9)),
    'ThunderShock':     rec(H, T('ThunderShock', anchor='bottom', size=1.1, off=[0, 0.25]), T('Spark', size=0.8)),
    'Thunderbolt':      rec(H, T('ThunderBolt', anchor='bottom', size=1.4, off=[0, 0.3]), T('Discharge', size=1.0, par=True, delay=0.3)),
    'Thunder':          rec(K, T('Thunder', anchor='bottom', size=1.6, off=[0, 0.3], loops=2), T('Discharge', size=1.3), Q(0.4, par=True)),
    'ThunderWave':      rec(W, T('Electrocute', size=1.0, loops=2)),
    'ThunderPunch':     rec(L, T('MegaPunch', size=1.0), T('Spark', size=1.0, par=True, delay=0.05)),
    'ThunderFang':      rec(L, T('ThunderFang', size=1.0)),
    'ElectricTackle':   rec(L, T('ElectroShock', size=0.8), T('Spark', size=1.0, par=True)),
    'ElectroBall':      rec(H, P('ElectroBall', size=0.4, spin=360), T('Discharge', size=1.0)),
    'LightningBall':    rec(H, P('ElectroShock', size=0.45), T('Spark', size=1.0)),
    'ZapCannon':        rec(K, S('ZapCannon/Ball', size=0.3, off=[0.35, 0]), P('ZapCannon/Projectile', orient=True, size=0.6), T('ZapCannon/Impact', size=1.2)),
    'Discharge':        rec(K, S('Discharge', size=1.4), T('Spark', size=1.0, delay=0.0)),
    'Charge':           rec(H, S('Charge', size=1.0)),
    'ReverseCharge':    rec(H, S('ReverseCharge', size=1.0)),
    'Gigashock':        rec(K, T('Thunder', anchor='bottom', size=1.5, off=[0, 0.3]), T('Discharge', size=1.2), B('Spark', size=0.8, par=True)),
    'ChainLightning':   rec(K, T('ThunderBolt', anchor='bottom', size=1.3, off=[0, 0.3]), B('ThunderShock', anchor='bottom', size=0.9, off=[0, 0.3], par=True, delay=0.2)),
    'Magnet':           rec(H, P('SteelOrb/Projectile', size=0.3, count=2, stagger=0.1), T('ElectroShock', size=0.9)),
    'MagnetBomb':       rec(H, P('SteelOrb/Projectile', size=0.35, arc=50), T('SmallBomb', size=1.0), T('Spark', size=0.8, par=True)),

    # ---------------- GRASS ----------------
    'VineWhip':         rec(W, T('VineWhip/000', size=0.9, loops=2), T('VineWhip/001', size=0.6)),
    'VineWrap':         rec(W, T('VineWrap', size=1.1, dur=0.6)),
    'RazorLeaf':        rec(H, S('RazorLeafPowerUp', size=1.0, dur=0.5), T('LeafNeedles1', size=1.0)),
    'LeafStorm':        rec(H, S('RazorLeafPowerUp', size=1.0, dur=0.5), T('LeafNeedles2', size=1.1), T('PetalBlizzard', size=0.9, par=True, hue=-90)),
    'MagicalLeaf':      rec(H, S('MagicalLeaf/PowerUp', size=1.0), P('MagicalLeaf/Projectile', size=0.5, spin=540), T('SmallSlash', size=0.8)),
    'LeafBlade':        rec(L, T('LeafBlade', size=1.0)),
    'PetalDance':       rec(W, S('PetalBomb', size=0.8), T('PetalBlizzard', size=1.1)),
    'PetalBlizzard':    rec(W, SC('PetalBlizzard', size=1.4), B('PetalBomb', size=0.6, par=True, delay=0.3)),
    'SleepPowder':      rec(W, T('SleepPowder', size=0.9, off=[0, -0.1])),
    'StunSpore':        rec(W, T('StunPowder', size=0.9, off=[0, -0.1])),
    'PoisonPowder':     rec(W, T('PoisonPowder', size=0.9, off=[0, -0.1])),
    'CottonSpore':      rec(W, T('CottonSpore', size=1.0)),
    'LeechSeed':        rec(H, P('LeechSeed/000', arc=60, size=0.15, count=3, stagger=0.08), T('LeechSeed/001', size=0.9, anchor='bottom', off=[0, 0.3]),
                            R('LightPowerUpMini', size=0.4, tint='#a0ff80')),
    'Growth':           rec(H, S('LeafPowerUp', size=1.0), S('NaturePowerUp1', size=0.8, par=True, delay=0.2)),
    'Ingrain':          rec(H, S('Ingrain2', size=1.1, anchor='bottom', off=[0, 0.45])),
    'Roots':            rec(W, T('Ingrain1', size=1.1, anchor='bottom', off=[0, 0.45])),
    'Photosynthesis':   rec(H, S('Photosynthesis', size=0.7), S('NatureRecovery', size=1.0, par=True, delay=0.15)),
    'Solarbeam':        rec(K, S('Photosynthesis', size=0.7, loops=2), T('SpotLightsRainbow', anchor='bottom', size=1.4, off=[0, 0.45]),
                            T('GreenEnergyHit', size=1.1, par=True, delay=0.25)),
    'EnergyBall':       rec(H, P('EnergyBall/000', size=0.5), T('EnergyBall/002', size=1.0), T('EnergyBall/001', size=0.8, par=True)),
    'BulletSeed':       rec(H, P('BulletSeed', orient=True, size=0.3, count=5, stagger=0.07), T('VineWhip/001', size=0.6, count=2, stagger=0.1, jitter=0.2)),
    'NaturalPower':     rec(H, S('NaturalPower', size=1.0)),
    'NatureRecovery':   rec(H, S('NatureRecovery', size=1.0)),
    'Seeds':            rec(H, D('ChestnutsFalling', anchor='bottom', size=1.2, time=0.0, off=[0, 0.4])),
    'GrassKnot':        rec(W, T('Ingrain1', size=1.0, anchor='bottom', off=[0, 0.45]), T('GreenEnergyHit', size=0.9)),
    'GreenHit':         rec(H, P('EnergyBall/001', size=0.35, spin=360), T('GreenEnergyHit', size=1.0)),
    'MegaDrain':        rec(W, T('GreenEnergyHit', size=0.9), R('AbsorbingLights', size=0.6), S('NatureRecovery', size=0.9)),
    'Spore':            rec(W, T('CottonSpore', size=1.0, tint='#ffe0a0'), T('SleepPowder', size=0.8, par=True, delay=0.2)),

    # ---------------- BUG ----------------
    'StringShot':       rec(W, P('StringShotSpiderSilk', range=[0, 1], size=0.3), T('StringShotSpiderSilk', size=1.0, mirror=False)),
    'BugSwarm':         rec(W, T('BeeSwarmBugAttack', size=1.1)),
    'BugBuzz':          rec(W, T('BeeSwarmWithEffect', size=1.1)),
    'PinMissile':       rec(H, P('PinMissile', orient=True, size=0.4, count=3, stagger=0.1), T('SmallSlash', size=0.7, count=2, stagger=0.1, jitter=0.2)),
    'Sting':            rec(H, P('Sting', orient=True, size=0.3), T('SmallSlash', size=0.6)),
    'Twineedle':        rec(H, P('DoubleSting', orient=True, size=0.35), T('SmallSlash', size=0.6, count=2, stagger=0.1, jitter=0.15)),
    'TripleNeedle':     rec(H, P('TripleSting', orient=True, size=0.4), T('SmallSlash', size=0.6, count=3, stagger=0.08, jitter=0.2)),
    'PoisonSting':      rec(H, P('Sting', orient=True, size=0.3), T('QuickPoisonHit', size=0.9)),
    'SignalBeam':       rec(H, P('SignalBeam', size=0.35, count=3, stagger=0.08), T('PsionicAttack', size=1.0, hue=-160)),
    'SilverWind':       rec(W, SC('Gust', size=1.4, tint='#e0e0ff'), T('TwinklingStar', size=0.6, par=True, delay=0.2, count=3, stagger=0.1, jitter=0.25)),
    'LeechLife':        rec(L, T('Bite', size=0.5), R('LightPowerUpMini', size=0.4, tint='#ff8080')),
    'Web':              rec(W, T('StringShotSpiderSilk', size=1.1, mirror=False)),

    # ---------------- POISON ----------------
    'Acid':             rec(W, P('Octazooka/001', size=0.25, hue=50, tint='#c0ff80', count=2, stagger=0.1), T('QuickPoisonHit', size=1.0)),
    'Sludge':           rec(W, P('Octazooka/001', size=0.35, tint='#c080ff', arc=50), T('SmokeBombAttack/001', size=1.0), T('QuickPoisonHit', size=0.9, par=True)),
    'PoisonGas':        rec(W, T('SmokeBombAttack/001', size=1.1)),
    'Smog':             rec(W, P('SmokeBombAttack/000', size=0.35, arc=50), T('SmokeBombAttack/001', size=1.1)),
    'Toxic':            rec(W, T('ToxicSpike', size=0.9, count=2, stagger=0.12, jitter=0.2), T('CrossPoison', size=0.9)),
    'PoisonFang':       rec(L, T('Crunch', size=0.8), T('QuickPoisonHit', size=0.9, par=True, delay=0.1)),
    'PoisonClaw':       rec(L, T('PoisonSlash', size=1.0)),
    'CrossPoison':      rec(L, T('CrossPoison', size=1.0)),
    'PoisonHorn':       rec(L, T('ViceGrip', size=0.9), T('QuickPoisonHit', size=0.9, par=True, delay=0.1)),
    'PoisonTentacle':   rec(W, T('VineWrap', hue=PURPLE, size=1.0, dur=0.6), T('QuickPoisonHit', size=0.9)),
    'PoisonSpray':      rec(W, P('PsychicBall', size=0.3, hue=60, count=3, stagger=0.1), T('QuickPoisonHit', size=1.0)),

    # ---------------- PSYCHIC ----------------
    'Confusion':        rec(W, T('MiniPyschic', size=1.0)),
    'Psychic':          rec(W, T('PsychicAttack', size=1.1)),
    'Psybeam':          rec(W, P('PsyWave', orient=True, size=0.55, count=3, stagger=0.08), T('PsionicAttack', size=1.0)),
    'Psywave':          rec(W, P('PsyWave', orient=True, size=0.5, count=4, stagger=0.12), T('MiniPyschic', size=0.9)),
    'Psyshock':         rec(W, T('PsychicRazor', size=1.1)),
    'PsychicBlast':     rec(K, S('PsychicPowerUp', size=0.9, dur=0.5), T('MassivePsychichBlast', size=1.3)),
    'PsychicBall':      rec(H, P('PsychicBall', size=0.4), T('PsychicAttack', size=1.0)),
    'MindShock':        rec(W, T('MindShatter', size=1.1)),
    'PsychicLights':    rec(W, T('PsychicLights', size=1.0)),
    'Hypnosis':         rec(W, T('SpiralSpinIn', size=0.9), T('PsychicLights', size=0.9, par=True, delay=0.15)),
    'Amnesia':          rec(H, S('Amnesia', size=1.0)),
    'Meditate':         rec(H, S('PsychicPowerUp', size=1.0)),
    'Psypunch':         rec(L, T('PsychicPalm', size=1.0)),
    'PsyPalm':          rec(L, T('OneSlap', size=1.0)),
    'SpoonBend':        rec(W, S('SpoonBend', size=0.4, off=[0.3, -0.2]), T('MiniPyschic', size=0.9)),
    'Telekinesis':      rec(W, T('PsychicPalm', size=1.0), T('PsychicLights', size=0.9, par=True)),
    'DestinyBond':      rec(W, T('DestinyBond', size=1.0), S('DestinyBond', size=1.0, par=True)),
    'PainSplit':        rec(W, T('DestinyBond', size=1.0), S('DestinyBond', size=1.0, par=True, hue=-60)),
    'Nightmare':        rec(W, T('Nightmare', size=0.6), T('DarknessEngulf', size=1.0, par=True, delay=0.15)),
    'DreamEater':       rec(W, T('Nightmare', size=0.6), T('DarknessEngulf', size=1.0), R('LightPowerUpMini', size=0.4, tint='#ff80ff')),
    'Curse':            rec(W, S('CurseGhost', size=0.6, off=[0, -0.3]), P('CursePin', orient=True, size=0.4), T('Spite', size=0.9)),
    'CurseCounters':    rec(W, T('CursePin', orient=True, size=0.4, count=3, stagger=0.12, jitter=0.25), T('Spite', size=0.9)),
    'Spite':            rec(W, T('Spite', size=1.0)),
    'ConfuseRay':       rec(W, P('PsychicBall', size=0.35, hue=-60), T('ConfusingHit', size=1.0)),
    'Lunar':            rec(H, S('Moonlight/001', size=0.9, off=[0, -0.4], dur=0.6), T('MassivePsychichBlast', size=1.1, hue=40)),
    'Future':           rec(W, S('MindReader/000', size=0.6, off=[0, -0.3]), T('PsychicLights', size=1.0)),
    'Barrier':          rec(H, S('Protect', size=1.1, hue=150)),
    'PsychicDamage':    rec(W, T('PsionicAttack', size=1.0)),

    # ---------------- GHOST / DARK ----------------
    'ShadowBall':       rec(W, P('ShadowBall', size=0.4, spin=360), T('DarknessEngulf', size=1.1)),
    'NightShade':       rec(W, T('EvilForce', size=0.9), T('DarkSwirl', size=1.0, par=True, delay=0.3)),
    'Haunt':            rec(W, P('CurseGhost', size=0.4), T('EvilForce', size=0.9)),
    'ShadowPunch':      rec(L, T('ShadowPunch', size=0.6, count=2, stagger=0.15, jitter=0.2), T('DarkSwirl', size=0.9)),
    'ShadowClaw':       rec(L, T('ShadowClaw', size=1.0)),
    'ShadowSneak':      rec(L, P('ShadowSneak/Move', size=0.9, time=0.3), T('ShadowSneak/Effect', size=1.0)),
    'FeintAttack':      rec(L, T('HiddenDarkShadowStrike', size=1.2)),
    'DarkSlash':        rec(L, T('DarkSlash', size=1.1)),
    'Bite':             rec(L, T('Bite', size=0.7)),
    'Crunch':           rec(L, T('Crunch', size=0.8)),
    'HyperFang':        rec(L, T('SuperFang', size=1.2)),
    'DarkWave':         rec(W, P('DarkWave', orient=True, size=0.5, count=3, stagger=0.1), T('DarkSwirl', size=1.0)),
    'DarkPulse':        rec(W, S('DarkPowerUp', size=1.2, dur=0.6), P('DarkWave', orient=True, size=0.6, count=2, stagger=0.1), T('DarkCombustion', size=1.1)),
    'DarkMind':         rec(W, T('EvilDarkPsychicPower', size=1.0)),
    'DarkCloud':        rec(W, T('DarkCloudAttack', size=1.1)),
    'DarknessEngulf':   rec(W, T('DarknessEngulf', size=1.1)),
    'DarkBlast':        rec(K, S('DarkPowerUp', size=1.2, dur=0.6), P('ShadowBall', size=0.5), T('DarkCombustion', size=1.2)),
    'EvilForce':        rec(W, T('EvilForce', size=1.0)),
    'DarkPowerUp':      rec(H, S('DarkPowerUp', size=1.2)),
    'Pursuit':          rec(L, P('ShadowSneak/Move', size=0.9, time=0.25), T('HiddenDarkShadowStrike', size=1.1)),

    # ---------------- METAL / DRAGON ----------------
    'MetalClaw':        rec(L, T('ShadowClaw', size=1.0, tint='#e0e0f0', hue=-30), T('SmallSlash', size=0.8, par=True, delay=0.1)),
    'IronTail':         rec(L, T('PowerfulHit', size=1.0, tint='#c8d0e8'), T('SmallSlash', size=0.9, par=True, delay=0.05)),
    'SteelWing':        rec(L, T('Feathers', size=1.0, tint='#c0c8d8'), T('SmallSlash', size=0.8, par=True, delay=0.1)),
    'MetalSound':       rec(K, T('MetalSound', size=1.1)),
    'SteelOrb':         rec(H, S('SteelOrb/PowerUp', size=0.8), P('SteelOrb/Projectile', size=0.35), T('SteelRockPunch', size=1.0)),
    'MetalBall':        rec(H, P('SteelOrb/Projectile', size=0.35, arc=60), T('PowerfulHit', size=1.0, tint='#d0d8ff')),
    'DragonRage':       rec(K, S('RoarOfTime/000', size=1.1, dur=0.6), P('RoarOfTime/001', size=0.4, spin=360), T('DarkCombustion', size=1.2, hue=170)),
    'Dragonbreath':     rec(H, P('BlueFireBall', orient=True, size=0.5, count=2, stagger=0.1, hue=-60), T('Combustion2', size=1.1, hue=-140)),
    'DragonClaw':       rec(L, T('MultipleClawAttack/000', size=1.0, count=2, stagger=0.15, jitter=0.15, hue=140), T('MultipleClawAttack/008', size=1.1)),
    'RoarOfTime':       rec(K, S('RoarOfTime/000', size=1.3), P('RoarOfTime/001', size=0.4), T('Explosion', size=1.4), Q(0.6, par=True)),
    'Outrage':          rec(L, T('Slam', count=3, stagger=0.15, jitter=0.25, size=1.0, hue=170), T('DarkCombustion', size=1.1, hue=170)),
    'DragonDance':      rec(H, S('PowerUpRings', size=1.0, hue=140), S('MiniRedPowerup', size=0.9, par=True)),
    'Meteor':           rec(K, SC('MeteorStrike', size=2.4, off=[0.0, -0.1]), T('Explosion', size=1.2, delay=0.0), Q(0.5, par=True)),
    'AuraSphere':       rec(H, P('AuraSphere', size=0.5), T('GenericPulseOut3', size=1.1)),
    'FingerStorm':      rec(W, T('FingerStorm', size=0.9), T('Spark', size=0.7, par=True, delay=0.3)),
    'NastyPlot':        rec(H, S('NastyPlot', size=0.9, off=[0, -0.25])),
    'RainbowWing':      rec(W, P('RainbowWing', orient=True, size=0.35, count=3, stagger=0.1), T('TwinklingStar', size=0.8)),
    'EnergyAbsorbLong': rec(H, S('PowerUpAbsorbLong', size=1.1)),
    'PowerUpNoRing':    rec(H, S('PoweringUpNoRing', size=1.0), S('Glow2', size=0.5, par=True, delay=0.4)),
    'Pebbles':          rec(H, D('RockfallSmall', anchor='bottom', size=1.1, off=[0, 0.4]), T('RockSmash', size=0.8)),
    'NatureBoost':      rec(H, S('NaturePowerUp2', size=0.9), S('Glow4', size=0.5, par=True, delay=0.2)),
    'SmokeBurst':       rec(H, T('SmokeBurst', size=1.1)),
    'FireCharge':       rec(H, S('MiniRedPowerup', size=0.9), S('FireSpinningTower', anchor='bottom', size=0.8, off=[0, 0.45], par=True, delay=0.2)),
    'TailSmash':        rec(L, T('Slam', size=1.1), T('PowerfulHit', size=0.9, par=True, delay=0.08)),
    'Shockwave':        rec(K, S('GenericPulseOut', size=1.4), T('GenericPulseOut2', size=1.2, delay=0.0), T('QuickBurst', size=0.9, par=True)),
}

# ---------------- PER-TYPE VARIANTS: a generic recipe swapped for the attacker's own type ----------------
VARIANTS = {
    'Charge':     {'Fire': 'FireCharge', 'Grass': 'NatureBoost', 'Water': 'EnergyUp', 'Psychic': 'Meditate', 'Darkness': 'DarkPowerUp',
                   'Fighting': 'PowerUp', 'Colorless': 'EnergyUp', 'Metal': 'EnergyUp'},
    'EnergyUp':   {'Lightning': 'Charge', 'Fire': 'FireCharge', 'Darkness': 'DarkPowerUp', 'Grass': 'NatureBoost', 'Psychic': 'Meditate'},
    'EnergyBall': {'Water': 'WaterPulse', 'Colorless': 'AuraSphere', 'Psychic': 'PsychicBall', 'Lightning': 'ElectroBall'},
    'PowerUp':    {'Lightning': 'Charge', 'Fire': 'FireCharge', 'Darkness': 'DarkPowerUp', 'Grass': 'NatureBoost', 'Psychic': 'Meditate'},
}

# ========================================================================================
# PASS 2 (2026-10-26): recipes rebuilt around the effects copied out of the numbered folders, plus
# the card movements, reactions, element colours and screen effects Attack_VFX.gd now does.
# ========================================================================================
def BM(fx, **kw): return _st('beam', fx, **kw)
DASH, LEAP, SPIN, VSTRIKE, DIVE = 'dash', 'leap', 'spin', 'vanish_strike', 'dive'
CHARGE, GROW, SHRINK, RISE, VANISH = 'charge', 'grow', 'shrink', 'rise', 'vanish'
STAT_DOWN = dict(size=0.4, off=[0.0, -0.05], mirror=False, count=2, stagger=0.15, jitter=0.18, loops=2)
STAT_UP = dict(size=0.4, off=[0.0, -0.05], mirror=False, count=2, stagger=0.15, jitter=0.18, loops=2)

RECIPES.update({
    # ---- normal ----
    'QuickAttack':   rec(DASH, P('SpeedLines', orient=True, size=1.0, time=0.15), T('QuickSwipe', orient=True), T('SmallSlash', par=True, delay=0.05)),
    'Tackle':        rec(L, T('SimpleAttack'), T('DustBurst', size=0.7, par=True, off=[0, 0.3])),
    'TakeDown':      rec(DASH, T('GigaImpact/000', size=1.0), T('GigaImpact/016', par=True, size=1.1), T('DustBurst', size=0.8, par=True, off=[0, 0.3])),
    'GigaImpact':    rec(DASH, P('GigaImpact/010', orient=True, time=0.15), T('GigaImpact/016', size=1.4),
                         T('GigaImpact/000', par=True, size=1.3), T('HatchFlash', size=1.0, par=True), Q(0.4, par=True)),
    'BodySlam':      rec(LEAP, T('Slam', size=1.3), T('DustBurst', size=1.0, par=True, off=[0, 0.3]), Q(0.35, par=True)),
    'Stomp':         rec(LEAP, T('Paw', size=0.6, tint='#c8b8a0'), T('DustBurst', size=0.9, par=True, off=[0, 0.3])),
    'Trample':       rec(LEAP, T('Paw', size=0.55, tint='#c8b8a0', count=3, stagger=0.13, jitter=0.25), T('DustBurst', size=1.0, par=True, off=[0, 0.3]), Q(0.5, par=True)),
    'Bounce':        rec(LEAP, T('CatKick', size=0.6), T('SimpleAttack', par=True, size=0.8)),
    'Swift':         rec(H, P('Star', spin=720, size=0.25, count=5, stagger=0.07, jitter=0.15), T('YellowStars', size=0.9), T('StarShine', size=1.0, par=True)),
    'StarStrike':    rec(H, P('StarTrail', orient=True, size=0.6, time=0.3), T('StarShine', size=1.0), T('Twinkle', size=0.8, par=True)),
    'ShootingStar':  rec(H, D('StarStrikeRed', size=0.8, time=0.3, count=3, stagger=0.12, jitter=0.2), T('YellowStars', size=1.0), T('StarShine', size=1.0, par=True)),
    'PayDay':        rec(L, T('SimpleAttack'), T('GoldScatter', size=1.0, par=True), T('GoldCluster', size=0.8, par=True, delay=0.1)),
    'Present':       rec(H, P('Sack', arc=90, spin=360, size=0.25), T('HatchFlash', size=1.0), T('Confetti', size=1.2, par=True)),
    'Cheer':         rec(H, S('Confetti', size=1.2), S('MiniIcons/LoudCheer', size=0.6, off=[0, -0.4], mirror=False, par=True)),
    'Glitter':       rec(H, S('FairySparkles', size=1.0), S('Twinkle', size=0.7, par=True, delay=0.1)),
    'Wish':          rec(H, S('Wish', size=1.2, off=[0, -0.35]), S('FairySparkles', size=1.0, par=True, delay=0.2)),
    'Explosion':     rec(CHARGE, S('WhiteGrow', size=1.0), S('Explosion', size=2.4), T('Explosion', size=2.2, par=True, delay=0.12), Q(0.8, par=True)),
    'Selfdestruct':  rec(CHARGE, S('WhiteGather', size=1.0), S('Selfdestruct', size=2.0), T('SmallBomb', size=1.3, par=True, delay=0.12), Q(0.5, par=True)),
    'HyperBeam':     rec(CHARGE, S('PowerUpAbsorb', size=1.0, dur=0.6), BM('LightBeam', size=0.55, tint='#ffb070', dur=0.75),
                         T('Explosion', size=1.6, delay=0.15, par=True), Q(0.5, par=True)),
    'GenericBeam':   rec(H, BM('WhiteLineBeam', size=0.35, dur=0.5), T('GenericPulseOut', size=1.0, par=True, delay=0.15)),
    'Growl':         rec(K, S('Growl', size=1.2, off=[0.45, 0]), T('StatDown', delay=0.25, **STAT_DOWN)),
    'Leer':          rec(W, T('MeanLook', size=0.8), T('StatDown', delay=0.2, **STAT_DOWN)),
    'TailWhip':      rec(W, T('Swagger', size=0.6, count=2, stagger=0.2, jitter=0.2), T('StatDown', delay=0.15, **STAT_DOWN)),
    'ScaryFace':     rec(W, T('ScaryFace', size=0.9), T('StatDown', delay=0.3, **STAT_DOWN)),
    'Charm':         rec(W, T('LotsOfLove', size=1.0), T('PinkSparkles', size=0.9, par=True), T('StatDown', delay=0.2, **STAT_DOWN)),
    'Screech':       rec(K, S('SoundRings', size=1.0, off=[0.3, 0]), T('MetalSound', size=1.1, hue=-30), T('StatDown', delay=0.15, **STAT_DOWN)),
    'Roar':          rec(K, S('Uproar', size=1.4), T('SoundRings', size=1.2, par=True, delay=0.15), T('Growl', size=1.0, par=True, delay=0.25)),
    'HyperVoice':    rec(K, S('HyperVoice', size=1.2), P('HarshSound', orient=True, size=0.8, count=2, stagger=0.15), T('SoundRings', size=1.3), T('Uproar', size=1.0, par=True)),
    'SwordsDance':   rec(GROW, S('SwordsDance', size=0.5, count=2, stagger=0.15, jitter=0.25), S('StatUp', **STAT_UP)),
    'Agility':       rec(H, S('SpeedLines', size=1.2, loops=2), S('QuickPowerUp', size=1.0, par=True), S('StatUp', **STAT_UP)),
    'Harden':        rec(GROW, S('DefenceCurl', size=0.7), S('SelfPolishPowerUp', size=1.0, par=True), S('StatUp', **STAT_UP)),
    'IronDefense':   rec(GROW, S('SelfPolishPowerUp', size=1.0), S('GlowGrowShrink/000', size=0.8, par=True, tint='#d0e0ff'), S('StatUp', **STAT_UP)),
    'Withdraw':      rec(SHRINK, S('ShellArmour', size=0.9), S('StatUp', **STAT_UP)),
    'Minimize':      rec(SHRINK, S('GenericSelfPulseIn', size=1.0), S('GenericSelfPulseIn2', size=0.7, par=True, delay=0.15), S('StatUp', **STAT_UP)),
    'Focus':         rec(CHARGE, S('PowerUpSpinningCircles', size=0.9), S('GlowGrowShrink/002', size=0.6, par=True, delay=0.2), S('StatUp', **STAT_UP)),
    'PowerUp':       rec(GROW, S('PoweringUp', size=1.0), S('StatUp', **STAT_UP)),
    'PowerUpRings':  rec(GROW, S('PowerUpRings', size=1.0), S('StatUp', **STAT_UP)),
    'PowerUpLights': rec(GROW, S('PowerUpLights', size=1.0), S('StatUp', **STAT_UP)),
    'PowerUpNoRing': rec(GROW, S('PoweringUpNoRing', size=1.0), S('Glow2', size=0.5, par=True, delay=0.4), S('StatUp', **STAT_UP)),
    'Recover':       rec(RISE, S('GoldenRingRise', size=1.0, anchor='bottom', off=[0, 0.45]), S('Heal1', size=0.9, par=True, delay=0.2)),
    'Heal':          rec(RISE, S('Heal1', size=0.9), S('GoldenRingRise', size=0.9, anchor='bottom', off=[0, 0.45], par=True)),
    'Softboiled':    rec(H, S('Egg', size=0.3, off=[0, -0.3]), S('Softboiled', size=1.0)),
    'Rest':          rec(H, S('Nightmare', size=0.5, off=[0.3, -0.3], mirror=False, tint='#c0d8ff'), S('Heal1', size=0.9), S('BubblesRising', size=0.8, par=True)),
    'Teleport':      rec(VANISH, S('Teleport', anchor='bottom', off=[0, 0.45], size=1.4)),
    'SmokeEscape':   rec(VANISH, S('SmokeBombEscape', size=1.0)),
    'Switch':        rec(VANISH, S('SmokePuff', size=0.6), S('GenericPulseOut', size=0.9, par=True)),
    'Substitute':    rec(VANISH, S('Substitute', size=0.9)),
    'Steal':         rec(DASH, P('SpeedLines', orient=True, size=1.0, time=0.15), T('QuickSwipe', orient=True), R('Sack', size=0.25, arc=50, spin=360)),
    'Hatch':         rec(H, S('Egg', size=0.35), S('EggCrack', size=0.45), S('HatchFlash', size=1.2), S('Confetti', size=1.0, par=True)),
    'Fly':           rec(DIVE, S('FeatherFall', size=1.0), T('PowerfulHit', size=1.0), T('DustBurst', size=0.8, par=True)),
    'BraveBird':     rec(DASH, P('BraveBird', orient=True, time=0.15, size=0.7), T('PowerfulHit', size=1.3), T('Feathers', size=1.0, par=True)),
    'Peck':          rec(L, T('Beak', size=0.35, orient=True), T('SmallSlash', size=0.7, par=True)),
    'DrillPeck':     rec(SPIN, T('Beak', size=0.35, orient=True, count=3, stagger=0.1, jitter=0.12), T('QuickBurst', size=0.8)),
    'Dig':           rec(VSTRIKE, S('DustBurst', size=1.0), T('RockScatter', size=1.0), T('DustBurst', size=1.0, par=True, off=[0, 0.3])),
    'FeintAttack':   rec(VSTRIKE, T('HiddenDarkShadowStrike', size=1.2), T('PurpleCrescent', size=0.7, par=True)),
    'ShadowSneak':   rec(VSTRIKE, T('ShadowSneak/Move', size=0.9, off=[0, 0.35]), T('ShadowSneak/Effect', size=1.0)),
    'Pursuit':       rec(DASH, P('ShadowSneak/Move', size=0.9, time=0.2), T('HiddenDarkShadowStrike', size=1.1)),
    'Earthquake':    rec(K, Q(1.0), T('DustBurst', size=1.3, par=True), T('RockChips', size=0.9, par=True, delay=0.15), B('RockScatter', size=0.7, par=True)),
    'Magnitude':     rec(K, Q(0.8), T('RockScatter', size=1.0, par=True, delay=0.1), T('DustBurst', size=1.0, par=True)),
    'Fissure':       rec(K, Q(1.0), T('SandFall', anchor='bottom', size=1.4, off=[0, 0.45], par=True), T('RockDebris', size=1.0, par=True, delay=0.2)),
    'RockThrow':     rec(H, P('RockThrow', arc=80, spin=540, size=0.3), T('RockSmash', size=1.0), T('RockDebris', size=0.8, par=True)),
    'RockSlide':     rec(K, D('RockfallMed', anchor='bottom', size=1.2, time=0.0, off=[0, 0.4]), T('RockDebris', size=1.0), T('DustBurst', size=1.0, par=True)),
    'MudSlap':       rec(W, P('MudBall', size=0.3, count=2, stagger=0.1, arc=30), T('Bomb', size=1.0)),
    'Spin':          rec(SPIN, T('SpinningSlash', size=1.0), T('SimpleAttack', par=True, delay=0.1, size=0.8)),
    'Rollout':       rec(SPIN, T('Slam', size=1.1), T('DustBurst', size=0.8, par=True, off=[0, 0.3])),
    'FlameWheel':    rec(SPIN, P('FlameWheel', size=0.6, spin=720, time=0.18), T('FlameWheel', size=1.0, spin=360), T('FireSparks', size=0.9, par=True)),
    'HornDrill':     rec(SPIN, T('SpinningSlash', size=0.9), T('PowerfulHit', size=1.1)),
    'Punch':         rec(L, T('Fist', size=0.45), T('QuickBurst', size=0.7, par=True, delay=0.05)),
    # ---- fire ----
    'Ember':         rec(H, P('FireDart', orient=True, size=0.35), T('Ember', size=0.9), T('FireSparks', size=0.8, par=True)),
    'Flare':         rec(H, T('Ember', size=1.0), T('Embers', size=0.9, par=True), T('MiniCombustion', size=0.4, par=True, delay=0.1, count=2, stagger=0.1, jitter=0.2)),
    'Fireball':      rec(H, P('FireOrb', size=0.35, spin=360), T('FireballCombust', size=0.9), T('FireSparks', size=0.8, par=True)),
    'BigFireball':   rec(CHARGE, P('FireOrb', size=0.55, grow=[0.6, 1.2]), T('Combustion2', size=1.1), T('FireBursts', size=1.0, par=True, delay=0.1)),
    'Flamethrower':  rec(H, P('FireBullet', orient=True, size=0.55, count=6, stagger=0.06), T('FireBursts', size=1.1), T('Embers', size=1.0, par=True, delay=0.1)),
    'FireBlast':     rec(CHARGE, S('FireRing', size=0.7, dur=0.45), P('FireBlast/000', spin=720, size=0.55), T('FireBlast/001', size=1.4), T('Embers', size=1.0, par=True, delay=0.3)),
    'FlamePillar':   rec(H, T('FlameColumn', anchor='bottom', size=1.3, off=[0, 0.45]), T('UpwardShootingFire', anchor='bottom', size=1.2, off=[0.2, 0.45], par=True, delay=0.1), T('Embers', size=1.0, par=True)),
    'FireSpin':      rec(W, T('FireRing', size=1.0), T('FireSpin', size=1.1, par=True), T('FireSpinningTower', anchor='bottom', size=1.0, off=[0, 0.4], par=True, delay=0.3)),
    'WillOWisp':     rec(W, P('DarkFlame/DarkFlame2', size=0.35, arc=-40, count=3, stagger=0.1), T('Willowisp', size=0.9)),
    'BlueFlame':     rec(H, P('BlueComet', orient=True, size=0.5), T('BlueFlame', size=0.8), T('DarkFlame/DarkFlame', size=1.0, hue=-70, par=True)),
    'SacredFire':    rec(CHARGE, P('FireBlast/000', spin=720, size=0.5, hue=30), T('FlameColumn', anchor='bottom', size=1.4, off=[0, 0.45]),
                         T('FireBlast/001', size=1.2, par=True, delay=0.15), T('Embers', size=1.0, par=True, delay=0.3)),
    'HeatWave':      rec(W, T('FireSpin', size=1.2), T('Embers', size=1.0, par=True), T('Smoke', size=0.8, par=True, tint='#ffb080')),
    'FireCharge':    rec(CHARGE, S('MiniRedPowerup', size=0.9), S('Embers', size=1.0, par=True), S('FireSpinningTower', anchor='bottom', size=0.8, off=[0, 0.45], par=True, delay=0.2)),
    'FireTail':      rec(L, T('FireSweep', size=0.9), T('Ember', size=0.8, par=True, delay=0.1), T('FireSparks', size=0.8, par=True, delay=0.1)),
    # ---- water ----
    'Bubble':        rec(H, P('BigBubble', size=0.25, count=3, stagger=0.1, arc=-20), T('BubbleBurst', size=0.9), T('BubblePop', size=0.8, par=True)),
    'Bubblebeam':    rec(H, P('BubbleSmall', size=0.2, count=9, stagger=0.045, jitter=0.12), T('BubbleTrio', size=0.8), T('BubblePop', size=1.0, par=True)),
    'WaterGun':      rec(H, P('WaterBall', size=0.25, count=3, stagger=0.08), T('WaterBallBurst', size=0.9), T('SplashAttack/001', size=0.8, par=True)),
    'WaterPulse':    rec(H, P('WaterPulse', orient=True, size=0.5), T('BlueRings', size=1.0), T('SplashAttack/002', size=1.0, par=True)),
    'HydroPump':     rec(CHARGE, BM('LightBeam', size=0.6, tint='#70b8ff', dur=0.8), P('WaterBall', size=0.3, count=4, stagger=0.1, par=True),
                         T('WaterGeyser', anchor='bottom', size=1.3, off=[0, 0.45], delay=0.2, par=True), T('SplashAttack/000', size=1.2, par=True, delay=0.3)),
    'Splash':        rec(H, S('WaterGeyser', anchor='bottom', size=0.9, off=[0, 0.45]), S('WaterSplash', size=0.8, par=True)),
    'SplashHit':     rec(L, T('WaterBallBurst', size=1.0), T('SplashAttack/001', size=0.8, par=True)),
    'Waterfall':     rec(L, T('DownPour', anchor='bottom', size=1.2, off=[0, 0.4], dur=0.6), T('WaterGeyser', anchor='bottom', size=1.2, off=[0, 0.45])),
    'Surf':          rec(W, SC('WaterGeyser', anchor='bottom', size=1.4, off=[0, 0.45], count=3, stagger=0.12, jitter=0.3),
                         T('SplashAttack/000', size=1.3, par=True, delay=0.25), B('SplashAttack/001', size=0.7, par=True, delay=0.3)),
    'TidalWave':     rec(K, SC('WaterGeyser', anchor='bottom', size=1.6, off=[0, 0.45], count=4, stagger=0.1, jitter=0.4),
                         T('BubbleColumn', anchor='bottom', size=1.3, off=[0, 0.45], par=True, delay=0.15), T('SplashAttack/000', size=1.4, par=True, delay=0.25),
                         T('DownPour', anchor='bottom', size=1.3, off=[0, 0.4], par=True, delay=0.1), Q(0.6, par=True)),
    'Rain':          rec(H, T('RainStreaks', size=0.8, count=4, stagger=0.1, jitter=0.3, loops=2), T('DownPour', anchor='bottom', size=1.3, off=[0, 0.4], par=True)),
    'AquaRing':      rec(RISE, S('AquaRing', size=1.0), S('BubblesRising', size=0.9, par=True)),
    'Steam':         rec(W, T('BlueSmoke', size=1.1, tint='#e0f0ff'), T('Smoke', size=0.9, par=True, delay=0.15), T('BubblesRising', size=0.8, par=True)),
    # ---- ice ----
    'IceBeam':       rec(H, BM('LightBeam', size=0.5, tint='#a8f0ff', dur=0.7), P('IceDart', orient=True, size=0.35, count=3, stagger=0.08, par=True),
                         T('IceSparkle', size=1.1, delay=0.2, par=True), T('CyanBurst', size=0.9, par=True, delay=0.3)),
    'AuroraBeam':    rec(H, BM('LightBeam', size=0.55, hue_cycle=540, dur=0.8), T('IceSparkle', size=1.0, delay=0.25, par=True), T('RockTombBlueIce', size=1.0, par=True, delay=0.3)),
    'IcyWind':       rec(W, P('Snowflake', size=0.2, spin=540, count=5, stagger=0.07, jitter=0.2), T('IcyWind/001', size=1.1, anchor='bottom', off=[0, 0.35]), T('IceDust', size=0.9, par=True)),
    'PowderSnow':    rec(W, D('Snowflake', size=0.2, spin=360, count=6, stagger=0.08, jitter=0.3, time=0.35), T('IceDust', size=1.0), T('IceAttack/001', size=0.9, par=True)),
    'Blizzard':      rec(K, SC('Gust', size=1.8, tint='#d0f0ff'), D('Snowflake', size=0.22, spin=540, count=10, stagger=0.06, jitter=0.45, time=0.35, par=True),
                         T('IceSparkle', size=1.2, par=True, delay=0.35), T('IceAttack/000', size=1.3, par=True, delay=0.4), B('IceAttack/001', size=0.7, par=True, delay=0.4)),
    'Freeze':        rec(W, T('RockTombBlueIce', size=1.2), T('IceSparkle', size=1.0, par=True, delay=0.4)),
    'IceShard':      rec(H, P('IceDart', orient=True, size=0.4), T('IceCrash/000', size=1.0), T('IceSparkle', size=0.8, par=True)),
    'Hail':          rec(H, D('IceCrash/001', size=0.3, count=5, stagger=0.09, jitter=0.3, time=0.3), T('Hail', size=1.0), T('IceCrash/000', size=0.9, par=True)),
    'IcePunch':      rec(L, T('MegaPunch', size=1.0), T('IceCrash/000', size=1.0, par=True, delay=0.05), T('IceSparkle', size=0.9, par=True, delay=0.1)),
    'SheerCold':     rec(CHARGE, S('IceDust', size=1.0), T('RockTombBlueIce', size=1.3), T('IceAttack/000', size=1.4, par=True, delay=0.3), T('CyanBurst', size=1.0, par=True, delay=0.5)),
    # ---- electric ----
    'Spark':         rec(H, T('Spark', size=0.9), T('SparkScatter', size=0.9, par=True)),
    'ThunderShock':  rec(H, T('ThunderShock', anchor='bottom', size=1.1, off=[0, 0.25]), T('Spark', size=0.8), T('SparkScatter', size=0.9, par=True)),
    'Thunderbolt':   rec(CHARGE, S('ElectricGather', size=1.0, dur=0.4), T('ThunderBolt', anchor='bottom', size=1.4, off=[0, 0.3]),
                         T('Discharge', size=1.0, par=True, delay=0.3), T('SparkBurst', size=1.0, par=True, delay=0.35)),
    'Thunder':       rec(CHARGE, T('Thunder', anchor='bottom', size=1.6, off=[0, 0.3], loops=2), T('Discharge', size=1.3), T('SparkScatter', size=1.2, par=True), Q(0.4, par=True)),
    'ThunderWave':   rec(W, P('LightningDart', orient=True, size=0.3, count=3, stagger=0.08), T('Electrocute', size=1.0, loops=2)),
    'ElectroBall':   rec(H, P('SparkOrb', size=0.45), T('Discharge', size=1.0), T('SparkScatter', size=0.9, par=True)),
    'LightningBall': rec(H, P('SparkOrb', size=0.4, spin=360), T('Spark', size=1.0), T('SparkBurst', size=0.9, par=True)),
    'Charge':        rec(CHARGE, S('ElectricGather', size=1.0), S('Charge', size=1.0)),
    'ElectricTackle':rec(DASH, P('LightningDart', orient=True, size=0.35, time=0.15), T('ElectroShock', size=0.8), T('Spark', size=1.0, par=True)),
    # ---- grass ----
    'RazorLeaf':     rec(H, S('RazorLeafPowerUp', size=1.0, dur=0.4), P('Leaf', size=0.3, spin=900, count=6, stagger=0.05, jitter=0.15), T('LeafNeedles1', size=1.0)),
    'LeafStorm':     rec(K, S('RazorLeafPowerUp', size=1.0, dur=0.4), P('Leaf', size=0.3, spin=900, count=10, stagger=0.04, jitter=0.3),
                         T('LeafNeedles2', size=1.1), T('PetalBlizzard', size=0.9, par=True, hue=-90)),
    'MagicalLeaf':   rec(H, S('MagicalLeaf/PowerUp', size=1.0), P('MagicalLeaf/Projectile', size=0.5, spin=540, hue_cycle=720), T('SmallSlash', size=0.8)),
    'LeechSeed':     rec(H, P('Seed', arc=60, size=0.15, count=3, stagger=0.08), T('LeechSeed/001', size=0.9, anchor='bottom', off=[0, 0.3]),
                         R('GreenSparkle', size=0.3, count=3, stagger=0.1), S('Heal1', size=0.7, tint='#a0ff80')),
    'Solarbeam':     rec(CHARGE, S('Photosynthesis', size=0.7, loops=2), S('SunRing', size=0.9, par=True), BM('LightBeam', size=0.65, tint='#fff4b0', dur=0.8),
                         T('GreenEnergyHit', size=1.2, par=True, delay=0.25), T('GreenBurst', size=1.0, par=True, delay=0.3)),
    'EnergyBall':    rec(H, P('GreenOrb', size=0.4), T('GreenBloom', size=1.0), T('EnergyBall/002', size=1.0, par=True)),
    'GreenHit':      rec(H, P('SeedBomb', size=0.3, arc=60, spin=360), T('GreenBurst', size=1.0), T('GreenEnergyHit', size=0.9, par=True)),
    'Absorb':        rec(W, T('GreenGlint', size=0.6), T('AbsorbingLights', size=1.0, par=True), R('GreenSparkle', size=0.3, count=3, stagger=0.1), S('Heal1', size=0.7)),
    'MegaDrain':     rec(W, T('GreenEnergyHit', size=0.9), R('GreenSparkle', size=0.35, count=5, stagger=0.08), S('NatureRecovery', size=0.9), S('GreenBloom', size=0.8, par=True)),
    'Growth':        rec(GROW, S('LeafPowerUp', size=1.0), S('GreenSparkle', size=0.6, par=True, count=3, stagger=0.1, jitter=0.3), S('StatUp', **STAT_UP)),
    # ---- poison ----
    'Acid':          rec(W, P('PoisonBubbles', size=0.3, count=3, stagger=0.08, arc=30), T('QuickPoisonHit', size=1.0), T('PoisonColumn', size=0.6, par=True)),
    'Sludge':        rec(W, P('SludgeOrb', size=0.35, arc=60), T('SmokeBombAttack/001', size=1.0), T('PoisonColumn', size=0.7, par=True)),
    'PoisonGas':     rec(W, T('SmokeBombAttack/001', size=1.1), T('PoisonColumn', size=0.7, par=True, delay=0.2)),
    'Smog':          rec(W, P('SmokeBombAttack/000', size=0.35, arc=50), T('SmokeBombAttack/001', size=1.1), T('PoisonColumn', size=0.6, par=True)),
    'Toxic':         rec(W, T('ToxicSpike', size=0.9, count=2, stagger=0.12, jitter=0.2), T('CrossPoison', size=0.9), T('PoisonColumn', size=0.7, par=True)),
    # ---- psychic ----
    'Confusion':     rec(W, T('PinkPulse', size=1.0), T('MiniPyschic', size=1.0, par=True, delay=0.1)),
    'Psychic':       rec(W, T('PsychoOrb', size=1.0), T('PsychicAttack', size=1.1, par=True, delay=0.15)),
    'Psybeam':       rec(W, BM('LightBeam', size=0.5, tint='#ffa0f0', hue_cycle=300, dur=0.7), T('PinkPulse', size=1.0, par=True, delay=0.2)),
    'PsychicBlast':  rec(CHARGE, S('PsychicPowerUp', size=0.9, dur=0.5), T('MassivePsychichBlast', size=1.3), T('PinkPulse', size=1.1, par=True)),
    'MistBall':      rec(H, P('MistBall', size=0.45, spin=180), T('PsychicAttack', size=1.0), T('CloudPuff', size=1.0, par=True)),
    'Hypnosis':      rec(W, T('HypnoSpiral', size=0.6, spin=360, loops=2), T('PsychicLights', size=0.9, par=True, delay=0.15)),
    'Amnesia':       rec(H, S('Amnesia', size=1.0), S('StatUp', **STAT_UP)),
    'Meditate':      rec(RISE, S('PsychicPowerUp', size=1.0), S('StatUp', **STAT_UP)),
    'Barrier':       rec(GROW, S('Protect', size=1.1, hue=150), S('StatUp', **STAT_UP)),
    'Telekinesis':   rec(W, T('PsychicPalm', size=1.0), T('PsychicLights', size=0.9, par=True)),
    # ---- dark / ghost ----
    'ShadowBall':    rec(W, P('ShadowBall', size=0.45, spin=360, grow=[0.6, 1.1]), T('DarknessEngulf', size=1.1), T('ShadowSpark', size=0.9, par=True)),
    'DarkSlash':     rec(L, T('DarkSlash', size=1.1), T('PurpleCrescent', size=0.7, par=True, delay=0.1)),
    'MetalSound':    rec(K, T('MetalSound', size=1.1), T('SoundRings', size=1.0, par=True, hue=180), T('StatDown', delay=0.2, **STAT_DOWN)),
    # ---- dragon ----
    'Dragonbreath':  rec(H, P('BlueComet', orient=True, size=0.5, count=2, stagger=0.1), T('BlueFlame', size=0.9), T('Combustion2', size=1.0, hue=-140, par=True)),
    'DragonRage':    rec(CHARGE, S('RoarOfTime/000', size=1.1, dur=0.6), P('BlueComet', orient=True, size=0.55), T('DarkCombustion', size=1.2, hue=170)),
    'DragonDance':   rec(GROW, S('PowerUpRings', size=1.0, hue=140), S('MiniRedPowerup', size=0.9, par=True), S('StatUp', **STAT_UP)),
})

# ---------------- ELEMENTS: the colours a card takes on ----------------
#   glow   the attacker's tint as it charges / powers up
#   flash  the defender's flash at the hit (r, g, b -- values over 1 brighten)
#   linger the defender's tint after the flash, fading over linger_time ("fade", "flicker" or "pulse")
ELEMENTS = {
    'normal':   {'glow': '#ffffff', 'flash': [3.0, 3.0, 3.0]},
    'fire':     {'glow': '#ffa050', 'flash': [3.0, 1.9, 1.1], 'linger': '#ff9060', 'linger_mode': 'fade', 'linger_time': 0.9},
    'water':    {'glow': '#70b8ff', 'flash': [1.7, 2.3, 3.0], 'linger': '#90c8ff', 'linger_mode': 'fade', 'linger_time': 0.6},
    'electric': {'glow': '#fff070', 'flash': [3.0, 3.0, 1.5], 'linger': '#fff080', 'linger_mode': 'flicker', 'linger_time': 0.8},
    'grass':    {'glow': '#90f070', 'flash': [1.9, 3.0, 1.6], 'linger': '#b0f0a0', 'linger_mode': 'fade', 'linger_time': 0.5},
    'ice':      {'glow': '#b0f4ff', 'flash': [2.2, 3.0, 3.0], 'linger': '#a0e8ff', 'linger_mode': 'fade', 'linger_time': 1.3},
    'fighting': {'glow': '#ffb080', 'flash': [3.0, 2.4, 2.0]},
    'psychic':  {'glow': '#ff90e0', 'flash': [3.0, 1.9, 2.9], 'linger': '#f4b0ff', 'linger_mode': 'pulse', 'linger_time': 0.8},
    'poison':   {'glow': '#c080ff', 'flash': [2.5, 1.5, 3.0], 'linger': '#c890ff', 'linger_mode': 'pulse', 'linger_time': 1.0},
    'dark':     {'glow': '#9070b0', 'flash': [1.8, 1.5, 2.2], 'linger': '#6a6a80', 'linger_mode': 'fade', 'linger_time': 0.9},
    'ghost':    {'glow': '#a890ff', 'flash': [2.0, 1.7, 3.0], 'linger': '#9a8cd0', 'linger_mode': 'fade', 'linger_time': 0.9},
    'metal':    {'glow': '#d8e0f8', 'flash': [2.7, 2.9, 3.0], 'linger': '#d0d8f0', 'linger_mode': 'fade', 'linger_time': 0.4},
    'dragon':   {'glow': '#9090ff', 'flash': [2.1, 2.1, 3.0], 'linger': '#b0b0ff', 'linger_mode': 'fade', 'linger_time': 0.6},
    'flying':   {'glow': '#e8f4ff', 'flash': [3.0, 3.0, 3.0]},
    'ground':   {'glow': '#e0b070', 'flash': [3.0, 2.5, 1.7], 'linger': '#e0c090', 'linger_mode': 'fade', 'linger_time': 0.5},
    'rock':     {'glow': '#d0b890', 'flash': [2.8, 2.5, 2.0]},
    'bug':      {'glow': '#c0e850', 'flash': [2.5, 3.0, 1.5]},
    'fairy':    {'glow': '#ffc0e8', 'flash': [3.0, 2.3, 2.8], 'linger': '#ffd0ec', 'linger_mode': 'fade', 'linger_time': 0.6},
    'heal':     {'glow': '#90ffb0', 'flash': [2.0, 3.0, 2.2]},
    'sound':    {'glow': '#ffe0b0', 'flash': [3.0, 2.8, 2.4]},
}

# Recipe -> element. Anything not listed is guessed from its name (ELEMENT_GUESS), else "normal".
ELEMENT_OF = {
    'fire': 'SunnyDay Ember Flare Fireball BigFireball Flamethrower FireBlast FireSpin FlamePillar FlameWheel FirePunch BlazeKick FireFang FireClaw FireTail '
            'Inferno Eruption HotRocks Magma FireWall FireBurst Combustion Sunburn SacredFire FlameStar HeatWave FireCharge',
    'water': 'Bubble Bubblebeam WaterGun WaterPulse HydroPump Splash SplashHit WaterSlash Waterfall Surf TidalWave Rain Whirlpool AquaRing '
             'Octazooka Crabhammer Steam Clamp',
    'ice': 'IceBeam AuroraBeam IcyWind PowderSnow Blizzard Freeze IceShard Icicle Hail IcePunch IceFang IceWing SheerCold',
    'electric': 'Spark ThunderShock Thunderbolt Thunder ThunderWave ThunderPunch ThunderFang ElectricTackle ElectroBall LightningBall ZapCannon '
                'Discharge Charge ReverseCharge Gigashock ChainLightning Magnet MagnetBomb LightSlash FingerStorm',
    'grass': 'VineWhip VineWrap RazorLeaf LeafStorm MagicalLeaf LeafBlade PetalDance PetalBlizzard SleepPowder StunSpore CottonSpore LeechSeed '
             'Growth Ingrain Roots Photosynthesis Solarbeam EnergyBall BulletSeed NaturalPower NatureRecovery Seeds GrassKnot GreenHit '
             'MegaDrain Spore Absorb NatureBoost',
    'poison': 'PoisonPowder Acid Sludge PoisonGas Smog Toxic PoisonFang PoisonClaw CrossPoison PoisonHorn PoisonTentacle PoisonSpray PoisonSting',
    'psychic': 'Confusion Psychic Psybeam Psywave Psyshock PsychicBlast PsychicBall MistBall MindShock PsychicLights Hypnosis Amnesia Meditate '
               'Psypunch PsyPalm SpoonBend Telekinesis Future Barrier PsychicDamage ConfuseRay MindReader Lunar Teleport TeleportBeam Copy',
    'ghost': 'WillOWisp Nightmare DreamEater Curse CurseCounters Spite DestinyBond PainSplit Haunt NightShade PerishSong',
    'dark': 'ShadowBall ShadowPunch ShadowClaw ShadowSneak FeintAttack DarkSlash Bite Crunch HyperFang DarkWave DarkPulse DarkMind DarkCloud '
            'DarknessEngulf DarkBlast EvilForce DarkPowerUp Pursuit MeanLook Leer Glare ScaryFace Taunt Torment EvilKiss NastyPlot DarkSing '
            'DarkFlame Steal',
    'metal': 'MetalClaw IronTail SteelWing MetalSound SteelOrb MetalBall SteelPunch IronDefense Harden Withdraw',
    'dragon': 'DragonRage Dragonbreath DragonClaw RoarOfTime Outrage DragonDance Meteor BlueFlame',
    'fighting': 'AuraSphere Punch MegaPunch MegaKick Kick DoubleKick TripleKick CatKick CometPunch RapidPunches DynamicPunch DizzyPunch DrainPunch '
                'FistSlam GrabCrush CrossChop KarateChop ForcePalm Palm OneSlap WakeUpSlap SeismicToss Submission Counter Focus',
    'ground': 'Earthquake Magnitude Fissure Dig SandAttack Sandstorm SandTomb MudSlap MudSport Bonemerang BoneClub BoneRush',
    'rock': 'RockSmash RockThrow RockSlide Avalanche RockTomb StoneEdge AncientPower RockBlast Pebbles',
    'flying': 'Gust Whirlwind Twister Hurricane AirCutter AirSlash RazorWind Sonicboom Fly BraveBird WingAttack Peck DrillPeck FuryAttack '
              'SilverWind RainbowWing',
    'bug': 'Megahorn StringShot BugSwarm BugBuzz PinMissile Sting Twineedle TripleNeedle SignalBeam LeechLife Web',
    'fairy': 'Charm SweetKiss Attract Wish Glitter Moonlight MoonAttack Sing Present Cheer Encore Clap Flatter Swagger Hidden Power '
             'FollowMe CallForFamily Whisper HealingSong ChantingBell',
    'heal': 'Recover Heal HealBench Softboiled MilkDrink Rest',
    'sound': 'Growl Roar Screech HyperVoice Supersonic',
}
ELEMENT_GUESS = [(r'Fire|Flame|Ember|Burn|Heat|Magma|Lava', 'fire'), (r'Water|Aqua|Bubble|Hydro|Splash', 'water'),
                 (r'Ice|Freez|Snow|Hail', 'ice'), (r'Thunder|Spark|Electr|Zap|Volt', 'electric'), (r'Leaf|Vine|Petal|Seed|Nature', 'grass'),
                 (r'Poison|Toxic|Sludge', 'poison'), (r'Psy|Mind', 'psychic'), (r'Dark|Shadow|Evil', 'dark'), (r'Metal|Steel|Iron', 'metal'),
                 (r'Rock|Stone', 'rock'), (r'Dragon', 'dragon')]

# ---------------- BODIES / REACTIONS / POWER / SCREEN ----------------
# (anything not listed keeps the body it was built with; reaction defaults to "knock")
BODY_OF = {
    LEAP: 'BodySlam Stomp Trample Bounce',
    SPIN: 'Spin Rollout FlameWheel HornDrill DrillPeck',
    DASH: 'QuickAttack TakeDown GigaImpact BraveBird Pursuit ElectricTackle Steal Megahorn',
    VSTRIKE: 'Dig FeintAttack ShadowSneak',
    DIVE: 'Fly',
    CHARGE: 'Explosion Selfdestruct HyperBeam FireBlast BigFireball SacredFire HydroPump Thunderbolt Thunder ZapCannon Solarbeam '
            'PsychicBlast DarkBlast DarkPulse DragonRage RoarOfTime Meteor SheerCold Focus Charge FireCharge EnergyOut',
    VANISH: 'Teleport SmokeEscape Switch Substitute',
    RISE: 'Recover Heal AquaRing Meditate Moonlight Wish',
    GROW: 'SwordsDance Harden IronDefense PowerUp PowerUpRings PowerUpLights PowerUpNoRing Growth Barrier DragonDance Endure NaturalPower',
    SHRINK: 'Withdraw Minimize',
}
REACT_OF = {
    'multi':   'FurySwipes DoubleSlap CometPunch RapidPunches DoubleKick TripleKick FuryAttack PinMissile Twineedle TripleNeedle BulletSeed '
               'Barrage GangUp BeatUp DoubleClaw DoubleSlash ShadowPunch Bubblebeam Swift MiniExplosions DragonClaw Thrash Outrage Trample '
               'BoneRush DrillPeck RazorLeaf LeafStorm WaterGun Flamethrower AirSlash VineWhip MultiPunch ShootingStar Hail',
    'spin':    'DizzyPunch DynamicPunch Twister Whirlwind Gust Hurricane Whirlpool Confusion ConfuseRay Supersonic FireSpin AirCutter',
    'lift':    'SeismicToss Psychic Telekinesis Fling PsychicBlast',
    'squash':  'BodySlam Stomp Slam GigaImpact Submission FistSlam Rock Avalanche RockSlide Waterfall Fly Bounce',
    'squeeze': 'Wrap Bind Constrict Squeeze VineWrap GrabCrush PoisonTentacle Clamp ViceGrip Crabhammer Roots GrassKnot Web StringShot',
    'jolt':    'Spark ThunderShock Thunderbolt Thunder ThunderWave ThunderPunch ThunderFang ElectricTackle ElectroBall LightningBall ZapCannon '
               'Discharge Gigashock ChainLightning Magnet MagnetBomb FingerStorm',
    'shake':   'Earthquake Magnitude Fissure Sandstorm Roar HyperVoice Screech MetalSound Eruption',
    'freeze':  'IceBeam AuroraBeam Blizzard Freeze SheerCold IcyWind PowderSnow',
}
HITS_OF = {2: 'DoubleSlap DoubleKick Twineedle DoubleClaw DoubleSlash ShadowPunch DragonClaw Trample VineWhip AirSlash',
           3: 'FurySwipes TripleKick PinMissile TripleNeedle Barrage GangUp Bubblebeam Swift MiniExplosions Thrash Outrage BoneRush DrillPeck '
              'RazorLeaf WaterGun ShootingStar Hail',
           4: 'CometPunch FuryAttack BulletSeed BeatUp LeafStorm Flamethrower MultiPunch',
           5: 'RapidPunches'}
HEAVY = ('GigaImpact TakeDown BodySlam Megahorn MegaPunch MegaKick DynamicPunch FistSlam CrossChop SteelPunch Explosion Selfdestruct '
         'HyperBeam FireBlast SacredFire Inferno Eruption Magma HydroPump TidalWave Thunder ZapCannon Gigashock Solarbeam LeafStorm '
         'PsychicBlast DarkBlast DarkPulse RoarOfTime Meteor DragonRage Outrage Earthquake Fissure Avalanche StoneEdge RockBlast '
         'Blizzard SheerCold Hurricane BraveBird SeismicToss Guillotine HornDrill Waterfall Submission IronTail DragonClaw HyperFang')
RECOIL = 'TakeDown BraveBird GigaImpact Selfdestruct'
SCREEN_OF = {
    'Explosion': {'flash': '#ffffff', 'shake': 14}, 'Selfdestruct': {'flash': '#fff4d0', 'shake': 10},
    'HyperBeam': {'flash': '#ffd0a0', 'shake': 8}, 'GigaImpact': {'shake': 10}, 'TakeDown': {'shake': 5}, 'BodySlam': {'shake': 6},
    'Megahorn': {'shake': 6}, 'MegaPunch': {'shake': 5}, 'MegaKick': {'shake': 5}, 'DynamicPunch': {'shake': 7}, 'FistSlam': {'shake': 6},
    'SeismicToss': {'shake': 8}, 'Submission': {'shake': 5}, 'Trample': {'shake': 4},
    'FireBlast': {'flash': '#ffb060', 'shake': 6}, 'SacredFire': {'flash': '#ffe0a0', 'shake': 6}, 'Inferno': {'flash': '#ff8040', 'shake': 6},
    'Eruption': {'shake': 12, 'flash': '#ff8040'}, 'Magma': {'shake': 7},
    'HydroPump': {'shake': 6}, 'TidalWave': {'shake': 9, 'dim': 0.2}, 'Surf': {'shake': 4},
    'Thunder': {'flash': '#fffbe0', 'shake': 10, 'dim': 0.35}, 'Thunderbolt': {'flash': '#fff8c0', 'shake': 4}, 'ZapCannon': {'flash': '#fff8a0', 'shake': 8},
    'Gigashock': {'flash': '#fff8c0', 'shake': 8, 'dim': 0.3}, 'Discharge': {'flash': '#fff8c0', 'shake': 4}, 'ChainLightning': {'dim': 0.3, 'shake': 5},
    'Solarbeam': {'flash': '#fff8d0', 'shake': 7}, 'LeafStorm': {'shake': 5},
    'Blizzard': {'flash': '#e0f8ff', 'shake': 6, 'dim': 0.25}, 'SheerCold': {'flash': '#c0f0ff', 'dim': 0.45, 'shake': 8}, 'IceBeam': {'flash': '#d8f8ff'},
    'AuroraBeam': {'flash': '#f0e0ff'},
    'Psychic': {'dim': 0.3}, 'PsychicBlast': {'dim': 0.4, 'flash': '#ffc0f0', 'shake': 7}, 'Hypnosis': {'dim': 0.35}, 'Future': {'dim': 0.3},
    'MindShock': {'dim': 0.25}, 'Lunar': {'dim': 0.4, 'flash': '#fff0c0'},
    'ShadowBall': {'dim': 0.35}, 'DarkPulse': {'dim': 0.45, 'shake': 7}, 'DarkBlast': {'dim': 0.45, 'shake': 8}, 'NightShade': {'dim': 0.45},
    'Haunt': {'dim': 0.4}, 'EvilForce': {'dim': 0.4}, 'DarkMind': {'dim': 0.35}, 'DarkCloud': {'dim': 0.35}, 'DarknessEngulf': {'dim': 0.4},
    'Nightmare': {'dim': 0.45}, 'DreamEater': {'dim': 0.45}, 'Curse': {'dim': 0.45}, 'CurseCounters': {'dim': 0.35}, 'Spite': {'dim': 0.35},
    'DestinyBond': {'dim': 0.45}, 'PainSplit': {'dim': 0.3}, 'PerishSong': {'dim': 0.45}, 'MeanLook': {'dim': 0.3}, 'Glare': {'dim': 0.25},
    'Moonlight': {'dim': 0.45}, 'MoonAttack': {'dim': 0.4}, 'Teleport': {'flash': '#ffe0ff'}, 'Flash': {'flash': '#ffffff'},
    'RoarOfTime': {'dim': 0.4, 'flash': '#c0d0ff', 'shake': 12}, 'Meteor': {'flash': '#ffe0c0', 'shake': 14}, 'DragonRage': {'shake': 7},
    'Outrage': {'shake': 6}, 'Earthquake': {'shake': 10}, 'Magnitude': {'shake': 7}, 'Fissure': {'shake': 12}, 'Avalanche': {'shake': 9},
    'RockSlide': {'shake': 5}, 'StoneEdge': {'shake': 6}, 'RockBlast': {'shake': 5}, 'Hurricane': {'shake': 5}, 'BraveBird': {'shake': 7},
    'Guillotine': {'flash': '#ffffff', 'shake': 6}, 'HornDrill': {'shake': 6}, 'Roar': {'shake': 4}, 'HyperVoice': {'shake': 5},
    'Hatch': {'flash': '#fffbe0'}, 'Present': {'flash': '#fff8e0'}, 'Wish': {'dim': 0.3}, 'SunnyDay': {'flash': '#fff4c0'},
    'Sunburn': {'flash': '#fff0b0'},
}


# ---------------- BENCH HITS ----------------
# What plays on each benched Pokémon an attack damages (Attack_VFX.bench_hit, driven by the real damage,
# one card after another). Recipes not listed use a smaller copy of their own impact effect.
BENCH_FX = {
    'Earthquake': T('RockScatter', size=0.8), 'Magnitude': T('RockScatter', size=0.7), 'Fissure': T('RockDebris', size=0.8),
    'Avalanche': T('RockDebris', size=0.8), 'RockSlide': T('RockDebris', size=0.7), 'Sandstorm': T('SandAttack', size=0.8),
    'Selfdestruct': T('SmallBomb', size=0.8), 'Explosion': T('MiniExplosions', size=0.9), 'MiniExplosions': T('MiniExplosions', size=0.7),
    'Blizzard': T('Snowflake', size=0.3, spin=360), 'IcyWind': T('IceDust', size=0.7), 'PowderSnow': T('IceDust', size=0.7),
    'Surf': T('SplashAttack/001', size=0.7), 'TidalWave': T('WaterBallBurst', size=0.8), 'Rain': T('RainStreaks', size=0.6),
    'Gigashock': T('Spark', size=0.7), 'ChainLightning': T('ThunderShock', anchor='bottom', size=0.8), 'Discharge': T('Spark', size=0.7),
    'Thunder': T('Spark', size=0.7), 'Eruption': T('HotRocks/001', size=0.7), 'HeatWave': T('Ember', size=0.7), 'FireSpin': T('Ember', size=0.6),
    'Inferno': T('FireBursts', size=0.7), 'PetalBlizzard': T('PetalBomb', size=0.7), 'LeafStorm': T('LeafNeedles1', size=0.7),
    'Hurricane': T('Gust', size=0.7), 'Twister': T('Gust', size=0.6), 'SilverWind': T('TwinklingStar', size=0.5),
    'Swift': T('YellowStars', size=0.6), 'Psychic': T('PinkPulse', size=0.6), 'PsychicBlast': T('PinkPulse', size=0.7),
    'DarkPulse': T('DarkSwirl', size=0.7), 'Earthquake ': T('RockScatter', size=0.8), 'Spark': T('SparkScatter', size=0.6),
    'Toxic': T('PoisonBubbles', size=0.3), 'PoisonGas': T('PoisonColumn', size=0.5), 'Smog': T('SmokeBombAttack/001', size=0.6),
    'HyperVoice': T('SoundRings', size=0.6), 'Roar': T('SoundRings', size=0.6), 'Screech': T('SoundRings', size=0.6),
    'Meteor': T('Explosion', size=0.7), 'RoarOfTime': T('RoarOfTime/001', size=0.4), 'Bubblebeam': T('BubbleTrio', size=0.5),
}


# ---------------- SOUND ----------------
# Gen 4 move clips (Audio/SFX/Attacks, prepared by attack_sfx_import.py). Every recipe gets one: recipes
# named after a move use that move automatically; these are the rest. A TCG attack that IS a game move
# (Thunderbolt, Ember, Hyper Beam...) plays its own move's clip whatever recipe it uses.
SFX_OF = {
    'Anger': 'Rage', 'Barrage': 'Barrage 1hit', 'BeatUp': 'Beat Up 1hit', 'BigFireball': 'Overheat', 'BlueFlame': 'Will O Wisp',
    'BoneRush': 'Bone Rush 1hit', 'Bonemerang': 'Bonemerang 2hits', 'BugSwarm': 'Attack Order', 'CallForFamily': 'Helping Hand',
    'CatKick': 'Low Kick', 'ChainLightning': 'Discharge', 'ChantingBell': 'Heal Bell', 'Cheer': 'Helping Hand', 'Clap': 'Encore',
    'Combustion': 'Lava Plume', 'CometPunch': 'Comet Punch 1hit', 'Copy': 'Mimic', 'CrossCut': 'X-Scissor', 'Cry': 'Fake Tears',
    'CurseCounters': 'Grudge', 'DarkBlast': 'Dark Pulse', 'DarkCloud': 'Ominous Wind', 'DarkFlame': 'Will O Wisp', 'DarkMind': 'Night Shade',
    'DarkPowerUp': 'Nasty Plot', 'DarkSing': 'Perish Song', 'DarkSlash': 'Night Slash', 'DarkWave': 'Dark Pulse', 'DarknessEngulf': 'Dark Void',
    'DataStrike': 'Lock On', 'Devolve': 'Transform', 'DoubleClaw': 'Crush Claw', 'DoubleSlap': 'Double Slap 1hit', 'DoubleSlash': 'Cut',
    'Draw': 'Recycle', 'ElectricTackle': 'Volt Tackle', 'ElectroBall': 'Shock Wave', 'EnergyAbsorbLong': 'Tail Glow', 'EnergyOut': 'Judgment',
    'EnergyRemove': 'Knock Off', 'EnergyRings': 'Conversion', 'EnergyUp': 'Focus Energy', 'EnergyUpSmall': 'Focus Energy', 'EvilForce': 'Astonish',
    'EvilKiss': 'Lovely Kiss', 'Exclaim': 'Foresight', 'FingerStorm': 'Thunder Shock', 'FireBurst': 'Lava Plume', 'FireCharge': 'Sunny Day',
    'FireClaw': 'Fire Fang', 'FireTail': 'Flame Wheel', 'FireWall': 'Fire Spin', 'Fireball': 'Ember', 'FistSlam': 'Hammer Arm',
    'FlamePillar': 'Lava Plume', 'FlameStar': 'Flame Wheel', 'Flare': 'Ember', 'Focus': 'Focus Energy', 'Freeze': 'Sheer Cold',
    'FuryAttack': 'Fury Attack 1hit', 'Future': 'Future Sight', 'GangUp': 'Beat Up 1hit', 'GenericBeam': 'Charge Beam', 'Gigashock': 'Discharge',
    'Glitter': 'Lucky Chant', 'GrabCrush': 'Crush Grip', 'GreenHit': 'Seed Bomb', 'Hatch': 'Natural Gift', 'Haunt': 'Astonish', 'Heal': 'Recover',
    'HealBench': 'Heal Bell', 'HealingSong': 'Heal Bell', 'HotRocks': 'Lava Plume', 'Hurricane': 'Aeroblast', 'IceWing': 'Icy Wind',
    'Icicle': 'Icicle Spear 1hit', 'Inferno': 'Overheat', 'Kick': 'Low Kick', 'LightBall': 'Flash Cannon', 'LightSlash': 'Psycho Cut',
    'LightningBall': 'Shock Wave', 'Lunar': 'Lunar Dance', 'Magma': 'Magma Storm', 'Magnet': 'Magnet Rise', 'MetalBall': 'Gyro Ball',
    'Meteor': 'Draco Meteor', 'MindShock': 'Extrasensory', 'MiniExplosions': 'Self Destruct', 'Misc': 'Disable', 'MoonAttack': 'Moonlight',
    'NaturalPower': 'Nature Power', 'NatureBoost': 'Growth', 'NatureRecovery': 'Synthesis', 'OneSlap': 'Double Slap 1hit', 'Palm': 'Force Palm',
    'Panic': 'Teeter Dance', 'Pebbles': 'Rock Throw', 'PetalBlizzard': 'Petal Dance', 'Photosynthesis': 'Synthesis', 'Pickup': 'Recycle',
    'PinMissile': 'Pin Missile 1hit', 'PoisonClaw': 'Poison Jab', 'PoisonHorn': 'Poison Jab', 'PoisonSpray': 'Acid', 'PoisonTentacle': 'Wring Out',
    'PowerUp': 'Bulk Up', 'PowerUpLights': 'Cosmic Power', 'PowerUpNoRing': 'Belly Drum', 'PowerUpRings': 'Stockpile', 'PowerfulHit': 'Strength',
    'PsyPalm': 'Force Palm', 'PsychicBall': 'Mist Ball', 'PsychicBlast': 'Psycho Boost', 'PsychicDamage': 'Psychic', 'PsychicLights': 'Miracle Eye',
    'Psypunch': 'Zen Headbutt', 'Psyshock': 'Psycho Cut', 'Punch': 'Mach Punch', 'Question': 'Mimic', 'Rain': 'Rain Dance',
    'RainbowWing': 'Silver Wind', 'RapidPunches': 'Arm Thrust 1hit', 'ReverseCharge': 'Charge', 'RockBlast': 'Rock Blast 1hit', 'Roots': 'Ingrain',
    'Search': 'Odor Sleuth', 'Seeds': 'Bullet Seed', 'ShieldBreak': 'Brick Break', 'ShootingStar': 'Doom Desire', 'Slap': 'Double Slap 1hit',
    'SmallBomb': 'Self Destruct', 'SmokeBurst': 'Smokescreen', 'SmokeEscape': 'In-Battle Switch Flee Run', 'Spin': 'Rapid Spin',
    'SpinningSlash': 'Fury Cutter', 'SplashHit': 'Aqua Tail', 'SpoonBend': 'Kinesis', 'Spotlight': 'Morning Sun', 'Squeeze': 'Constrict',
    'StarBeam': 'Swift', 'StarStrike': 'Swift', 'Steal': 'Thief', 'Steam': 'Mist', 'SteelOrb': 'Flash Cannon', 'SteelPunch': 'Meteor Mash',
    'Sting': 'Pin Missile 1hit', 'Sunburn': 'Heat Wave', 'Sweat': 'Teeter Dance', 'Switch': 'In-Battle Recall Switch Pokeball', 'TailSlap': 'Slam',
    'TailSmash': 'Slam', 'Telekinesis': 'Kinesis', 'TeleportBeam': 'Teleport', 'TidalWave': 'Water Spout', 'Trample': 'Stomp',
    'TripleNeedle': 'Twineedle', 'VineWrap': 'Wrap', 'WaterSlash': 'Aqua Jet', 'Web': 'Spider Web', 'Whisper': 'Grass Whistle',
    'Hidden Power': 'Hidden Power', 'Shockwave': 'Shock Wave', 'SleepPowder': 'Sleep Powder', 'Rest': 'Rest',
}
# Pitch for recipes that borrow a bigger move's sound for a smaller effect (and the reverse).
SFX_PITCH = {'MiniExplosions': 1.25, 'SmallBomb': 1.15, 'Fireball': 0.9, 'Flare': 1.1, 'Pebbles': 1.15, 'EnergyUpSmall': 1.15,
             'OneSlap': 0.95, 'Kick': 1.05, 'TailSlap': 1.1, 'IceWing': 1.1, 'BigFireball': 1.05}
STATUS_SFX = {'Poisoned': 'Status Poisoned', 'Toxic': 'Status Poisoned', 'Burned': 'Status Burned', 'Paralyzed': 'Status Paralyzed',
              'Asleep': 'Status Sleep', 'Confused': 'Status Confused'}
SOUNDS = {'hit': 'Hit Normal Damage', 'hit_weak': 'Hit Super Effective', 'hit_resist': 'Hit Weak Not Very Effective',
          'bench': 'Hit Normal Damage', 'stat_up': 'Stat Rise Up', 'stat_down': 'Stat Fall Down'}
SFX_MANIFEST = os.path.join(OUT_DIR, 'sfx_manifest.json')


def _norm(s):
    return re.sub(r'[^a-z0-9]', '', s.lower())


def sfx_clips():
    if not os.path.exists(SFX_MANIFEST):
        return {}
    with open(SFX_MANIFEST, encoding='utf-8') as fh:
        return json.load(fh)


def sfx_resolve(name, clips):
    """A move name -> the clip to use: the move itself, or its single-hit / two-hit take."""
    for cand in (name, name + ' 1hit', name + ' 2hits'):
        if cand in clips:
            return cand
    idx = {_norm(k): k for k in clips}
    for cand in (name, name + ' 1hit'):
        if _norm(cand) in idx:
            return idx[_norm(cand)]
    return None


def apply_sfx(mapping, clips):
    if not clips:
        print('NOTE: no sfx_manifest.json -- run attack_sfx_import.py first; building without sound.')
        return
    missing = []
    spaced = lambda rid: re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', rid)
    for rid, r in RECIPES.items():
        clip = sfx_resolve(SFX_OF[rid], clips) if rid in SFX_OF else (sfx_resolve(rid, clips) or sfx_resolve(spaced(rid), clips))
        if clip is None:
            missing.append(rid)
            continue
        r['sfx'] = clip
        if rid in SFX_PITCH:
            r['sfx_pitch'] = SFX_PITCH[rid]
        for s in r['steps']:
            if s.get('fx') == 'StatUp':
                s['sfx'] = SOUNDS['stat_up']
            elif s.get('fx') == 'StatDown':
                s['sfx'] = SOUNDS['stat_down']
    for k, clip in STATUS_SFX.items():
        STATUS[k]['sfx'] = clip
    for name, m in mapping.items():
        clip = sfx_resolve(name, clips)
        if clip:
            m['sfx'] = clip
    for v in list(STATUS_SFX.values()) + list(SOUNDS.values()):
        if v not in clips:
            missing.append('(sound) ' + v)
    if missing:
        print('NO SOUND FOR:', ', '.join(missing))
        raise SystemExit(1)


def _words(s):
    return s.split()


def apply_pass2():
    elem_lookup = {}
    for el, ids in ELEMENT_OF.items():
        for rid in _words(ids):
            elem_lookup[rid] = el.strip()
    elem_lookup['Hidden Power'] = 'psychic'
    for rid, r in RECIPES.items():
        el = elem_lookup.get(rid)
        if el is None:
            for pat, e in ELEMENT_GUESS:
                if re.search(pat, rid):
                    el = e
                    break
        r['element'] = el or 'normal'
    for body, ids in BODY_OF.items():
        for rid in _words(ids):
            if rid in RECIPES:
                RECIPES[rid]['body'] = body
    for react, ids in REACT_OF.items():
        for rid in _words(ids):
            if rid in RECIPES:
                RECIPES[rid]['react'] = react
    for n, ids in HITS_OF.items():
        for rid in _words(ids):
            if rid in RECIPES:
                RECIPES[rid]['hits'] = n
                RECIPES[rid]['react'] = 'multi'
    for rid in _words(HEAVY):
        if rid in RECIPES:
            RECIPES[rid]['power'] = 'heavy'
    for rid in _words(RECOIL):
        if rid in RECIPES:
            RECIPES[rid]['recoil'] = True
    for rid, sc in SCREEN_OF.items():
        if rid in RECIPES:
            RECIPES[rid]['screen'] = sc
    # Bench splashes are no longer part of the main animation: they play per damaged benched card.
    for rid, r in RECIPES.items():
        bench_steps = [s for s in r['steps'] if s.get('at') == 'bench']
        if bench_steps:
            r['steps'] = [s for s in r['steps'] if s.get('at') != 'bench']
            b = dict(bench_steps[0])
            b['at'] = 'target'
            for k in ('par', 'delay'):
                b.pop(k, None)
            r['bench_fx'] = b
    for rid, step in BENCH_FX.items():
        if rid.strip() in RECIPES:
            RECIPES[rid.strip()]['bench_fx'] = step


# ---------------- STATUS overlays: played by Card_FX when a condition actually lands ----------------
STATUS = {
    'Poisoned':  rec(N, T('PoisonBubbles', size=0.35, count=3, stagger=0.12, jitter=0.25), T('QuickPoisonHit', size=0.9, par=True, delay=0.1)),
    'Toxic':     rec(N, T('PoisonColumn', size=0.7), T('ToxicSpike', size=0.8, count=2, stagger=0.12, jitter=0.2, par=True), T('QuickPoisonHit', size=0.9, par=True)),
    'Burned':    rec(N, T('Embers', size=1.0), T('MiniCombustion', size=0.35, count=3, stagger=0.12, jitter=0.25, par=True)),
    'Paralyzed': rec(N, T('Electrocute', size=1.0), T('SparkScatter', size=0.9, par=True)),
    'Asleep':    rec(N, T('Nightmare', size=0.45, off=[0.25, -0.3], mirror=False, tint='#c0d8ff')),
    'Confused':  rec(N, T('ConfusingHit', size=0.9, off=[0, -0.25], range=[0, 8])),
}
for _k, _el in [('Poisoned', 'poison'), ('Toxic', 'poison'), ('Burned', 'fire'), ('Paralyzed', 'electric'), ('Asleep', 'normal'), ('Confused', 'psychic')]:
    STATUS[_k]['element'] = _el

# ---------------- FALLBACKS: type -> [cost 0-1, cost 2, cost 3+] ----------------
FALLBACK = {
    'Fire':      {'spec': ['Ember', 'Fireball', 'FireBlast'],       'phys': ['FireTail', 'FirePunch', 'BlazeKick']},
    'Water':     {'spec': ['Bubble', 'WaterGun', 'HydroPump'],      'phys': ['SplashHit', 'WaterSlash', 'Waterfall']},
    'Lightning': {'spec': ['Spark', 'ThunderShock', 'Thunder'],     'phys': ['ElectricTackle', 'ThunderPunch', 'ThunderFang']},
    'Grass':     {'spec': ['VineWhip', 'RazorLeaf', 'EnergyBall'],  'phys': ['VineWhip', 'LeafBlade', 'LeafBlade']},
    'Psychic':   {'spec': ['Confusion', 'Psybeam', 'PsychicBlast'], 'phys': ['PsyPalm', 'Psypunch', 'Psypunch']},
    'Fighting':  {'spec': ['RockThrow', 'RockSlide', 'StoneEdge'],  'phys': ['Punch', 'MegaPunch', 'DynamicPunch']},
    'Darkness':  {'spec': ['DarkWave', 'ShadowBall', 'DarkPulse'],  'phys': ['Bite', 'DarkSlash', 'FeintAttack']},
    'Metal':     {'spec': ['MetalBall', 'SteelOrb', 'MetalSound'],  'phys': ['MetalClaw', 'IronTail', 'SteelPunch']},
    'Colorless': {'spec': ['Swift', 'GenericBeam', 'HyperBeam'],    'phys': ['Tackle', 'PowerfulHit', 'TakeDown']},
    'Dragon':    {'spec': ['Dragonbreath', 'DragonRage', 'RoarOfTime'], 'phys': ['DragonClaw', 'DragonClaw', 'Outrage']},
}
# Non-damaging attacks with nothing more specific: what kind of thing the text does.
UTILITY = {
    'inflict': 'Misc', 'self': 'PowerUp', 'counters': 'CurseCounters', 'other': 'Glitter',
}

# ========================================================================================
# ATTACK -> RECIPE
# ========================================================================================
# 1) EXACT: names pinned by hand (checked first; case-insensitive).
EXACT = {
    # --- the obvious ones: game moves under their own name ---
    'Absorb': 'Absorb', 'Mega Drain': 'MegaDrain', 'Leech Seed': 'LeechSeed', 'Leech Life': 'LeechLife',
    'Acid': 'Acid', 'Agility': 'Agility', 'Air Cutter': 'AirCutter', 'Air Slash': 'AirSlash', 'Amnesia': 'Amnesia',
    'Attract': 'Attract', 'Aurora Beam': 'AuroraBeam', 'Barrage': 'Barrage', 'Beat Up': 'BeatUp', 'Bind': 'Bind',
    'Bite': 'Bite', 'Blaze Kick': 'BlazeKick', 'Blizzard': 'Blizzard', 'Body Slam': 'BodySlam', 'Bonemerang': 'Bonemerang',
    'Bone Rush': 'BoneRush', 'Bone Attack': 'BoneClub', 'Bubble': 'Bubble', 'Bubblebeam': 'Bubblebeam', 'Charge': 'Charge',
    'Charm': 'Charm', 'Clamp': 'Clamp', 'Comet Punch': 'CometPunch', 'Confuse Ray': 'ConfuseRay', 'Constrict': 'Constrict',
    'Conversion 1': 'Conversion', 'Conversion 2': 'Conversion', 'Cotton Spore': 'CottonSpore', 'Crabhammer': 'Crabhammer',
    'Cross Chop': 'CrossChop', 'Crunch': 'Crunch', 'Defense Curl': 'Harden', 'Destiny Bond': 'DestinyBond', 'Detect': 'Detect',
    'Dig': 'Dig', 'Discharge': 'Discharge', 'Double Kick': 'DoubleKick', 'Doubleslap': 'DoubleSlap', 'Doublslap': 'DoubleSlap',
    'Double-edge': 'TakeDown', 'Dragon Rage': 'DragonRage', 'Dragonbreath': 'Dragonbreath', 'Dragon Claw': 'DragonClaw',
    'Dragon Dance': 'DragonDance', 'Dream Eater': 'DreamEater', 'Drill Peck': 'DrillPeck', 'Earthquake': 'Earthquake',
    'Egg Bomb': 'EggBomb', 'Ember': 'Ember', 'Endure': 'Endure', 'Energy Ball': 'EnergyBall', 'Eruption': 'Eruption',
    'Explosion': 'Explosion', 'Fake Out': 'QuickAttack', 'False Swipe': 'Slash', 'Feint Attack': 'FeintAttack',
    'Fire Blast': 'FireBlast', 'Fireblast': 'FireBlast', 'Fire Punch': 'FirePunch', 'Fire Spin': 'FireSpin',
    'Fissure': 'Fissure', 'Flail': 'Thrash', 'Flame Wheel': 'FlameWheel', 'Flamethrower': 'Flamethrower', 'Flare': 'Flare',
    'Fly': 'Fly', 'Foresight': 'Foresight', 'Fury Attack': 'FuryAttack', 'Fury Cutter': 'FurySwipes', 'Fury Swipes': 'FurySwipes',
    'Glare': 'Glare', 'Growl': 'Growl', 'Growth': 'Growth', 'Guillotine': 'Guillotine', 'Gust': 'Gust', 'Harden': 'Harden',
    'Headbutt': 'Headbutt', 'Hidden Power': 'Hidden Power', 'High Jump Kick': 'MegaKick', 'Horn Attack': 'HornAttack',
    'Horn Drill': 'HornDrill', 'Hurricane': 'Hurricane', 'Hydro Pump': 'HydroPump', 'Hyper Beam': 'HyperBeam',
    'Hyper Fang': 'HyperFang', 'Hyper Voice': 'HyperVoice', 'Hypnosis': 'Hypnosis', 'Ice Beam': 'IceBeam', 'Ice Punch': 'IcePunch',
    'Icy Wind': 'IcyWind', 'Iron Defense': 'IronDefense', 'Iron Tail': 'IronTail', 'Karate Chop': 'KarateChop', 'Lick': 'Lick',
    'Leaf Blade': 'LeafBlade', 'Light Screen': 'Barrier', 'Lock-on': 'LockOn', 'Lullaby': 'Sing', 'Magnitude': 'Magnitude',
    'Mean Look': 'MeanLook', 'Meditate': 'Meditate', 'Mega Kick': 'MegaKick', 'Mega Punch': 'MegaPunch', 'Megahorn': 'Megahorn',
    'Metal Claw': 'MetalClaw', 'Metal Sound': 'MetalSound', 'Metronome': 'Metronome', 'Mini-Metronome': 'Metronome',
    'Super Metronome': 'Metronome', 'Milk Drink': 'MilkDrink', 'Minimize': 'Minimize', 'Mirror Move': 'Copy', 'Mud Slap': 'MudSlap',
    'Mud Shot': 'MudSlap', 'Night Ambush': 'ShadowSneak', 'Nightmare': 'Nightmare', 'Octazooka': 'Octazooka', 'Pay Day': 'PayDay',
    'Peck': 'Peck', 'Perish Song': 'PerishSong', 'Petal Dance': 'PetalDance', 'Pin Missile': 'PinMissile', 'Poison Fang': 'PoisonFang',
    'Poison Gas': 'PoisonGas', 'Poison Sting': 'PoisonSting', 'Poisonpowder': 'PoisonPowder', 'Pound': 'Pound', 'Powder Snow': 'PowderSnow',
    'Present': 'Present', 'Psybeam': 'Psybeam', 'Psychic': 'Psychic', 'Psyshock': 'Psyshock', 'Psywave': 'Psywave', 'Pursuit': 'Pursuit',
    'Quick Attack': 'QuickAttack', 'Rage': 'Thrash', 'Rapid Spin': 'Spin', 'Razor Leaf': 'RazorLeaf', 'Razor Wind': 'RazorWind',
    'Recover': 'Recover', 'Rest': 'Rest', 'Roar': 'Roar', 'Rock Blast': 'RockBlast', 'Rock Slide': 'RockSlide', 'Rock Smash': 'RockSmash',
    'Rock Throw': 'RockThrow', 'Rollout': 'Rollout', 'Sacred Fire': 'SacredFire', 'Sand Attack': 'SandAttack', 'Sand-attack': 'SandAttack',
    'Sandstorm': 'Sandstorm', 'Scary Face': 'ScaryFace', 'Scratch': 'Scratch', 'Screech': 'Screech', 'Seismic Toss': 'SeismicToss',
    'Selfdestruct': 'Selfdestruct', 'Sheer Cold': 'SheerCold', 'Signal Beam': 'SignalBeam', 'Silver Wind': 'SilverWind', 'Sing': 'Sing',
    'Skull Bash': 'Headbutt', 'Slam': 'BodySlam', 'Slash': 'Slash', 'Sleep Powder': 'SleepPowder', 'Smog': 'Smog', 'Smokescreen': 'Smokescreen',
    'Sonicboom': 'Sonicboom', 'Spark': 'Spark', 'Spike Cannon': 'PinMissile', 'Spore': 'Spore', 'Stomp': 'Stomp', 'String Shot': 'StringShot',
    'Stun Spore': 'StunSpore', 'Submission': 'Submission', 'Super Fang': 'HyperFang', 'Supersonic': 'Supersonic', 'Surf': 'Surf',
    'Swagger': 'Swagger', 'Sweet Kiss': 'SweetKiss', 'Swift': 'Swift', 'Swords Dance': 'SwordsDance', 'Tackle': 'Tackle',
    'Tail Whip': 'TailWhip', 'Take Down': 'TakeDown', 'Taunt': 'Taunt', 'Teleport': 'Teleport', 'Thrash': 'Thrash', 'Thunder': 'Thunder',
    'Thunder Wave': 'ThunderWave', 'Thunderbolt': 'Thunderbolt', 'Thunderpunch': 'ThunderPunch', 'Thundershock': 'ThunderShock',
    'Toxic': 'Toxic', 'Tri Attack': 'TriAttack', 'Twineedle': 'Twineedle', 'Twister': 'Twister', 'Vine Whip': 'VineWhip',
    'Water Gun': 'WaterGun', 'Waterfall': 'Waterfall', 'Whirlpool': 'Whirlpool', 'Whirlwind': 'Whirlwind', 'Will-o\'-the-wisp': 'WillOWisp',
    'Call Will-o\'-the-wisp': 'WillOWisp', 'Wing Attack': 'WingAttack', 'Withdraw': 'Withdraw', 'Wrap': 'Wrap', 'Zap Kick': 'Kick',
    'Low Kick': 'Kick', 'Rolling Kick': 'MegaKick', 'Hydrocannon': 'HydroPump', 'Bubble Bomb': 'Bubblebeam', 'Spark ': 'Spark',
    'Solarbeam': 'Solarbeam', 'Wide Solarbeam': 'Solarbeam', 'Ancestral Memory': 'AncientPower', 'Ancient Mantra': 'AncientPower',
    'Psychic Boom': 'PsychicBlast', 'Mist Ball': 'PsychicBall', 'Luster Purge': 'PsychicBlast', 'Aeroblast': 'Hurricane',
    'Gigashock': 'Gigashock', 'Gigavolt': 'Thunder', 'Mega Shock': 'Thunderbolt', 'Chain Lightning': 'ChainLightning',
    'Lightning Bolt': 'Thunderbolt', 'Lightning Strike': 'Thunder', 'Raging Thunder': 'Thunder', 'Thunderstorm': 'Gigashock',
    'Thundersquall': 'Gigashock', 'Pika Ball': 'LightningBall', 'Pika Bolt': 'Thunderbolt', 'Zzzap': 'Discharge', 'Kerzap': 'Spark',
    'Electric Shock': 'ThunderShock', 'Shock Bolt': 'Thunderbolt', 'Thunder Jolt': 'ThunderShock', 'Electro Beam': 'ZapCannon',
    'Electric Blast': 'ZapCannon', 'Thunder Blast': 'ZapCannon', 'Mega Thunderbolt': 'Thunder', 'Miraculous Thunder': 'Thunder',
    'Lightning Ball': 'LightningBall', 'Lightning Sphere': 'ElectroBall', 'Static Electricity': 'Charge', 'Recharge': 'ReverseCharge',
    'Self Charge': 'Charge', 'Charge Up': 'Charge', 'Quick Charge': 'Charge', 'Continuous Charge': 'Charge', 'Power Generation': 'Charge',
    'Magnetic Bomb': 'MagnetBomb', 'Magnetic Blast': 'MagnetBomb', 'Magnetic Force': 'Magnet', 'Magnetic Pull': 'Magnet',
    'Magnetic Wave': 'Magnet', 'Magnetic Lines': 'Magnet', 'Magnetism': 'Magnet', 'Magnetic Swirl': 'Magnet', 'Magnetic Trip': 'Magnet',
    'Magnetic Tackle': 'ElectricTackle', 'Body Bolt': 'ElectricTackle', 'Thundertackle': 'ElectricTackle', 'Lightning Tackle': 'ElectricTackle',
    'Electric Tackle': 'ElectricTackle', 'Electric Punch': 'ThunderPunch', 'Thunderous Blow': 'ThunderPunch',
    'Psypunch': 'Psypunch', 'Psyimpact': 'PsychicBlast', 'Psyburn': 'PsychicBlast', 'Psyburst': 'PsychicBlast', 'Psystorm': 'PsychicBlast',
    'Psyshot': 'Psybeam', 'Psysplash': 'Psywave', 'Psymist': 'PsychicLights', 'Psycho Waves': 'Psywave', 'Super Psy': 'PsychicBlast',
    'Super Psy Bolt': 'PsychicBlast', 'Super Psywave': 'Psywave', 'Psy Confuse': 'Confusion', 'Psykiss': 'SweetKiss', 'Psyscan': 'MindReader',
    'Psyloop': 'Psywave', 'Psyche': 'Psychic', 'ESP': 'MindShock', 'Random ESP': 'MindShock', 'Mind Shock': 'MindShock',
    'Mind Blast': 'PsychicBlast', 'Mind Bend': 'Hypnosis', 'Mind Trip': 'Hypnosis', 'Mind Play': 'MindShock', 'Third Eye': 'MindReader',
    'The Third Eye': 'MindReader', 'Telekinesis': 'Telekinesis', 'Synchronize': 'MindReader', 'Calm Mind': 'Meditate',
    'Hypnoblast': 'Hypnosis', 'Super Hypnoblast': 'Hypnosis', 'Hypnotic Gaze': 'Glare', 'Hypnotic Stare': 'Glare', 'Hypnotic Ray': 'Psybeam',
    'Hypno Wave': 'Hypnosis', 'Super Hypno Wave': 'Hypnosis', 'Hypnosplash': 'Hypnosis', 'Hypno Splash': 'Hypnosis', 'Hypnoshower': 'Hypnosis',
    'Sleep Inducer': 'Hypnosis', 'Shadow Ball': 'ShadowBall', 'Haunt': 'Haunt', 'Poltergeist': 'Haunt', 'Spook': 'Haunt',
    'Grudge': 'Spite', 'Gift of Spite': 'Spite', 'Cursed Reaction': 'Curse', 'Pendulum Curse': 'Curse', 'Clay Curse': 'Curse',
    'Random Curse': 'CurseCounters', 'Damage Curse': 'CurseCounters', 'Extra Curse': 'CurseCounters', 'Pain Split': 'PainSplit',
    'Pain Amplifier': 'CurseCounters', 'Bad Dream': 'Nightmare', 'Night Murmurs': 'Whisper', 'Night Song': 'DarkSing',
    'Night Spirits': 'Haunt', 'Night Attack': 'FeintAttack', 'Night Eyes': 'MeanLook', 'Evil Eye': 'MeanLook', 'Black Magic': 'DarkMind',
    'Dark Mind': 'DarkMind', 'Darkness Blast': 'DarkBlast', 'Dark Wave': 'DarkWave', 'Dark Slash': 'DarkSlash', 'Dark Swirl': 'DarkPulse',
    'Dark Flame': 'DarkFlame', 'Dark Fire': 'DarkFlame', 'Dark Burst': 'DarkBlast', 'Dark Impact': 'DarkBlast', 'Shadow Beam': 'DarkPulse',
    'Shadow Attack': 'FeintAttack', 'Shadow Hand': 'ShadowPunch', 'Shadow Crush': 'DarknessEngulf', 'Shadow Bind': 'MeanLook',
    'Shadow Tag': 'MeanLook', 'Shadow Images': 'Substitute', 'Hide in Shadows': 'SmokeEscape', 'Shadow Steal': 'FeintAttack',
    'Shadow Chant': 'DarkSing', 'Ambush': 'FeintAttack', 'Blindside': 'FeintAttack', 'Surprise Attack': 'FeintAttack',
    'Darkness Fang': 'HyperFang', 'Black Fang': 'Crunch', 'Lonely Fang': 'Crunch', 'Mystic Fang': 'Crunch', 'Sharp Fang': 'Bite',
    'Sharp Teeth': 'Bite', 'Big Bite': 'Crunch', 'Continuous Bite': 'Crunch', 'Second Bite': 'Bite', 'Bite Off': 'Crunch', 'Chomp': 'Crunch',
    'Gnaw': 'Bite', 'Tail Bite': 'Bite', 'Poison Bite': 'PoisonFang', 'Burning Fang': 'FireFang', 'Rending Jaws': 'Crunch',
    'Clamping Jaw': 'Crunch', 'Jaw Clamp': 'Crunch', 'Tight Jaw': 'Crunch', 'Delta Fang': 'Crunch',
    'Scary Face ': 'ScaryFace', 'Leer': 'MeanLook', 'Stare': 'MeanLook', 'Intense Glare': 'Glare', 'Paralyzing Gaze': 'Glare',
    'Threaten': 'ScaryFace', 'Intimidate': 'ScaryFace', 'Terrorize': 'ScaryFace', 'Snarl': 'Growl', 'Bellow': 'Roar',
    'Destructive Roar': 'Roar', 'Thunderous Roar': 'Roar', 'Dragon Roar': 'Roar', 'Eerie Howl': 'Roar', 'Black Cry': 'Roar',
    'Wail': 'Cry', 'Bawl': 'Cry', 'Snivel': 'Cry', 'Teary Eyes': 'Cry', 'Rainy Day Blues': 'Cry', 'Eek': 'Panic', 'Eeeeeeek': 'Panic',
    'Fidget': 'Sweat', 'Spacing Out': 'Question', 'Disorder': 'Question', 'Mislead': 'Question', 'Scam': 'Question', 'Deceive': 'Question',
    'Alert': 'Detect', 'Cheer On': 'Cheer', 'Cheer Up': 'Cheer', 'Let\'s Play!': 'Cheer', 'Fairy Power': 'Wish', 'Make a Wish': 'Wish',
    'Miracle': 'Wish', 'Anger': 'Anger', 'Seething Anger': 'Anger', 'Tantrum': 'Thrash', 'Rampage': 'Thrash', 'Outrage': 'Outrage',
    'Violent Rage': 'Outrage', 'Mega Thrash': 'Thrash', 'Frenzied Attack': 'Thrash', 'Battle Frenzy': 'Thrash',
    'Sweet Scent': 'Charm', 'Alluring Smile': 'Charm', 'Alluring Kiss': 'SweetKiss', 'Blown Kiss': 'SweetKiss', 'Energy Kiss': 'SweetKiss',
    'Paralyzing Kiss': 'EvilKiss', 'Freezing Kiss Goodnight': 'SweetKiss', 'Fascinate': 'Attract', 'Tempt': 'Attract',
    'Tempting Eyes': 'Attract', 'Sweet Temptation': 'Attract', 'Lure': 'FollowMe', 'Luring Antenna': 'FollowMe', 'Luring Flame': 'WillOWisp',
    'Call for Family': 'CallForFamily', 'Call for Friend': 'CallForFamily', 'Call for Friends': 'CallForFamily', 'Call Back': 'CallForFamily',
    'Cry for Help': 'Cry', 'Look for Friends': 'Search', 'Friend Search': 'Search', 'Seek Out': 'Search', 'Sniff Out': 'Search',
    'Scout': 'Foresight', 'Spy': 'Foresight', 'Searchlight': 'Foresight', 'Floodlight': 'Spotlight', 'Collect': 'Draw',
    'Pickup': 'Pickup', 'Fetch': 'Pickup', 'Pickup Power': 'Pickup', 'Scavenge': 'Pickup', 'Hoard': 'Pickup',
    'Sing ': 'Sing', 'Good Night Song': 'Sing', 'Sleepy Song': 'Sing', 'Gentle Song': 'Sing', 'Dragon Song': 'Sing', 'Set Song': 'Sing',
    'Dark Song': 'DarkSing', 'Dirge': 'DarkSing', 'Evolution Song': 'HealingSong', 'Healing Sound': 'HealingSong',
    'Sound Waves': 'HyperVoice', 'Sonic Noise': 'Screech', 'Sonic Scream': 'HyperVoice', 'Screechy Voice': 'Screech', 'Deafen': 'Screech',
    'Chaotic Noise': 'Screech', 'Cracking Voice': 'HyperVoice', 'Breaking Sound': 'MetalSound', 'Poison Sound Wave': 'Supersonic',
    'Sonic Distortion': 'Supersonic', 'Sonic Signal': 'Supersonic', 'Warp Sounds': 'Supersonic', 'Strange Rasping': 'Screech',
    'Uproar': 'HyperVoice', 'Chime': 'ChantingBell', 'Resonate': 'MetalSound', 'Bass Control': 'HyperVoice',
    'Teleport Blast': 'TeleportBeam', 'Teleportation Burst': 'TeleportBeam', 'Warp Hole': 'Teleport', 'Vanish': 'Teleport',
    'Fade Out': 'Teleport', 'Return Home': 'Teleport', 'Skedaddle': 'SmokeEscape', 'Punch and Run': 'Punch', 'Strike and Run': 'QuickAttack',
    'Snatch and Run': 'QuickAttack', 'Hit and run': 'QuickAttack', 'Baton Pass': 'Switch', 'Quick Turn': 'QuickAttack', 'Swift Turn': 'QuickAttack',
    'Tripping Turn': 'Tackle', 'Lightning Turn': 'ElectricTackle', 'Burning Turn': 'FlameWheel', 'Splashing Turn': 'SplashHit',
    'Smash Turn': 'BodySlam', 'Sting Turn': 'Sting', 'Detour': 'Switch',
    'Copy': 'Copy', 'Skill Copy': 'Copy', 'Delta Copy': 'Copy', 'Mimicry': 'Copy', 'Sketch': 'Copy', 'Mirror Shell': 'MirrorShot',
    'Counter': 'Counter', 'Crosscounter': 'Counter', 'Retaliate': 'Counter', 'Retaliation': 'Counter', 'Full Retaliation': 'Counter',
    'Return Attack': 'Counter', 'Get Even': 'Counter', 'Revenge': 'Counter', 'Power Revenge': 'Counter', 'Reflect Energy': 'MirrorShot',
    'Reflect Shield': 'Protect', 'Reflected Beam': 'MirrorShot', 'Reflected Sunlight': 'Solarbeam', 'Thunder Reflection': 'Thunderbolt',
    'Barrier': 'Barrier', 'Barrier Attack': 'Barrier', 'Psychic Shield': 'Barrier', 'Pulse Guard': 'Barrier', 'Protective Wave': 'Barrier',
    'Protective Swirl': 'Barrier', 'Darkness Shield': 'Protect', 'Ice Barrier': 'Freeze', 'Pollen Shield': 'Protect', 'Flame Screen': 'FireWall',
    'Fire Wall': 'FireWall', 'Deflector': 'Protect', 'Shield Beam': 'Barrier', 'Advanced Armor': 'IronDefense', 'Armor Up': 'IronDefense',
    'Stiffen': 'Harden', 'Hide in Shell': 'Withdraw', 'Shell Attack': 'Withdraw', 'Spiky Shell': 'Withdraw', 'Hide': 'SmokeEscape',
    'Dodge': 'Agility', 'Super Speed': 'Agility', 'Lie Low': 'Withdraw', 'Play Dead': 'Sweat', 'Float': 'Agility',
    'Twiddle': 'Question', 'Wiggle': 'TailWhip', 'Tail Shake': 'TailWhip', 'Tail Wag': 'TailWhip', 'Tail Fan': 'TailWhip',
    'Belly Drum': 'PowerUp', 'Focus Energy': 'Focus', 'Bulk Up': 'PowerUp', 'Warm Up': 'PowerUp', 'Pure Power': 'PowerUpLights',
    'Stockpile': 'PowerUpRings', 'Sharpen': 'SwordsDance', 'Expand': 'PowerUp', 'Giant Growth': 'Growth', 'Growth Spurt': 'Growth',
    'Sudden Growth': 'Growth', 'Speed Growth': 'Growth', 'Spiral Growth': 'Growth', 'Sprout': 'Growth', 'Fruition': 'Growth',
    'Full Bloom': 'Growth', 'Ingrain': 'Ingrain', 'Photosynthesis': 'Photosynthesis', 'Sunbathe': 'Photosynthesis', 'Sunshine': 'SunnyDay',
    'Forecast': 'SunnyDay', 'Summon Storm': 'Rain', 'Drizzle': 'Rain', 'Rain Splash': 'Rain', 'Scattered Shower': 'Rain',
    'Energy Shower': 'Rain', 'Hailstone': 'Hail', 'Flurries': 'PowderSnow', 'White Snow': 'PowderSnow', 'Diamond Dust': 'PowderSnow',
    'Ice Throw': 'IceShard', 'Iceberg Crush': 'Icicle', 'Ice Pillar': 'Icicle', 'Crushing Ice': 'Icicle', 'Avalanche': 'Avalanche',
    'Freeze': 'Freeze', 'Freeze Dry': 'Freeze', 'Freeze Solid': 'Freeze', 'Freeze Lock': 'Freeze', 'Freeze Light': 'AuroraBeam',
    'Freezing Breath': 'IcyWind', 'Ice Breath': 'IcyWind', 'Cold Breath': 'IcyWind', 'Super Icy Wind': 'IcyWind', 'Generate Cold': 'Freeze',
    'Ice Generator': 'Freeze', 'Frostbite': 'IceFang', 'Freezing Wing': 'IceWing', 'Ice Wing': 'IceWing', 'Star Freeze': 'IceBeam',
    'Final Blizzard': 'Blizzard', 'Heavy Blizzard': 'Blizzard', 'Holon Blizzard': 'Blizzard', 'Ice Cyclone': 'Blizzard',
    'Freezing Force': 'SheerCold', 'Cold Crush': 'Icicle', 'Ice Gift': 'PowderSnow',
    'Will-o\'-the-wisp ': 'WillOWisp', 'Ethereal Flame': 'WillOWisp', 'White Flames': 'BlueFlame', 'Holy Flame': 'SacredFire',
    'Phoenix Flame': 'SacredFire', 'Bright Flame': 'SacredFire', 'Guiding Flame': 'WillOWisp', 'Protective Flame': 'FireWall',
    'Flame Pillar': 'FlamePillar', 'Flame Jet': 'FlamePillar', 'Fire Stream': 'Flamethrower', 'Steady Firebreathing': 'Flamethrower',
    'Firebreathing': 'Flamethrower', 'Fire Force': 'FireBlast', 'Hyper Flame': 'FireBlast', 'Mega Flame': 'FireBlast',
    'Destructive Fire': 'Inferno', 'Bursting Inferno': 'Inferno', 'Firestorm': 'FireSpin', 'Flame Swirl': 'FireSpin', 'Fire Dance': 'FireSpin',
    'Ring of Fire': 'FireSpin', 'Fire Ring': 'FireSpin', 'Flames of Rage': 'Inferno', 'Roaring Flames': 'Inferno', 'Wildfire': 'Inferno',
    'Fire Mane': 'FireBurst', 'Flame Burst': 'FireBurst', 'Burst': 'GreenHit', 'Combustion': 'Combustion', 'Detonate': 'Selfdestruct',
    'Detonation': 'Selfdestruct', 'Spontaneous Explosion': 'Selfdestruct', 'Big Explosion': 'Explosion', 'Mass Explosion': 'Explosion',
    'Mass Destruction': 'Explosion', 'Final Blast': 'Explosion', 'Big Eggsplosion': 'EggBomb', 'Eggsplosion': 'EggBomb',
    'Super Eggsplosion': 'EggBomb', 'Continuous Eggsplosion': 'EggBomb', 'Lateral Eggsplosion': 'EggBomb', 'Egg Toss': 'EggBomb',
    'Egg Surprise': 'EggBomb', 'Scatterbomb': 'Barrage', 'Split Bomb': 'Barrage', 'Smash Bomber': 'Barrage', 'Fireworks': 'MiniExplosions',
    'Pop': 'SmallBomb', 'Misfire': 'SmallBomb', 'Lava Burst': 'Magma', 'Lava Burn': 'Magma', 'Lava Flow': 'Magma', 'Scorching Lava': 'Magma',
    'Rushing Magma': 'Magma', 'Magma Spurt': 'Magma', 'Magma Burn': 'Magma', 'Magma Ring': 'FireSpin', 'Melting Mountain': 'Eruption',
    'Crushing Lava': 'Magma', 'Crushing Magma': 'Magma', 'Crushing Mantle': 'Eruption', 'Volcanic Ash': 'HotRocks', 'Volcanic Flame': 'Eruption',
    'Fire Claws': 'FireClaw', 'Burning Claw': 'FireClaw', 'Fire Tail': 'FireTail', 'Flame Tail': 'FireTail', 'Burning Tail': 'FireTail',
    'Fire Tail Slap': 'FireTail', 'Fire Wing': 'FireTail', 'Flaming Punch': 'FirePunch', 'Magma Punch': 'FirePunch', 'Fire Blow': 'FirePunch',
    'Magma Jab': 'FirePunch', 'Fire Tackle': 'FlameWheel', 'Heat Tackle': 'FlameWheel', 'Rushing Flames': 'FlameWheel', 'Burning Ball': 'Fireball',
    'Ball of Flame': 'Fireball', 'Flame Ball': 'Fireball', 'Fireball': 'Fireball', 'Continuous Fireball': 'Fireball', 'Heat Blast': 'BigFireball',
    'Thermal Blast': 'BigFireball', 'Sunburn': 'Sunburn', 'Scorching Light': 'Sunburn', 'Heat Wave': 'HeatWave', 'Hot Air': 'HeatWave',
    'Scalding Steam': 'Steam', 'Steam Blast': 'Steam', 'Scorching Smoke': 'Steam', 'Scorching Whirlwind': 'HeatWave', 'Fire Wind': 'HeatWave',
    'Roasting Heat': 'HeatWave', 'Gentle Flames': 'Ember', 'Kindle': 'Ember', 'Ignite': 'Ember', 'Singe': 'Ember', 'Super Singe': 'Flare',
    'Char': 'Flare', 'Stoke': 'Flare', 'Bonfire': 'FireSpin', 'Flickering Flames': 'Ember', 'Flickering Tail': 'FireTail', 'Collect Fire': 'Charge',
    'Playing with Fire': 'Flare', 'Fire Payback': 'FireBurst', 'Back Burner': 'FireBurst', 'Searing Flame': 'Flamethrower',
    'Searing Flames': 'Flamethrower', 'Burning Flame': 'Flamethrower', 'Burning Fire': 'Flamethrower', 'White-hot Flame': 'SacredFire',
    'Incinerate': 'Inferno', 'Crush and Burn': 'Inferno', 'Burn Down': 'Inferno', 'Burn Off': 'Flare', 'Burn Up': 'Inferno', 'Blaze': 'FireBlast',
    'Flame': 'Ember', 'Flame Gift': 'Charge', 'Extra Flame': 'FireBlast', 'Dragon Flame': 'Dragonbreath', 'Fire Payback ': 'FireBurst',
    'Dual Burn': 'FireBlast', 'Multi Burn': 'FireBlast', 'Rainbow Burn': 'FireBlast', 'Mega Burn': 'FireBlast', 'Back Burner ': 'FireBurst',
    'Water Arrow': 'WaterGun', 'Water Bullet': 'WaterGun', 'Water Cannon': 'HydroPump', 'Hydro Shot': 'WaterGun', 'Squirt': 'WaterGun',
    'Water Spray': 'WaterGun', 'Hyper Pump': 'HydroPump', 'Ultra Pump': 'HydroPump', 'Pump Out': 'HydroPump', 'Double Cannon': 'HydroPump',
    'Triple Cannon': 'HydroPump', 'Hydro Splash': 'Splash', 'Hydrosplash': 'Splash', 'Splash': 'Splash', 'Hyper Splash': 'Surf',
    'Holon Splash': 'Splash', 'Energy Splash': 'Splash', 'Rapids': 'Surf', 'Tsunami': 'TidalWave', 'Super Tidal Wave': 'TidalWave',
    'Tidal Wave': 'TidalWave', 'Giant Wave': 'TidalWave', 'Major Flood': 'TidalWave', 'Hydro Wave': 'Surf', 'Wave Splash': 'Surf',
    'Crushing Wave': 'TidalWave', 'Aqua Wave': 'Surf', 'Do the Wave': 'Surf', 'Riptide': 'Whirlpool', 'Hyper Whirlpool': 'Whirlpool',
    'Strong Current': 'Whirlpool', 'Reverse Stream': 'Whirlpool', 'Upstream': 'Whirlpool', 'Sludge Whirlpool': 'Whirlpool',
    'Aqua Ring': 'AquaRing', 'Water Ring': 'AquaRing', 'Healing Water': 'AquaRing', 'Mystic Water': 'AquaRing', 'Aqua Flower': 'AquaRing',
    'Ink Blast': 'Octazooka', 'Ink Spurt': 'Octazooka', 'Bubble Shower': 'Bubblebeam', 'Bubbles': 'Bubble', 'Max Bubbles': 'Bubblebeam',
    'Multi Bubble': 'Bubblebeam', 'Double Bubble': 'Bubble', 'Sleep Bubble': 'Bubble', 'Bubble Jump': 'Bubble', 'Water Pulse': 'WaterPulse',
    'Aqua Sonic': 'WaterPulse', 'Aqua Beam': 'WaterPulse', 'Aqua Blast': 'HydroPump', 'Aqua Smash': 'Waterfall', 'Aqua Crush': 'Waterfall',
    'Aqua Slash': 'WaterSlash', 'Water Slash': 'WaterSlash', 'Hydrocutter': 'WaterSlash', 'Razor Fin': 'WaterSlash', 'Sharp Fin': 'WaterSlash',
    'Fin Slap': 'SplashHit', 'Fin Smack': 'SplashHit', 'Flipper Splash': 'SplashHit', 'Flipper Stroke': 'SplashHit', 'Water Punch': 'SplashHit',
    'Hydro Punch': 'SplashHit', 'Wash Away': 'Surf', 'Salt Water': 'Splash', 'Rain': 'Rain', 'Dive': 'Waterfall', 'Deep Dive': 'Waterfall',
    'Super Deep Dive': 'Waterfall', 'Quick Dive': 'Waterfall', 'Aquabomb': 'Waterfall', 'Hydrokinesis': 'WaterPulse', 'Psysplash ': 'Psywave',
    'Prehistoric Water': 'HydroPump', 'Water of Evolution': 'AquaRing', 'Water Plant': 'AquaRing', 'Slimy Water': 'Octazooka',
    'Hyper Reverse': 'Whirlpool', 'Hydro Reverse': 'Whirlpool', 'Aqua Reverse': 'Whirlpool', 'Mist Attack': 'Smokescreen',
    'Dual Stream': 'HydroPump', 'Fast Stream': 'WaterGun', 'Core Stream': 'HydroPump', 'Energy Stream': 'WaterGun', 'Land Stream': 'Surf',
    'Vine Whip ': 'VineWhip', 'Stretch Vine': 'VineWhip', 'Vine Slap': 'VineWhip', 'Vine Tease': 'VineWrap', 'Grasping Vine': 'VineWrap',
    'Entangling Vines': 'VineWrap', 'Tickling Vines': 'VineWrap', 'Poison Vine': 'PoisonTentacle', 'Entangle': 'VineWrap',
    'Entangling Thread': 'StringShot', 'Entagling Thread': 'StringShot', 'Gooey Thread': 'StringShot', 'Poison Thread': 'StringShot',
    'Spider Web': 'Web', 'Spider Trap': 'Web', 'Spider Force': 'BugBuzz', 'String Pull': 'StringShot',
    'Razor Leaf ': 'RazorLeaf', 'Double Razor Leaf': 'RazorLeaf', 'Knife Leaf': 'RazorLeaf', 'Leaf Slice': 'LeafBlade', 'Sharp Leaf': 'RazorLeaf',
    'Miracle Leaf': 'MagicalLeaf', 'Psychic Leaf': 'MagicalLeaf', 'Spiral Leaf': 'LeafStorm', 'Petal Whirlwind': 'LeafStorm',
    'Leaf Shade': 'Protect', 'Green Blast': 'EnergyBall', 'Green Dance': 'PetalDance', 'Flower Dance': 'PetalDance',
    'Bullet Seed': 'BulletSeed', 'Seed Bomb': 'Seeds', 'Dark Seed': 'LeechSeed', 'Poison Seed': 'LeechSeed', 'Sleep Seed': 'LeechSeed',
    'Spiral Drain': 'MegaDrain', 'Vital Drain': 'MegaDrain', 'Life Drain': 'MegaDrain', 'Dig Drain': 'MegaDrain', 'Dark Drain': 'DreamEater',
    'Sleep Sap': 'MegaDrain', 'Energy Absorption': 'Absorb', 'Draining Cut': 'MegaDrain',
    'Healing Pollen': 'NatureRecovery', 'Healing Dust': 'NatureRecovery', 'Green Heal': 'NatureRecovery', 'Healing Oasis': 'NatureRecovery',
    'Soothing Scent': 'NatureRecovery', 'Sweet Nectar': 'NatureRecovery', 'Sticky Nectar': 'NatureRecovery', 'Energy Plant': 'NaturalPower',
    'Hard Plant': 'Growth', 'Paradise Pollen': 'CottonSpore', 'Rapture Pollen': 'CottonSpore', 'Addictive Pollen': 'CottonSpore',
    'Magic Pollen': 'CottonSpore', 'Horrid Pollen': 'PoisonPowder', 'Pollen Hazard': 'PoisonPowder', 'Stun Powder': 'StunSpore',
    'Break Powder': 'PoisonPowder', 'Magic Dust': 'CottonSpore', 'Miracle Powder': 'CottonSpore', 'Mysterious Powder': 'CottonSpore',
    'Rainbow Powder': 'CottonSpore', 'Strange Powder': 'StunSpore', 'Energy Powder': 'CottonSpore', 'Venom Powder': 'PoisonPowder',
    'Sleep Spore': 'SleepPowder', 'Toxic Spore': 'PoisonPowder', 'Poison Spore': 'PoisonPowder', 'Evolutionary Spore': 'Spore',
    'Spore Evolution': 'Spore', 'Stun Spore ': 'StunSpore', 'Stifling Fluff': 'CottonSpore', 'Flytrap': 'VineWrap',
    'Poison Powder': 'PoisonPowder', 'Healing Light': 'Heal', 'Miraculous Light': 'Flash', 'Mysterious Light': 'Flash', 'Blinding Light': 'Flash',
    'Sudden Flash': 'Flash', 'Flash Touch': 'Flash', 'Flashing Eyes': 'Flash', 'Lightning Flash': 'Flash', 'Eerie Light': 'ConfuseRay',
    'Coral Glow': 'Flash', 'Light Wave': 'Flash', 'Luster Blast': 'LightBall', 'Dazzle Blast': 'Flash', 'Dazzle Dance': 'Flash',
    'Moonwatching': 'Moonlight', 'Moon Guidance': 'Moonlight', 'Lunar Power': 'Moonlight', 'Lunar Blast': 'Lunar', 'Moon Impact': 'Lunar',
    'Moon Kick': 'MegaKick', 'Shining Star': 'StarStrike', 'Holy Star': 'StarStrike', 'Metal Star': 'StarStrike', 'Rainbow Star': 'ShootingStar',
    'Psychic Star': 'StarStrike', 'Shooting Star': 'ShootingStar', 'Star Boomerang': 'Swift', 'Star Back': 'Wish', 'Cosmic Draw': 'Wish',
    'Shining Fingers': 'Glitter', 'Shining Claws': 'MetalClaw', 'Gold Scale': 'Glitter', 'Miracle Essence': 'Wish', 'Miraculous Comeback': 'Wish',
    'Judgement': 'Spotlight', 'Revelation': 'Spotlight', 'Prophecy': 'Future', 'Data Retrieval': 'DataStrike', 'Data Sort': 'DataStrike',
    'Scanblast': 'DataStrike', 'Radar Jam': 'DataStrike', 'Block Signal': 'Block', 'Disconnect': 'Block', 'Limitation': 'Block',
    'Disable': 'Block', 'Corner': 'MeanLook', 'Block ': 'Block', 'Machine Burst': 'DataStrike', 'Texture Magic': 'Conversion',
    'Paint': 'Conversion', 'Paint Trick': 'Conversion', 'Type Match': 'Conversion', 'Delta Circle': 'TriAttack', 'Squared Attack': 'TriAttack',
    'Tri Attack ': 'TriAttack', '3-D Attack': 'TriAttack', 'Multiple Force': 'TriAttack', 'Elemental Blast': 'TriAttack',
    'Bi-Blast': 'TriAttack', 'Split Blast': 'TriAttack', 'Link Blast': 'TriAttack', 'Delta Beam': 'AuroraBeam', 'Rainbow Wave': 'AuroraBeam',
    'Aurora Wave': 'AuroraBeam', 'Crystal Beam': 'AuroraBeam', 'Crystal Laser': 'AuroraBeam', 'Crystal Wave': 'AuroraBeam',
    'Rainbow Moves': 'TriAttack', 'Distortion Beam': 'Psybeam', 'Devolution Beam': 'Devolve', 'Devolution Wave': 'Devolve',
    'Removal Beam': 'EnergyRemove', 'Removal Pulse': 'EnergyRemove', 'Super Removal': 'EnergyRemove', 'Psychic Removal': 'EnergyRemove',
    'Psychic Erase': 'EnergyRemove', 'Wide Laser': 'HyperBeam', 'Final Laser': 'HyperBeam', 'Target Beam': 'LockOn', 'Called Shot': 'LockOn',
    'Target Attack': 'LockOn', 'Target Scorch': 'LockOn', 'Target Slash': 'LockOn', 'Sharpshooter': 'LockOn', 'Sharpshooting': 'LockOn',
    'Lucky Shot': 'LockOn', 'Shoot Down': 'LockOn', 'Hook Shot': 'LockOn', 'Lock-on ': 'LockOn',
    'Mega Impact': 'GigaImpact', 'Gigacrush': 'GigaImpact', 'Deep Impact': 'GigaImpact', 'Heavy Impact': 'GigaImpact',
    'Breaking Impact': 'GigaImpact', 'Devastate': 'GigaImpact', 'Breakdown': 'GigaImpact', 'Wreck': 'GigaImpact', 'Tonnage': 'BodySlam',
    'Heavy Metal': 'SteelPunch', 'Crushing Blow': 'GigaImpact', 'Critical Crush': 'GigaImpact', 'Reckless Charge': 'TakeDown',
    'Careless Tackle': 'TakeDown', 'Raging Charge': 'TakeDown', 'Full Speed Charge': 'TakeDown', 'High-Speed Charge': 'TakeDown',
    'Sudden Charge': 'TakeDown', 'Rocket Tackle': 'GigaImpact', 'Spike Ball Tackle': 'Rollout', 'Rolling Tackle': 'Rollout',
    'Rolling Attack': 'Rollout', 'Continuous Tumble': 'Rollout', 'Rock Tumble': 'Rollout', 'Tumbling Attack': 'Rollout', 'Spin Ball': 'Rollout',
    'Bouncing Ball': 'Bounce', 'Bounce': 'Bounce', 'Bounce Off': 'Bounce', 'Bouncy Move': 'Bounce', 'Spring Back': 'Bounce',
    'Frog Hop': 'Bounce', 'Hop': 'Bounce', 'Leap': 'Bounce', 'Jump On': 'BodySlam', 'Jump Over': 'Bounce', 'Jump Catch': 'Bounce',
    'Spin Tackle': 'Spin', 'Spinning Attack': 'Spin', 'Spinning Head': 'Spin', 'Spinning Tail': 'Spin', 'Spinning Horn': 'HornDrill',
    'Spinning Blow': 'Spin', 'Double Spin': 'Spin', 'Triple Spin': 'Spin', 'Backspin': 'Spin', 'Spiral Attack': 'Spin',
    'Drill Tackle': 'HornDrill', 'Repeating Drill': 'HornDrill', 'Earthdrill': 'Dig', 'Dig Deep': 'Dig', 'Dig Under': 'Dig',
    'Burrow': 'Dig', 'Tunneling': 'Dig', 'Mining': 'Dig', 'Sand Pit': 'SandTomb', 'Sand Trap': 'SandTomb', 'Sand Swirl': 'Sandstorm',
    'Dust Devil': 'Sandstorm', 'Mudslide': 'MudSlap', 'Mud Splash': 'MudSlap', 'Muddy Eye': 'MudSlap', 'Desert Burn': 'Sandstorm',
    'Rock Hurl': 'RockThrow', 'Rock Toss': 'RockThrow', 'Pebble Hurl': 'RockThrow', 'Pebble Throw': 'RockThrow', 'Stone Barrage': 'RockSlide',
    'Mountain Crush': 'Avalanche', 'Mountain Smasher': 'Avalanche', 'Mountain Eater': 'Avalanche', 'Land Crush': 'Earthquake',
    'Crushing Earth': 'Earthquake', 'Major Earthquake': 'Earthquake', 'Tremor': 'Magnitude', 'Trembler': 'Magnitude', 'Rumble': 'Magnitude',
    'Raging Tremble': 'Earthquake', 'Earth Rift': 'Fissure', 'Collapse': 'Fissure', 'Land Sonic': 'Magnitude', 'Earth Bomb': 'Magnitude',
    'Stone Crush': 'RockTomb', 'Stone Generator': 'AncientPower', 'Fossil Charge': 'AncientPower', 'Retro Cave': 'AncientPower',
    'Genetic Memory': 'AncientPower', 'Rock Vengeance': 'StoneEdge', 'Granite Head': 'Headbutt', 'Rock Tackle': 'Headbutt',
    'Spike Barrage': 'PinMissile', 'Needle Storm': 'PinMissile', 'Needles': 'PinMissile', 'Needle Rush': 'PinMissile', 'Needle Ball': 'PinMissile',
    'Hyper Needle': 'PinMissile', 'Link Needle': 'PinMissile', 'Thunder Needle': 'PinMissile', 'Knockout Needle': 'Sting',
    'Triple Needle': 'TripleNeedle', 'Poison Needle': 'PoisonSting', 'Poison Barb': 'PoisonSting', 'Poison Needle Rush': 'PoisonSting',
    'Sharp Stinger': 'Sting', 'Sting': 'Sting', 'Tail Sting': 'PoisonSting', 'Jellyfish Sting': 'PoisonSting', 'Stun Needle': 'Sting',
    'Spike Stab': 'Sting', 'Double Stab': 'Twineedle', 'Sharp Point': 'Sting', 'Spearhead': 'Sting', 'Thunder Spear': 'ElectricTackle',
    'Poison Sting Tackle': 'PoisonSting', 'Fury Strikes': 'FuryAttack', 'Flock Attack': 'BugSwarm', 'Group Attack': 'GangUp',
    'Gang Up': 'GangUp', 'Dogpile': 'GangUp', 'Strength in Numbers': 'GangUp', 'Team Play': 'GangUp', 'Twin Play': 'GangUp',
    'Work Together': 'GangUp', 'Team Assembly': 'CallForFamily', 'Rely on Friends': 'GangUp', 'Assist': 'Copy', 'Helping Hand': 'Cheer',
    'Acidic Poison': 'Acid', 'Corrosive Acid': 'Acid', 'Harsh Fluid': 'Acid', 'Toxic Secretion': 'Acid', 'Secrete Poison': 'Acid',
    'Sludge': 'Sludge', 'Sludge Toss': 'Sludge', 'Sludge Punch': 'PoisonClaw', 'Sludge Grip': 'PoisonTentacle', 'Burning Sludge': 'Sludge',
    'Poison Sludge': 'Sludge', 'Nasty Goo': 'Sludge', 'Slime': 'Sludge', 'Paste': 'Sludge', 'Blot': 'Sludge', 'Drool': 'Acid',
    'Spit Poison': 'Acid', 'Spit Up': 'Sludge', 'Poison Spray': 'PoisonSpray', 'Poison Spurt': 'PoisonSpray', 'Splatter': 'Sludge',
    'Toxic Cloud': 'Smog', 'Poison Smog': 'Smog', 'Smogscreen': 'Smog', 'Foul Gas': 'PoisonGas', 'Foul Odor': 'PoisonGas', 'Smelly Gas': 'PoisonGas',
    'Vile Smell': 'PoisonGas', 'Suffocating Gas': 'PoisonGas', 'Poison Vapor': 'PoisonGas', 'Poison Breath': 'PoisonGas',
    'Super Poison Breath': 'PoisonGas', 'Confusion Gas': 'PoisonGas', 'Sleeping Gas': 'PoisonGas', 'Stun Gas': 'PoisonGas',
    'Slow Trip Gas': 'PoisonGas', 'Obscuring Gas': 'Smokescreen', 'Poison Scent': 'PoisonGas', 'Strange Scent': 'Charm',
    'Toxic Sleep': 'Toxic', 'Deadly Poison': 'Toxic', 'Triple Poison': 'Toxic', 'Thick Poison': 'Toxic', 'Toxic Vibration': 'Toxic',
    'Poison Buildup': 'Toxic', 'Poison Power': 'Toxic', 'Power Poison': 'Toxic', 'Dark Poison': 'Toxic', 'Earth Poison': 'Toxic',
    'Extra Poison': 'Toxic', 'Spread Poison': 'Toxic', 'Poison Reaction': 'Toxic', 'Reactive Poison': 'Toxic', 'Triggered Poison': 'Toxic',
    'Fast-Acting Poison': 'Toxic', 'Slow-Acting Poison': 'Toxic', 'Nerve Poison': 'Toxic', 'Stun Poison': 'Toxic', 'Sleep Poison': 'Toxic',
    'Lure Poison': 'Toxic', 'Leaf Poison': 'PoisonPowder', 'Lizard Poison': 'Toxic', 'Flick Poison': 'Acid', 'Poison Pulse': 'Toxic',
    'Poison Ring': 'Toxic', 'Poisonous Saliva': 'Acid', 'Toxic Saliva': 'Acid', 'Jellyfish Poison': 'PoisonTentacle', 'Jellyfish Pod': 'PoisonTentacle',
    'Poison Tentacles': 'PoisonTentacle', 'Tender Tentacles': 'PoisonTentacle', 'Dark Tentacle': 'PoisonTentacle', 'Tentacle Grip': 'PoisonTentacle',
    'Tentacle Wrap': 'PoisonTentacle', 'Long Tentacle': 'PoisonTentacle', 'Poison Bind': 'PoisonTentacle', 'Toxic Grip': 'PoisonTentacle',
    'Black Suction Cups': 'PoisonTentacle', 'Poison Claws': 'PoisonClaw', 'Toxic Claws': 'PoisonClaw', 'Poison Horn': 'PoisonHorn',
    'Poison Antennae': 'PoisonHorn', 'Poison Flame': 'Sludge', 'Burning Venom': 'Sludge', 'Poison Sting ': 'PoisonSting',
    'Silver Wind ': 'SilverWind', 'Bug Bite': 'LeechLife', 'Cat Fleas': 'BugSwarm', 'Pester': 'BugSwarm', 'Flitter': 'SilverWind',
    'Mysterious Wing': 'SilverWind', 'Rainbow Wing': 'SilverWind', 'Sacred Wing': 'SacredFire', 'Lightning Wing': 'ElectricTackle',
    'Scorching Wing': 'FireTail', 'Sonic Wing': 'Sonicboom', 'Razor Wing': 'AirSlash', 'Steel Wing': 'SteelWing', 'Aerowing': 'WingAttack',
    'Double Wing Attack': 'WingAttack', 'Aerial Maneuvers': 'Fly', 'Supersonic Flight': 'Fly', 'Glide': 'Fly', 'Nosedive': 'BraveBird',
    'Dive Bomb': 'BraveBird', 'Steep Dive': 'BraveBird', 'Spiral Dive': 'BraveBird', 'Skill Dive': 'BraveBird', 'Mid-air Crush': 'BraveBird',
    'Cutting Wind': 'AirCutter', 'Slicing Wind': 'AirCutter', 'Cross Wind': 'AirCutter', 'Shot Air': 'AirSlash', 'Gust ': 'Gust',
    'Mega Peck': 'DrillPeck', 'Peck Attack': 'Peck', 'Random Peck': 'FuryAttack', 'Double Peck': 'DrillPeck', 'Sharp Beak': 'Peck',
    'Steel Beak': 'Peck', 'Feather Fall': 'Fly',
    'Leek Slap': 'Slap', 'Leek Jab': 'Pound', 'Leek Rush': 'FuryAttack',
    'Mach Punch': 'Punch', 'Jab': 'Punch', 'Light Punch': 'Punch', 'Child\'s Punch': 'Punch', 'Cotton Punch': 'Punch', 'Pulled Punch': 'Punch',
    'Desperate Punch': 'MegaPunch', 'Heavy Punch': 'MegaPunch', 'Magnum Punch': 'MegaPunch', 'Smash Punch': 'MegaPunch',
    'Knuckle Punch': 'Punch', 'Steady Punch': 'Punch', 'Special Punch': 'MegaPunch', 'Energy Punch': 'MegaPunch', 'Power Lariat': 'MegaPunch',
    'Cat Punch': 'Punch', 'Lazy Punch': 'Punch', 'Hustle Punch': 'Punch', 'Tail Punch': 'Punch', 'Iron Fist': 'SteelPunch',
    'Corkscrew Punch': 'DynamicPunch', 'Spiral Punch': 'DynamicPunch', 'Split Spiral Punch': 'DynamicPunch', 'Hurricane Punch': 'RapidPunches',
    'Fury Punch': 'RapidPunches', 'Extra Comet Punch': 'CometPunch', 'One-Two Punch': 'CometPunch', 'One-Two Strike': 'CometPunch',
    'Reactive Beating': 'RapidPunches', 'Beat': 'Punch', 'Beatdown': 'RapidPunches', 'Sky Uppercut': 'MegaPunch', 'Speedy Uppercut': 'Punch',
    'Psychic Rage': 'Outrage', 'Upper Hand': 'Punch', 'Brick Smash': 'RockSmash', 'Pulverize': 'RockSmash', 'Pot Smash': 'RockSmash',
    'Chop': 'KarateChop', 'Double Chop': 'CrossChop', 'Vortex Chop': 'CrossChop', 'Smack': 'Slap', 'Slap Down': 'OneSlap',
    'Slap Push': 'OneSlap', 'Super Slap Push': 'OneSlap', 'Gentle Slap': 'Slap', 'Slap Awake': 'WakeUpSlap', 'Good Morning': 'WakeUpSlap',
    'Comet Slap': 'DoubleSlap', 'Tail Slap': 'TailSlap', 'Tail Rap': 'TailSlap', 'Tail Whap': 'TailSlap', 'Tail Snap': 'TailSlap',
    'Snap Tail': 'TailSlap', 'Tongue Slap': 'Lick', 'Tongue Whip': 'Lick', 'Upward Lick': 'Lick', 'Lap Up': 'Lick', 'Long Tongue': 'Lick',
    'Tongue Stretch': 'Lick', 'Tongue Wrap': 'Wrap', 'Lick Wounds': 'Heal',
    'Kick': 'Kick', 'Hind Kick': 'Kick', 'Rear Kick': 'Kick', 'Light Kick': 'Kick', 'Gentle Kick': 'Kick', 'Kick Away': 'MegaKick',
    'Risky Kick': 'MegaKick', 'Smash Kick': 'MegaKick', 'Sky Kick': 'MegaKick', 'Wild Kick': 'MegaKick', 'Split Kick': 'DoubleKick',
    'Stretch Kick': 'Kick', 'Spiral Kick': 'MegaKick', 'Upward Kick': 'MegaKick', 'Heel Drop': 'MegaKick', 'Energy Kick': 'MegaKick',
    'One-Two Kick': 'DoubleKick', 'Repeating Kick': 'TripleKick', 'Triple Kick': 'TripleKick', 'Cat Kick': 'CatKick',
    'Double Lariat': 'MegaPunch', 'Lariat': 'MegaPunch', 'Love Lariat': 'MegaPunch', 'Bear Hug': 'Squeeze', 'Hug': 'Squeeze',
    'Headlock': 'Squeeze', 'Strangle': 'Squeeze', 'Clutch': 'Squeeze', 'Grab': 'GrabCrush', 'Irongrip': 'GrabCrush', 'Cling': 'Squeeze',
    'Bound Crush': 'GrabCrush', 'Horn Grab': 'GrabCrush', 'Shell Grab': 'Clamp', 'Overhead Toss': 'SeismicToss', 'Pivot Throw': 'SeismicToss',
    'Light Touch Throw': 'SeismicToss', 'Mega Throw': 'SeismicToss', 'Toss': 'SeismicToss', 'Horn Toss': 'SeismicToss', 'Tusk Toss': 'SeismicToss',
    'Toss and Turn': 'SeismicToss', 'Flip Over': 'SeismicToss', 'Coin Hurl': 'Fling', 'Fling Away': 'SeismicToss', 'Fling': 'Fling',
    'Snapping Pincers': 'ViceGrip', 'Double Pinchers': 'ViceGrip', 'Prop-up Pinchers': 'ViceGrip', 'Sleep Pinchers': 'ViceGrip',
    'Vital Pinchers': 'ViceGrip', 'Metal Pincer': 'ViceGrip', 'Clamp Splash': 'Clamp', 'Horn Rush': 'Megahorn', 'Horn Charge': 'Megahorn',
    'Charging Horn': 'Megahorn', 'Giant Horn': 'Megahorn', 'Horn Thrust': 'HornAttack', 'Horn Swipe': 'HornAttack', 'Horn Hazard': 'HornAttack',
    'Angry Horn': 'Megahorn', 'Dark Horn': 'Megahorn', 'Mystifying Horns': 'HornAttack', 'Antler Swipe': 'HornAttack', 'Giant Tusk': 'Megahorn',
    'Impaling Tusk': 'Megahorn', 'Thrust': 'HornAttack', 'Pierce': 'HornAttack', 'Gouge': 'HornAttack',
    'Claw': 'Scratch', 'Claw Swipe': 'Scratch', 'Sharp Claws': 'FurySwipes', 'Extra Claws': 'FurySwipes', 'Hyper Claws': 'FurySwipes',
    'Rotating Claws': 'FurySwipes', 'Giant Claw': 'DragonClaw', 'Stretch Claws': 'Scratch', 'Mach Claw': 'FurySwipes', 'Supersonic Claws': 'FurySwipes',
    'Sky-high Claws': 'FurySwipes', 'Double Claw': 'DoubleClaw', 'Double Scratch': 'DoubleClaw', 'Scratch and Draw': 'Scratch', 'Rend': 'DoubleClaw',
    'Spike Rend': 'DoubleClaw', 'Shadow Claw': 'ShadowClaw', 'Swipe': 'Scratch', 'Sudden Swipe': 'Scratch', 'Brush Aside': 'Scratch',
    'Sweep Away': 'Scratch', 'Super Slash': 'Slash', 'Super Slice': 'Slash', 'Slashing Strike': 'Slash', 'Surprise Slash': 'Slash',
    'Ground Slash': 'Slash', 'Cross-Cut': 'CrossCut', 'Cross Attack': 'CrossCut', 'Double Cross': 'CrossCut', 'Dual Cut': 'DoubleSlash',
    'Twin-blade': 'DoubleSlash', 'Blade Arms': 'DoubleSlash', 'Triple Cutter': 'DoubleSlash', 'Sharp Sickle': 'Slash',
    'Blinding Scythe': 'LightSlash', 'Lightning Cut': 'LightSlash', 'Thunder Slash': 'LightSlash', 'Delta Edge': 'LightSlash',
    'Metal Hook': 'MetalClaw', 'Hook': 'Scratch', 'Metal Scoop': 'MetalClaw', 'Metal Tail': 'IronTail', 'Metal Charge': 'IronTail',
    'Metal Crush': 'SteelPunch', 'Metal Crusher': 'SteelPunch', 'Iron Smash': 'SteelPunch', 'Iron Head': 'IronTail', 'Steel Headbutt': 'IronTail',
    'Metallic Blow': 'SteelPunch', 'Metal Ball': 'MetalBall', 'Double Metal Ball': 'MetalBall', 'Metal Surge': 'MetalSound', 'Steel Wave': 'MetalSound',
    'Metallic Thunder': 'ZapCannon', 'Metal Burn': 'FireBlast', 'Steel Generator': 'SteelOrb', 'Metal Load': 'SteelOrb', 'Metal Reversal': 'Counter',
    'Mega Shot': 'HyperBeam', 'Power Ball': 'AuraSphere', 'Power Blast': 'AuraSphere', 'Pulse Blast': 'AuraSphere', 'Core Blast': 'HyperBeam',
    'Speed Ball': 'AuraSphere', 'Extra Ball': 'AuraSphere', 'Battle Blast': 'HyperBeam', 'All-out Blast': 'HyperBeam', 'MAX Burst': 'HyperBeam',
    'Reactive Blast': 'AuraSphere', 'Syncroblast': 'AuraSphere', 'Damage Blast': 'AuraSphere', 'Spiral Blast': 'AuraSphere',
    'Energy Cannon': 'AuraSphere', 'Energy Bomb': 'AuraSphere', 'Energy Burst': 'EnergyOut', 'Energy Crush': 'EnergyOut',
    'Energy Press': 'EnergyOut', 'Energy Loop': 'EnergyRings', 'Energy Cycle': 'EnergyRings', 'Energy Bone': 'BoneClub',
    'Delta Blast': 'AuraSphere', 'Magic Darts': 'Swift', 'Speed Shot': 'Swift', 'Rapid Fire': 'Swift', 'Auto Fire': 'WaterGun',
    'Dragon Tail': 'TailSmash', 'Dragon Smash': 'Outrage', 'Dragon Crush': 'Outrage', 'Devo Crush': 'Outrage', 'Dragon Burst': 'DragonRage',
    'Dragon Wave': 'DragonRage', 'Dragon Tornado': 'Twister', 'Dragon Spark': 'Thunderbolt', 'Dragon Mist': 'Smokescreen',
    'Dragon Dew': 'Heal', 'Dragon Eye': 'Glare', 'Dragon Bind': 'Bind', 'Dragon Bond': 'CallForFamily', 'Dragon\'s Vengeance': 'RoarOfTime',
    'Ozone Flare': 'RoarOfTime', 'Delta Crush': 'Outrage', 'Delta Mind': 'DarkMind', 'Delta Reduction': 'Barrier', 'Plasma': 'Thunderbolt',
    'Meteor Strike': 'Meteor', 'Comet': 'Meteor', 'Super Thunder Wave': 'ThunderWave', 'Stun Wave': 'ThunderWave', 'Jolt': 'ThunderWave',
    'Electromark': 'LockOn', 'Conduction': 'ThunderWave', 'Electric Current': 'ThunderWave', 'Attract Current': 'ThunderWave',
    'Tail Shock': 'ThunderWave', 'Negative Spark': 'Spark', 'Positive Spark': 'Spark', 'Negative Ion': 'Charge', 'Positive Ion': 'Charge',
    'Random Spark': 'Spark', 'Lightning Spark': 'Spark', 'Thunderspark': 'Spark', 'Return Spark': 'Spark', 'Gigaspark': 'Discharge',
    'High Voltage': 'Discharge', 'Max Voltage': 'Discharge', 'Meta Voltage': 'Discharge', 'Lightning Storm': 'Gigashock',
    'Rolling Thunder': 'Gigashock', 'Surprise Thunder': 'Thunder', 'Thunder Attack': 'Thunder', 'Thunder Force': 'Thunderbolt',
    'Thunder Flare': 'Thunderbolt', 'Thunder Gift': 'Charge', 'Power Bolt': 'Thunderbolt', 'Electric Bolt': 'Thunderbolt',
    'Electron Crush': 'ElectricTackle', 'Electroburn': 'Thunderbolt', 'Lightning Burn': 'Thunderbolt', 'Lightning Rod': 'Thunderbolt',
    'Lightning Tail': 'ElectricTackle', 'Extra Circuit': 'Charge', 'Special Circuit': 'Charge', 'Double Shock': 'ThunderShock',
    'Dark Shock': 'ThunderShock', 'Shockwave': 'Shockwave', 'Shock-wave': 'Shockwave', 'Mind Shock ': 'MindShock',
    'Confusion Wave': 'Supersonic', 'Confusion Pulse': 'Supersonic', 'Distorted Wave': 'Supersonic', 'Dwindling Wave': 'Psywave',
    'Spiral Wave': 'Hypnosis', 'Hypno Wave ': 'Hypnosis', 'Soothing Wave': 'HealingSong', 'Healing Wave': 'AquaRing', 'Return Wave': 'Surf',
    'Psychic Pulse': 'Psywave', 'Clay Pulse': 'Psywave', 'Multi Pulse': 'Psywave', 'Psychic Force': 'Psychic', 'Psychic Damage': 'PsychicDamage',
    'Psychic Exchange': 'PainSplit', 'Supernatural': 'Psychic', 'Supernatural Power': 'PsychicBlast', 'Miracle Blow': 'PsychicBlast',
    'Invisible Hand': 'Telekinesis', 'Sleight of Hand': 'Telekinesis', 'Dark Hand': 'ShadowPunch', 'Powerful Hand': 'Psypunch',
    'Bursting Hand': 'Psypunch', 'Sticky Hands': 'Telekinesis', 'Psychic Option': 'Meditate', 'Psychic Select': 'Meditate', 'Chakra Points': 'Meditate',
    'Spiral Aura': 'Meditate', 'Psychic Boom ': 'PsychicBlast', 'Hypnotic Gaze ': 'Glare', 'Migraine': 'MindShock', 'Headache': 'MindShock',
    'Dizziness': 'Confusion', 'Mix-Up': 'Confusion', 'Strange Dance': 'Confusion', 'Fickle Attack': 'Confusion', 'Losing Control': 'Confusion',
    'Dream Dance': 'Hypnosis', 'Afternoon Nap': 'Rest', 'Nap': 'Rest', 'Nap Time': 'Rest', 'Naptime': 'Rest', 'Slack Off': 'Rest',
    'Yawn': 'Rest', 'Good Night': 'Sing', 'Healing Egg': 'Softboiled', 'Healing Milk': 'MilkDrink', 'Healing Steps': 'Heal',
    'First Aid': 'Heal', 'Mend': 'Heal', 'Bind Wound': 'Heal', 'Power Heal': 'Heal', 'Energy Heal': 'Heal', 'Energy Healing': 'Heal',
    'Hyper Healing': 'Heal', 'Empathic Healing': 'HealBench', 'Group Therapy': 'HealBench', 'Invigorate': 'Heal', 'Recover ': 'Recover',
    'Dark Aid': 'Heal', 'Healing Light ': 'Heal',
    'Smokescreen ': 'Smokescreen', 'Mist': 'Smokescreen', 'Mirage': 'Substitute', 'Juxtapose': 'Switch', 'Quick Change': 'Switch',
    'Bench Manipulation': 'Switch', 'Darkness Switch': 'Switch', 'Push Aside': 'Switch', 'Push Away': 'Switch', 'Pull In': 'Switch',
    'Drag Off': 'Switch', 'Pull Away': 'Switch', 'Whirlwind ': 'Whirlwind', 'Knock Away': 'TakeDown', 'Knock Back': 'TakeDown',
    'Knock Down': 'BodySlam', 'Knock Over': 'BodySlam', 'Knock Off': 'Scratch', 'Shove': 'Tackle', 'Lunge': 'Tackle', 'Lunge Out': 'Tackle',
    'Rising Lunge': 'TakeDown', 'Gallop': 'TakeDown', 'Stampede': 'Trample', 'Overrun': 'Trample', 'Trample': 'Trample', 'Crushing Step': 'Stomp',
    'Stamp': 'Stomp', 'Circular Steps': 'Stomp', 'Squaredance': 'Stomp', 'The Hula-la': 'Stomp', 'Headpress': 'BodySlam',
    'Double Headbutt': 'Headbutt', 'Triple Headbutt': 'Headbutt', 'Continuous Headbutt': 'Headbutt', 'Fury Headbutt': 'Headbutt',
    'Raging Headbutt': 'Headbutt', 'Lazy Headbutt': 'Headbutt', 'Screaming Headbutt': 'Headbutt', 'Tackle ': 'Tackle', 'Double Tackle': 'Tackle',
    'Double Tack': 'Tackle', 'Ram': 'Tackle', 'Rush': 'Tackle', 'Quick Blow': 'QuickAttack', 'Swift Blow': 'QuickAttack', 'Quick Touch': 'QuickAttack',
    'Lazy Attack': 'Tackle', 'Risky Attack': 'TakeDown', 'Pounce': 'Bounce', 'Leap Out': 'Bounce', 'Run Around': 'Agility',
    'Tail Strike': 'TailSmash', 'Tail Smash': 'TailSmash', 'Quick Tail Smash': 'TailSmash', 'Tail Crush': 'TailSmash', 'Giant Tail': 'TailSmash',
    'Hyper Tail': 'TailSmash', 'Miracle Tail': 'TailSmash', 'Trick Tail': 'TailSlap', 'Stretch Tail': 'TailSlap', 'Fishing Tail': 'TailSlap',
    'Tail Wrap': 'Wrap', 'Fish Out': 'Wrap', 'Gentle Wrap': 'Wrap', 'Squeeze': 'Squeeze', 'Crush': 'Squeeze', 'Scrunch': 'Squeeze',
    'Smash': 'BodySlam', 'Heavy Blow': 'PowerfulHit', 'Power Blow': 'PowerfulHit', 'Power Crush': 'PowerfulHit', 'Special Blow': 'PowerfulHit',
    'Power Move': 'PowerfulHit', 'Critical Move': 'PowerfulHit', 'Chaos Crush': 'PowerfulHit', 'Extra Crush': 'PowerfulHit',
    'Hard Bone': 'BoneClub', 'Bone Smash': 'BoneClub', 'Triple Bone': 'BoneRush',
    'Silver Wind  ': 'SilverWind', 'Haze': 'Smokescreen', 'Surprise': 'Exclaim', 'Birthday Surprise': 'Present', 'Shake': 'Exclaim',
    'Shakedown': 'Taunt', 'Provoke': 'Taunt', 'Mischief': 'Taunt', 'Pranks': 'Taunt', 'Tantalize': 'Taunt', 'Gesture': 'Taunt',
    'Influence': 'Flatter', 'Suggestion': 'Flatter', 'Even Game': 'Flatter', 'False Charity': 'Flatter',
    'Mug': 'QuickAttack', 'Rob': 'QuickAttack', 'Pilfer': 'QuickAttack', 'Plunder': 'QuickAttack', 'Snatch': 'QuickAttack',
    'Take Away': 'QuickAttack', 'Thief': 'QuickAttack', 'Liability': 'Question', 'Bad News': 'Question',
    'Shed': 'Substitute', 'Hatch': 'Substitute', 'Mimic': 'Copy', 'Quick Bind': 'Bind', 'Dark Bind': 'Bind',
    'Signs of Evolution': 'Glitter', 'Fast Evolution': 'Glitter', 'Rapid Evolution': 'Glitter', 'Explosive Evolution': 'Explosion',
    'Delta Call': 'CallForFamily', 'Delta Draw': 'Draw', 'Delta Search': 'Search', 'Holon Draw': 'Draw', 'Holon Search': 'Search',
    'Energy Call': 'EnergyUp', 'Aqua Call': 'EnergyUp', 'Darkness Call': 'EnergyUp', 'Darkness Charge': 'EnergyUp', 'Energy Draw': 'EnergyUp',
    'Energy Link': 'EnergyUp', 'Energy Recall': 'EnergyUp', 'Energy Recycle': 'EnergyUp', 'Energy Retrieval': 'EnergyUp',
    'Energy Catch': 'EnergyUp', 'Energy Support': 'EnergyUp', 'Energy Patch': 'EnergyUp', 'Energy Control': 'EnergyUp', 'Energy Conversion': 'EnergyUp',
    'Gather Energy': 'EnergyUp', 'Max Energy Source': 'EnergyUp', 'Ultra Energy Source': 'EnergyUp', 'Drawup Power': 'EnergyUp',
    'Plus Energy': 'EnergyUpSmall', 'Minus Energy': 'EnergyRemove', 'Energy Flip': 'EnergyUpSmall', 'Aqua Supply': 'EnergyUp',
    'Dark Provide': 'EnergyUp', 'Burn Booster': 'EnergyUp', 'Steel Generator ': 'SteelOrb', 'Messenger': 'Search', 'Errand-Running': 'Search',
    'Minor Errand-Running': 'Search', 'Important Errands': 'Search', 'Limited Delivery': 'Search', 'Baby Outing': 'CallForFamily',
    'Dump and Draw': 'Draw', 'Whimsy Draw': 'Draw', 'Loving Draw': 'Draw', 'Down Draw': 'Draw', 'Extra Draw': 'Draw', 'Pick and Choose': 'Search',
    'Critical Collection': 'Draw', 'Stadium Play': 'Spotlight', 'Stadium Power': 'Spotlight', 'Synchronized Search': 'Search',
    'Ascension': 'Glitter', 'Bay Dance': 'Glitter', 'Prize Count': 'Draw', 'Power Count': 'Draw', 'Skill Hack': 'DataStrike',
    'Special Formula': 'DataStrike', 'Linear Attack': 'Sonicboom', 'Enraged Linear Attack': 'Sonicboom',
    # --- odd names the keywords got wrong or missed ---
    'Sleepy Ball': 'Bubble', 'Souvenir': 'CurseCounters', 'Double Damage': 'GangUp', 'Pull Down': 'Devolve', 'Repulsion': 'Whirlwind',
    'Grand Loop': 'Draw', 'Pick On': 'Taunt', 'Power Short': 'Thunderbolt', 'Double Attack': 'Bubble', 'Triple Breach': 'Bubblebeam',
    'Solar Blast': 'Solarbeam', 'Cannonball': 'TakeDown', 'Fastwave': 'Psywave', 'Vengeful Spikes': 'PinMissile', 'Sputter': 'SmallBomb',
    'Nail Flick': 'Scratch', 'Flop': 'Splash', 'Flail Around': 'Thrash', 'Swallow': 'Crunch', 'Swallow Up': 'Crunch', 'Surround': 'Psywave',
    'Bustle': 'Spark', 'Grind': 'Counter', 'Shatter': 'ShieldBreak', 'Derail': 'ShieldBreak', 'Speed Stroke': 'QuickAttack',
    'Undulate': 'Surf', 'Time Trap': 'Future', 'Sore Spot': 'Waterfall', 'Strange Scale': 'SilverWind', 'Flutter Trick': 'SilverWind',
    'Sporadic Sponging': 'MegaDrain', 'Parallel Gain': 'Absorb', 'Litter': 'Fling', 'Aftermath': 'Haunt', 'Boyfriends': 'GangUp',
    'Surge': 'WaterPulse', 'Vengeance': 'Counter', 'Terror Strike': 'FeintAttack', 'Trip Over': 'Tackle', 'Second Strike': 'Punch',
    'Scramble Trip': 'TriAttack', 'Shuffle Attack': 'MindShock', 'Curve Attack': 'TriAttack', 'Reverse Thrust': 'Switch',
    'Call of the Night': 'DarkCloud', 'Shell Rupture': 'MiniExplosions', 'Burn Away': 'Inferno', '3-Pronged Tail': 'TailSlap',
    # --- giving the remaining effects a home ---
    'Mass Destruction': 'Meteor', 'Gesture': 'Swagger', 'Mischief': 'Torment', 'Mind Bend': 'SpoonBend', 'Dizziness': 'DizzyPunch',
    'Iron Fist': 'FistSlam', 'Powerful Hand': 'ForcePalm', 'Bursting Hand': 'Palm', 'Hard Plant': 'Ingrain', 'Energy Plant': 'Ingrain',
    'Flytrap': 'Roots', 'Grasping Vine': 'Roots', 'Entangling Vines': 'GrassKnot', 'Green Blast': 'GreenHit', 'Petal Whirlwind': 'PetalBlizzard',
    'Toxic Claws': 'CrossPoison', 'Psychic Star': 'StarBeam', 'Back Burner': 'FlameStar', 'Moon Impact': 'MoonAttack',
    'Helping Hand': 'Clap', 'Cheer On': 'Encore', 'Darkness Charge': 'DarkPowerUp', 'Dark Provide': 'DarkPowerUp', 'Mud Splash': 'MudSport',
    'Rotating Claws': 'SpinningSlash', 'Night Attack': 'NightShade', 'Night Spirits': 'NightShade', 'Black Magic': 'EvilForce',
    'Shining Fingers': 'FingerStorm', 'Pranks': 'NastyPlot', 'Rainbow Wing': 'RainbowWing', 'Mysterious Wing': 'RainbowWing',
    'Max Energy Source': 'EnergyAbsorbLong', 'Ultra Energy Source': 'EnergyAbsorbLong', 'Belly Drum': 'PowerUpNoRing',
    'Pebble Throw': 'Pebbles', 'Pebble Hurl': 'Pebbles', 'Speed Growth': 'NatureBoost', 'Pop': 'SmokeBurst', 'Smash Bomber': 'SmokeBurst',
    'Sharp Claws': 'ShadowClaw', 'Needle Ball': 'BulletSeed', 'Fruition': 'Seeds', 'Draining Cut': 'DrainPunch',
    # --- pass 2: the new recipes ---
    'Mug': 'Steal', 'Rob': 'Steal', 'Pilfer': 'Steal', 'Plunder': 'Steal', 'Snatch': 'Steal', 'Take Away': 'Steal',
    'Snatch and Run': 'Steal', 'Thief': 'Steal', 'Hatch': 'Hatch', 'Leer': 'Leer', 'Stare': 'Leer', 'Night Eyes': 'Leer',
    'Evil Eye': 'Leer', 'Mist Ball': 'MistBall', 'Luster Purge': 'MistBall', 'Coin Hurl': 'PayDay', 'Birthday Surprise': 'Present',
    'Seed Bomb': 'GreenHit', 'Burst': 'GreenHit',
}

# 2) KEYWORDS on the lower-case name, first match wins. (regex, recipe)
KEYWORDS = [
    (r'thunder|lightning|volt|zap|electr', 'Thunderbolt'),
    (r'spark|shock', 'ThunderShock'),
    (r'blizzard|freez|frost|icicle|\bice\b|\bicy\b|\bcold\b|snow|hail|glacier', 'IceBeam'),
    (r'fire|flame|blaze|burn|heat|scorch|inferno|magma|lava|ember', 'Flamethrower'),
    (r'hydro|aqua|water|bubble|splash|wave|surf|tide|flood|rain', 'WaterGun'),
    (r'leaf|vine|petal|seed|pollen|spore|powder|bloom|plant|root|flower', 'RazorLeaf'),
    (r'poison|toxic|venom|sludge|acid|smog|gas', 'Toxic'),
    (r'psy|mind|hypno|dream|telepath|esp\b', 'Psychic'),
    (r'shadow|dark|night|evil|curse|ghost|spirit|haunt', 'DarkWave'),
    (r'dragon', 'DragonRage'),
    (r'metal|steel|iron', 'IronTail'),
    (r'rock|stone|boulder|pebble|mountain', 'RockThrow'),
    (r'quake|tremor|earth|ground|land', 'Magnitude'),
    (r'sand|mud|dirt|dust', 'SandAttack'),
    (r'wind|gust|cyclone|tornado|storm|air', 'Gust'),
    (r'star|comet|meteor', 'Swift'),
    (r'light|shine|shining|glow|flash|bright', 'Flash'),
    (r'sound|voice|song|sing|cry|howl|roar|noise|scream', 'HyperVoice'),
    (r'punch|fist|knuckle|uppercut|jab', 'Punch'),
    (r'kick|stomp|stamp', 'Kick'),
    (r'claw|scratch|swipe', 'Scratch'),
    (r'slash|cut|blade|slice|scythe|sickle|edge', 'Slash'),
    (r'bite|fang|jaw|teeth|chomp|gnaw', 'Bite'),
    (r'horn|tusk|drill|needle|spike|stab|spear|pierce|sting', 'HornAttack'),
    (r'wing|peck|beak|feather', 'WingAttack'),
    (r'tail', 'TailSlap'),
    (r'slap|smack', 'Slap'),
    (r'tackle|charge|rush|ram\b|headbutt|lunge|dash', 'Tackle'),
    (r'slam|crush|smash|impact|press|pound|hammer|blow|bash|stomp', 'BodySlam'),
    (r'wrap|bind|squeeze|hug|constrict|grip|clutch|grab', 'Squeeze'),
    (r'throw|toss|hurl|fling', 'SeismicToss'),
    (r'spin|roll|tumble|spiral|whirl', 'Spin'),
    (r'heal|recover|rest|nap|sleep', 'Heal'),
    (r'bomb|blast|burst|explo|cannon|beam', 'HyperBeam'),
]

# Physical vs special for the type fallback.
PHYS_WORDS = r'tackle|punch|kick|slam|bash|butt|ram\b|rush|charge|crush|smash|strike|hit|blow|chop|claw|scratch|slash|cut|bite|fang|jaw|' \
             r'tail|horn|tusk|head|body|stomp|trample|beat|pound|slap|jab|peck|wing|hug|squeeze|grab|toss|throw|drop|dive|impact|lunge|' \
             r'lariat|knock|push|shove|gnaw|chomp|clamp|pinch|drill|spin|roll|tumble|bounce|jump|leap|hop|stamp|step|attack|swipe|fist|' \
             r'scrunch|press|crunch|hammer|whip|smack|club|gouge|rend|tear|scrape|trip|sweep|rampage|frenzy|fury|tantrum|wreck|pierce|stab'

# ========================================================================================
def scan_manifest():
    try:
        from PIL import Image
    except ImportError:
        Image = None
    man = {}
    for dirpath, dirs, files in os.walk(FX_DIR):
        pngs = sorted(f for f in files if f.lower().endswith('.png'))
        if not pngs:
            continue
        part = os.path.relpath(dirpath, FX_DIR).replace('\\', '/')
        w = h = 0
        if Image:
            with Image.open(os.path.join(dirpath, pngs[0])) as im:
                w, h = im.size
            for f in pngs[1:]:
                with Image.open(os.path.join(dirpath, f)) as im:
                    w, h = max(w, im.size[0]), max(h, im.size[1])
        man[part] = {'frames': pngs, 'w': w, 'h': h}
    return man


def load_attacks():
    by = collections.OrderedDict()
    for f in sorted(glob.glob(os.path.join(CARD_DIR, '*.json'))):
        if os.path.basename(f) == 'pack_prices.json':
            continue
        with open(f, encoding='utf-8') as fh:
            for c in json.load(fh):
                for a in c.get('attacks') or []:
                    n = (a.get('name') or '').strip()
                    if not n:
                        continue
                    e = by.setdefault(n, {'types': collections.Counter(), 'cost': [], 'dmg': [], 'text': [], 'cards': []})
                    e['types'].update(c.get('types') or ['Colorless'])
                    e['cost'].append(a.get('convertedEnergyCost', len(a.get('cost') or [])))
                    e['dmg'].append(a.get('damage') or '')
                    e['text'].append(a.get('text') or '')
                    e['cards'].append(c.get('id'))
    return by


def classify_utility(text):
    t = text.lower().replace('é', 'e')
    if 'damage counter' in t and 'defending' in t or 'benched' in t and 'damage' in t:
        return 'counters'
    for w in ['defending pokemon', "opponent's active", 'asleep', 'confused', 'paralyzed', 'poisoned', 'burned',
              "can't retreat", "can't attack", 'your opponent']:
        if w in t:
            return 'inflict'
    for w in ['this pokemon', 'attach', 'your deck', 'your hand', 'remove', 'heal', 'during your next turn']:
        if w in t:
            return 'self'
    return 'other'


def text_recipe(text):
    """Zero-damage attacks: what the card text says it does."""
    t = text.lower().replace('é', 'e')
    if 'heal' in t and ('each of your' in t or 'benched' in t):
        return 'HealBench'
    if re.search(r'remove \d+ damage counter|heal', t):
        return 'Heal'
    if re.search(r'discard (an?|\d+|all) .*energy .*defending|discard .*energy attached to the defending|energy .*(from|attached to) (the defending|1 of your opponent)', t):
        return 'EnergyRemove'
    if re.search(r'devolve|evolution card .* shuffle|return .*evolution card', t):
        return 'Devolve'
    if re.search(r'is now asleep', t) and not re.search(r'poisoned|paralyzed|confused', t):
        return 'Sing'
    if re.search(r'is now paralyzed', t):
        return 'ThunderWave'
    if re.search(r'is now confused', t):
        return 'Supersonic'
    if re.search(r'is now poisoned|is now badly poisoned', t):
        return 'PoisonGas'
    if re.search(r'is now burned', t):
        return 'WillOWisp'
    if re.search(r"can't attack|can't retreat|can't use", t):
        return 'MeanLook'
    if re.search(r'put \d+ damage counter|damage counters? on', t):
        return 'CurseCounters'
    if re.search(r'prevent all (effects of attacks, including )?damage|prevent all damage', t):
        return 'Protect'
    if re.search(r'switch|return .* to (your|his or her) hand|shuffle .* into', t) and 'deck for' not in t:
        return 'Switch'
    if re.search(r'attach .*energy', t):
        return 'EnergyUp'
    if re.search(r'search your deck for .*(pokemon|basic)|put .* onto your bench', t):
        return 'CallForFamily'
    if re.search(r'search your deck|look at the top|draw', t):
        return 'Search'
    if re.search(r'each of your opponent', t) and 'bench' in t:
        return 'Earthquake'
    if re.search(r'choose 1 of the defending pokemon.s attacks|copy|use .* as this attack', t):
        return 'Copy'
    return None


def tier(cost):
    return 0 if cost <= 1 else (1 if cost == 2 else 2)


def build():
    apply_pass2()
    man = scan_manifest()
    attacks = load_attacks()
    exact_ci = {k.strip().lower(): v for k, v in EXACT.items()}
    mapping, how = {}, collections.Counter()
    for name, e in attacks.items():
        n = name.lower()
        damaging = any(d.strip() for d in e['dmg'])
        text = max(e['text'], key=len) if e['text'] else ''
        rid, src = None, ''
        if n in exact_ci:
            rid, src = exact_ci[n], 'exact'
        if rid is None and not damaging:
            r = text_recipe(text)
            if r:
                rid, src = r, 'text'
        if rid is None:
            for pat, r in KEYWORDS:
                if re.search(pat, n):
                    rid, src = r, 'keyword'
                    break
        if rid is None and not damaging:
            rid, src = UTILITY[classify_utility(text)], 'utility'
        style = 'phys' if re.search(PHYS_WORDS, n) else 'spec'
        if rid is None:
            mapping[name] = {'fx': '@type', 'style': style, 'how': 'type'}
            how['type'] += 1
        else:
            mapping[name] = {'fx': rid, 'how': src}
            how[src] += 1
        # The dominant type and cost, for the report and for the debugger's preview.
        mapping[name]['type'] = e['types'].most_common(1)[0][0]
        mapping[name]['cost'] = max(set(e['cost']), key=e['cost'].count) if e['cost'] else 1
        mapping[name]['dmg'] = damaging
        st = []
        tl = ' '.join(e['text']).lower()
        for word, kind in [('badly poisoned', 'Toxic'), ('now poisoned', 'Poisoned'), ('now burned', 'Burned'),
                           ('now paralyzed', 'Paralyzed'), ('now asleep', 'Asleep'), ('now confused', 'Confused')]:
            if word in tl and not (kind == 'Poisoned' and 'Toxic' in st):
                st.append(kind)
        if st:
            mapping[name]['status'] = st
        v = VARIANTS.get(mapping[name]['fx'])
        if v:
            bt = {t: v[t] for t in e['types'] if t in v}
            if bt:
                mapping[name]['by_type'] = bt
        if re.search(r"bench", tl) and re.search(r"damage", tl) and not re.search(r"prevent all damage", tl):
            mapping[name]['bench'] = True

    clips = sfx_clips()
    apply_sfx(mapping, clips)

    # Sanity: every referenced recipe and part exists.
    missing = set()
    for rid, r in list(RECIPES.items()) + list(STATUS.items()):
        for s in r['steps']:
            if 'fx' in s and s['fx'] not in man:
                missing.add((rid, s['fx']))
    for t, f in FALLBACK.items():
        for st in f.values():
            for rid in st:
                if rid not in RECIPES:
                    missing.add(('FALLBACK ' + t, rid))
    for rid in UTILITY.values():
        if rid not in RECIPES:
            missing.add(('UTILITY', rid))
    for name, m in mapping.items():
        if m['fx'] != '@type' and m['fx'] not in RECIPES:
            missing.add((name, m['fx']))
    for rid, v in VARIANTS.items():
        for t, r in v.items():
            if r not in RECIPES:
                missing.add(('VARIANT ' + rid, r))
    if missing:
        for m in sorted(missing):
            print('MISSING:', m)
        raise SystemExit(1)

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, 'vfx_manifest.json'), 'w', encoding='utf-8') as f:
        json.dump(man, f, indent=1, sort_keys=True)
    with open(os.path.join(OUT_DIR, 'vfx_recipes.json'), 'w', encoding='utf-8') as f:
        json.dump({'recipes': RECIPES, 'status': STATUS, 'fallback': FALLBACK, 'utility': UTILITY, 'elements': ELEMENTS,
                   'sounds': SOUNDS}, f, indent=1)
    with open(os.path.join(OUT_DIR, 'attack_vfx_map.json'), 'w', encoding='utf-8') as f:
        json.dump(mapping, f, indent=1, ensure_ascii=False, sort_keys=True)

    groups = collections.defaultdict(list)
    for name, m in mapping.items():
        key = m['fx'] if m['fx'] != '@type' else '@type ' + m['type'] + ' ' + m['style'] + ' t' + str(tier(m['cost']) + 1)
        groups[key].append(f"{name}{'' if m['how'] == 'exact' else ' (' + m['how'] + ')'}")
    used = {m['fx'] for m in mapping.values()} | {r for f in FALLBACK.values() for st in f.values() for r in st}
    with open(os.path.join(OUT_DIR, 'attack_vfx_report.txt'), 'w', encoding='utf-8') as f:
        f.write(f"{len(mapping)} attacks  " + '  '.join(f'{k}={v}' for k, v in how.most_common()) + '\n\n')
        for k in sorted(groups, key=str.lower):
            f.write(f"[{k}] {len(groups[k])}\n    " + ', '.join(sorted(groups[k], key=str.lower)) + '\n')
        f.write('\nRECIPES NOT USED BY ANY ATTACK: ' + ', '.join(sorted(set(RECIPES) - used)) + '\n')
        parts_used = {s['fx'] for r in list(RECIPES.values()) + list(STATUS.values()) for s in r['steps'] if 'fx' in s}
        f.write('EFFECT PARTS NOT USED BY ANY RECIPE: ' + ', '.join(sorted(set(man) - parts_used)) + '\n')
    print(f"{len(man)} effect parts, {len(RECIPES)} recipes, {len(mapping)} attacks:", dict(how))


if __name__ == '__main__':
    build()
