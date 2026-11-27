"""Turn a Gif_Director frame folder into a README gif.

    py Scripts/Utilities/gif_build.py <frames_dir> <out.gif> [--fps 20] [--every 1]
        [--width 800] [--start 0] [--end N] [--hold-last 1.5] [--sheet sheet.png]

--every N keeps every Nth frame (20 fps capture, --every 2 = 10 fps gif).
--sheet writes a 3x3 contact sheet of the kept frames for a quick look.
"""
import argparse
import glob
import os

from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("frames")
    ap.add_argument("out")
    ap.add_argument("--fps", type=float, default=20.0)
    ap.add_argument("--every", type=int, default=1)
    ap.add_argument("--out-fps", type=float, default=0.0,
                    help="resample to this many fps by picking the nearest captured frame")
    ap.add_argument("--width", type=int, default=800)
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--end", type=int, default=-1)
    ap.add_argument("--hold-last", type=float, default=0.0)
    ap.add_argument("--colors", type=int, default=256)
    ap.add_argument("--sheet", default="")
    ap.add_argument("--squeeze", type=int, default=0,
                    help="cut still stretches: frames whose change is under this many pixels "
                         "(of a 240x135 grey thumbnail, diff > 25) are kept only up to --squeeze-keep in a row")
    ap.add_argument("--squeeze-keep", type=int, default=9)
    ap.add_argument("--fuzz", type=float, default=0.0,
                    help="RGB distance under which a pixel counts as unchanged (lossy; 0 = exact)")
    ap.add_argument("--hq", default="",
                    help="full-colour build through ffmpeg (imageio-ffmpeg) instead of the 128-colour "
                         "fuzzed palette: 'global' = one 256-colour palette from the whole clip, "
                         "'frame' = a fresh 256-colour palette every frame (best colour, biggest)")
    ap.add_argument("--crop", default="", help="x,y,w,h of each source frame to keep (zoom in), before --width")
    ap.add_argument("--dither", default="sierra2_4a", help="--hq dither: none, bayer, sierra2_4a, floyd_steinberg")
    a = ap.parse_args()

    files = sorted(glob.glob(os.path.join(a.frames, "f_*.png")) + glob.glob(os.path.join(a.frames, "f_*.jpg")))
    if a.end >= 0:
        files = files[: a.end]
    files = files[a.start :: a.every]
    if a.squeeze > 0:
        import numpy as np
        keep, run, prev = [], 0, None
        for f in files:
            g = np.asarray(Image.open(f).convert("L").resize((240, 135)), dtype=np.int16)
            act = 10**9 if prev is None else int((np.abs(g - prev) > 25).sum())
            prev = g
            run = run + 1 if act < a.squeeze else 0
            if run <= a.squeeze_keep:
                keep.append(f)
        files = keep
    if a.out_fps > 0:
        src = a.fps / a.every
        n = int(len(files) * a.out_fps / src)
        files = [files[min(len(files) - 1, round(i * src / a.out_fps))] for i in range(n)]
        a.fps, a.every = a.out_fps, 1
    if not files:
        raise SystemExit("no frames")

    frames = []
    for f in files:
        im = Image.open(f).convert("RGB")
        if a.crop:
            x, y, w, h = (int(v) for v in a.crop.split(","))
            im = im.crop((x, y, x + w, y + h))
        h = round(im.height * a.width / im.width)
        im = im.resize((a.width, h), Image.LANCZOS)
        frames.append(im)

    if a.sheet:
        n = len(frames)
        pick = [frames[int(i * (n - 1) / 8)] for i in range(9)]
        tw, th = 400, round(400 * frames[0].height / frames[0].width)
        sheet = Image.new("RGB", (tw * 3, th * 3))
        for k, im in enumerate(pick):
            sheet.paste(im.resize((tw, th)), ((k % 3) * tw, (k // 3) * th))
        sheet.save(a.sheet)

    if a.hq:
        _hq_build(frames, a)
        return

    # One palette for the whole gif (built from a strip of sampled frames), so a pixel
    # that did not change keeps the same index from frame to frame. Those pixels are
    # then written as transparent (disposal 1 keeps the frame below), which is what
    # makes mostly-still footage small.
    import numpy as np
    n = len(frames)
    sample = [frames[int(i * (n - 1) / 15)] for i in range(min(16, n))]
    strip = Image.new("RGB", (frames[0].width, frames[0].height * len(sample)))
    for k, im in enumerate(sample):
        strip.paste(im, (0, k * frames[0].height))
    ncol = min(a.colors, 255)
    palimg = strip.quantize(colors=ncol, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette = palimg.getpalette()[: ncol * 3]
    palette += [0, 0, 0] * (256 - ncol)
    TRANS = 255
    pal_rgb = np.array(palette, dtype=np.int32).reshape(256, 3)
    out = []
    shown = None   # the palette index each pixel currently DISPLAYS (after transparency)
    for im in frames:
        q = im.quantize(palette=palimg, dither=Image.Dither.NONE)
        idx = np.array(q, dtype=np.uint8)
        if shown is None:
            show = idx
            shown = idx.copy()
        else:
            if a.fuzz > 0:
                d = np.abs(pal_rgb[idx] - pal_rgb[shown]).sum(axis=2)
                same = d <= a.fuzz
            else:
                same = idx == shown
            show = idx.copy()
            show[same] = TRANS
            shown[~same] = idx[~same]
        p = Image.fromarray(show, mode="P")
        p.putpalette(palette)
        p.info["transparency"] = TRANS
        out.append(p)
    ms = round(1000 * a.every / a.fps)
    durations = [ms] * len(out)
    if a.hold_last > 0:
        durations[-1] = round(a.hold_last * 1000)
    out[0].save(a.out, save_all=True, append_images=out[1:], duration=durations,
                loop=0, optimize=False, disposal=1, transparency=TRANS)
    print(f"{a.out}: {len(out)} frames, {sum(durations)/1000:.1f}s, "
          f"{os.path.getsize(a.out)/1e6:.1f} MB")


def _hq_build(frames, a):
    """Full-colour gif: ffmpeg palettegen/paletteuse with error-diffusion dither, and only the
    changed rectangle of each frame stored (diff_mode=rectangle), so stills stay small without
    the fuzz smearing."""
    import shutil, subprocess, tempfile
    import imageio_ffmpeg
    tmp = tempfile.mkdtemp(prefix="gifhq_")
    for i, im in enumerate(frames):
        im.save(os.path.join(tmp, f"{i:05d}.png"), compress_level=1)
    fps = a.fps / a.every
    if a.hq == "frame":
        flt = (f"split[a][b];[a]palettegen=max_colors=256:stats_mode=single:reserve_transparent=1[p];"
               f"[b][p]paletteuse=new=1:dither={a.dither}:diff_mode=rectangle")
    else:
        flt = (f"split[a][b];[a]palettegen=max_colors=256:stats_mode=diff:reserve_transparent=1[p];"
               f"[b][p]paletteuse=dither={a.dither}:diff_mode=rectangle")
    cmd = [imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", str(fps),
           "-i", os.path.join(tmp, "%05d.png"), "-filter_complex", flt, "-loop", "0", a.out]
    subprocess.run(cmd, check=True)
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"{a.out}: {len(frames)} frames, {len(frames)/fps:.1f}s, {os.path.getsize(a.out)/1e6:.1f} MB")


if __name__ == "__main__":
    main()
