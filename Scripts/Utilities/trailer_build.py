"""Cut a trailer from Gif_Director frame folders.

    py -3 -I Scripts/Utilities/trailer_build.py <timeline.json> <out.mp4>

timeline.json:
{
  "fps": 30, "size": [1280, 720], "font": "UI_Themes/ChakraPetch-Bold.ttf",
  "music": "Audio/BGM/x.ogg", "music_start": 0, "xfade": 0.4,
  "segments": [
    {"frames": "C:/rec/battle", "start": 120, "dur": 6.0,
     "zoom": [1.0, 1.12], "focus": [0.5, 0.5],          # slow push-in toward focus (0-1)
     "caption": "Purpose built CPU battle system"},
    {"card": "Image_Assets/Intro_And_Splash_Screen/white_logo_only.png", "dur": 4.0,
     "caption": "", "sub": "Coming soon"}                 # logo card on a dark background
  ]
}
Every segment is rendered on its own, then they are joined with crossfades and the music
laid under the whole thing (faded in and out). Needs imageio-ffmpeg.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()


def run(args, cwd):
    r = subprocess.run([FF, "-y", "-loglevel", "error"] + args, cwd=cwd)
    if r.returncode != 0:
        sys.exit("ffmpeg failed: " + " ".join(args))


def caption_filters(seg, W, H, dur, work, idx):
    out = []
    cap = seg.get("caption", "")
    sub = seg.get("sub", "")
    if cap:
        with open(os.path.join(work, f"cap{idx}.txt"), "w", encoding="utf-8") as f:
            f.write(cap)
        # A soft band under the text, then the text slides in from the left with an ease-out
        # and fades away just before the cut.
        band_y = int(H * 0.72) if not seg.get("card") else int(H * 0.70)
        out.append(f"drawbox=x=0:y={band_y}:w={W}:h={int(H*0.16)}:color=black@0.45:t=fill:enable='between(t,0.15,{dur-0.25})'")
        slide = 0.45
        x = (f"if(lt(t-0.15,{slide}),(w-tw)/2-(w/2+tw)*pow(1-max(t-0.15,0)/{slide},3),(w-tw)/2)")
        alpha = f"if(lt(t,{dur-0.6}),1,max(0,({dur-0.25}-t)/0.35))"
        out.append(f"drawtext=fontfile=font.ttf:textfile=cap{idx}.txt:fontsize={int(H*0.075)}:fontcolor=white"
                   f":borderw=3:bordercolor=black@0.8:x='{x}':y={band_y}+({int(H*0.16)}-th)/2"
                   f":alpha='{alpha}':enable='gte(t,0.15)'")
    if sub:
        with open(os.path.join(work, f"sub{idx}.txt"), "w", encoding="utf-8") as f:
            f.write(sub)
        out.append(f"drawtext=fontfile=font.ttf:textfile=sub{idx}.txt:fontsize={int(H*0.05)}:fontcolor={seg.get('subcolor', 'white')}"
                   f":x=(w-tw)/2:y={int(H*0.80)}:alpha='min(1,max(0,(t-0.6)/0.5))'")
    return out


def render_segment(seg, cfg, work, idx):
    W, H = cfg["size"]
    fps = cfg["fps"]
    dur = float(seg["dur"])
    n = int(round(dur * fps))
    z0, z1 = seg.get("zoom", [1.0, 1.0])
    fx, fy = seg.get("focus", [0.5, 0.5])
    out = f"seg{idx}.mp4"
    if seg.get("card"):
        # Logo on a dark gradient-ish background, gently growing.
        # Pre-scaled with Pillow: ffmpeg's png path dropped the logo's alpha.
        from PIL import Image
        lw = int(W * seg.get("logo_w", 0.62))
        logo = Image.open(seg["card"]).convert("RGBA")
        logo = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
        logo.save(os.path.join(work, f"card{idx}.png"))
        inputs = ["-f", "lavfi", "-i", f"color=c={seg.get('bg', '0x101425')}:s={W}x{H}:r={fps}:d={dur}", "-loop", "1", "-framerate", str(fps), "-i", f"card{idx}.png"]
        f = [f"[0:v][1:v]overlay=x=(W-w)/2:y=(H-h)/2-{int(H*0.06)}:format=auto:shortest=1,"
             f"zoompan=z='1+0.06*on/{max(n-1,1)}':x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2':d=1:s={W}x{H}:fps={fps}[v0]"]
        chain = caption_filters(seg, W, H, dur, work, idx)
        last = "v0"
        if chain:
            f.append(f"[v0]{','.join(chain)}[v1]")
            last = "v1"
        run(inputs + ["-filter_complex", ";".join(f), "-map", f"[{last}]", "-frames:v", str(n),
                      "-pix_fmt", "yuv420p", "-c:v", "libx264", "-crf", "20", "-r", str(fps), out], work)
        return out
    frames = seg["frames"]
    ext = seg.get("ext") or ("jpg" if any(p.endswith(".jpg") for p in os.listdir(frames)[:5]) else "png")
    # Upscale 2x before zoompan so the slow push-in does not judder on whole pixels.
    zexpr = f"{z0}+({z1}-{z0})*on/{max(n-1,1)}"
    zp = (f"scale={W*2}:{H*2},zoompan=z='{zexpr}':x='(iw-iw/zoom)*{fx}':y='(ih-ih/zoom)*{fy}'"
          f":d=1:s={W}x{H}:fps={fps}")
    chain = [zp] + caption_filters(seg, W, H, dur, work, idx)
    run(["-framerate", str(seg.get("src_fps", fps)), "-start_number", str(seg.get("start", 0)),
         "-i", os.path.join(frames, f"f_%05d.{ext}"), "-vf", ",".join(chain), "-frames:v", str(n),
         "-pix_fmt", "yuv420p", "-c:v", "libx264", "-crf", "20", "-r", str(fps), out], work)
    return out


def main():
    tl_path, out_path = sys.argv[1], os.path.abspath(sys.argv[2])
    cfg = json.load(open(tl_path, encoding="utf-8"))
    cfg.setdefault("fps", 30)
    cfg.setdefault("size", [1280, 720])
    xf = float(cfg.get("xfade", 0.4))
    work = tempfile.mkdtemp(prefix="trailer_")
    shutil.copy(cfg.get("font", "UI_Themes/ChakraPetch-Bold.ttf"), os.path.join(work, "font.ttf"))
    segs = cfg["segments"]
    files = []
    for i, s in enumerate(segs):
        print(f"segment {i+1}/{len(segs)}: {s.get('caption') or s.get('card') or s.get('frames')}")
        files.append(render_segment(s, cfg, work, i))
    # Join with crossfades (each one eats `xf` seconds of overlap).
    inputs = []
    for f in files:
        inputs += ["-i", f]
    fl = []
    prev = "0:v"
    t = float(segs[0]["dur"])
    for i in range(1, len(files)):
        off = t - xf
        lab = f"x{i}"
        trans = segs[i].get("transition", "fade")
        fl.append(f"[{prev}][{i}:v]xfade=transition={trans}:duration={xf}:offset={off:.3f}[{lab}]")
        prev = lab
        t = off + float(segs[i]["dur"])
    total = t
    fl.append(f"[{prev}]fade=t=in:st=0:d=0.5,fade=t=out:st={total-0.8:.3f}:d=0.8[vout]")
    amap = []
    if cfg.get("music"):
        shutil.copy(cfg["music"], os.path.join(work, "music" + os.path.splitext(cfg["music"])[1]))
        inputs += ["-ss", str(cfg.get("music_start", 0)), "-i", "music" + os.path.splitext(cfg["music"])[1]]
        a = len(files)
        fl.append(f"[{a}:a]atrim=0:{total:.3f},afade=t=in:st=0:d=1,afade=t=out:st={total-2:.3f}:d=2,volume={cfg.get('volume', 0.8)}[aout]")
        amap = ["-map", "[aout]", "-c:a", "aac", "-b:a", "160k"]
    run(inputs + ["-filter_complex", ";".join(fl), "-map", "[vout]"] + amap +
        ["-pix_fmt", "yuv420p", "-c:v", "libx264", "-crf", "20", "-movflags", "+faststart", out_path], work)
    shutil.rmtree(work, ignore_errors=True)
    print(f"wrote {out_path} ({total:.1f}s)")


if __name__ == "__main__":
    main()
