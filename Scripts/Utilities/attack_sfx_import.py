"""
ATTACK SFX IMPORTER -- prepares the Pokémon move sound effects the attack animations play.

Needs numpy + soundfile (not part of the plain Python install):
    py -m venv sfxenv  &&  sfxenv\\Scripts\\python -m pip install numpy soundfile
    sfxenv\\Scripts\\python "Scripts/Utilities/attack_sfx_import.py" "C:/PKMTCG/pokemon_sfx_pack"

Reads   <pack>/GEN 4 SFX - Attack Moves - DPPL, HG, SS/*.mp3   (Gen 4: the DS era, closest to the
        Mystery Dungeon Explorers visuals; every Gen 1-4 move plus the battle-system sounds)
Writes  Audio/SFX/Attacks/<Move>.ogg            each clip trimmed of its leading / trailing silence,
                                                peak-normalised, mono (the source is 320 kbps stereo mp3)
        Attack_Animation_Data/sfx_manifest.json clip -> {dur, hit, onsets, src}

"hit" is where a clip's main impact lands (the last onset that is nearly as loud as the loudest part):
Fire Blast's spinning-wheel pulses come before it, Tackle's thump IS it. Attack_VFX.gd plays the part
before the hit as the animation builds up and cuts to the hit the moment the impact lands.

Run it once after downloading the pack (or a new one); then run attack_vfx_build.py, which picks the
clip for every recipe and attack out of sfx_manifest.json.
"""
import json, os, sys
import numpy as np
import soundfile as sf

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT_AUDIO = os.path.join(ROOT, 'Audio', 'SFX', 'Attacks')
OUT_MANIFEST = os.path.join(ROOT, 'Attack_Animation_Data', 'sfx_manifest.json')
GEN4 = 'GEN 4 SFX - Attack Moves - DPPL, HG, SS'

SILENCE = 0.04        # below this share of the loudest 10 ms, a clip counts as silent
KEEP_HEAD = 0.01      # seconds of lead-in kept before the first sound
PEAK = 0.89           # normalised peak (about -1 dBFS)
HOP = 0.01
OGG_QUALITY = 0.55


def envelope(x, sr):
    hop = int(sr * HOP)
    n = max(1, len(x) // hop)
    return np.array([np.sqrt(np.mean(x[i * hop:(i + 1) * hop] ** 2) + 1e-12) for i in range(n)])


def onsets(rms):
    thr = rms.max() * 0.1
    out = [0.0]
    for i in range(5, len(rms)):
        prev = rms[i - 5:i].mean()
        if rms[i] > thr and rms[i] > prev * 2.2 and i * HOP - out[-1] > 0.08:
            out.append(round(i * HOP, 2))
    return out


def main_hit(rms, ons):
    """The last onset whose next 150 ms reach 70% of the clip's loudest moment."""
    top = rms.max()
    hit = 0.0
    for t in ons:
        i = int(t / HOP)
        if rms[i:i + 15].max() >= top * 0.7:
            hit = t
    return hit


def process(src, dst):
    d, sr = sf.read(src, always_2d=True)
    x = d.mean(axis=1)
    rms = envelope(x, sr)
    loud = np.where(rms > rms.max() * SILENCE)[0]
    if len(loud) == 0:
        return None
    a = max(0, int((loud[0] * HOP - KEEP_HEAD) * sr))
    b = min(len(x), int((loud[-1] + 1) * HOP * sr) + int(0.03 * sr))
    x = x[a:b]
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x * (PEAK / peak)
    # A 5 ms fade at each end so trimming never clicks.
    f = min(len(x) // 4, int(0.005 * sr))
    if f > 0:
        x[:f] *= np.linspace(0, 1, f)
        x[-f:] *= np.linspace(1, 0, f)
    sf.write(dst, x.astype(np.float32), sr, format='OGG', subtype='VORBIS', compression_level=1.0 - OGG_QUALITY)
    rms = envelope(x, sr)
    ons = onsets(rms)
    return {'dur': round(len(x) / sr, 3), 'hit': main_hit(rms, ons), 'onsets': ons[:16]}


def main():
    pack = sys.argv[1] if len(sys.argv) > 1 else r'C:\PKMTCG\pokemon_sfx_pack'
    src_dir = os.path.join(pack, GEN4)
    os.makedirs(OUT_AUDIO, exist_ok=True)
    man = {}
    for f in sorted(os.listdir(src_dir)):
        if not f.lower().endswith('.mp3'):
            continue
        name = os.path.splitext(f)[0]
        info = process(os.path.join(src_dir, f), os.path.join(OUT_AUDIO, name + '.ogg'))
        if info is None:
            print('silent, skipped:', f)
            continue
        info['src'] = 'gen4/' + f
        man[name] = info
    with open(OUT_MANIFEST, 'w', encoding='utf-8') as fh:
        json.dump(man, fh, indent=1, sort_keys=True)
    total = sum(os.path.getsize(os.path.join(OUT_AUDIO, n + '.ogg')) for n in man)
    print(f'{len(man)} clips -> {OUT_AUDIO} ({total / 1e6:.1f} MB)')


if __name__ == '__main__':
    main()
