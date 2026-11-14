"""
Builds the talking-mouth frames for phone-call sprites, in the style of Ellie's old talking head.

    python make_talking_mouths.py              # build frames for every sprite in the config that has none yet
    python make_talking_mouths.py --force      # rebuild all of them
    python make_talking_mouths.py --preview    # also write mouth_preview.png (every sprite x every frame)
    python make_talking_mouths.py Olly_White   # only these sprites (implies --force for them)

Adding a sprite later:
  1. Put it in Talking_Sprites/Characters/<Character>/<Character>_<Outfit>.png
  2. Open it in any image editor, hover the MIDDLE of the closed mouth, and add its pixel position to
     talking_mouths.json:   "Olly/Olly_White": { "mouth": [410, 262], "pixel": 10 }
  3. Run this script. The frames land in Talking_Sprites/Mouths/.

Frames written per sprite (all on the sprite's OWN canvas, transparent except what changes, so the game
lays them over the sprite with no positioning at all):
    <stem>_Mouth_1.png      shut - fully transparent, the sprite's own closed mouth shows
    <stem>_Mouth_2.png      half open
    <stem>_Mouth_3.png      open
    <stem>_Sad_Mouth_1..3   the same for a [SAD] line: a flat mouth, then the frowning openings
The game plays them 1-2-3-2-1... while text is typing, so the mouth just moves up and down.

How a frame is made: the closed mouth (and its raised corner, if it has one) is painted over with the
surrounding skin, then the opening is stamped on, centred on the closed mouth. The openings are Ellie's
old talking-head mouths (TEMPLATES below, copied pixel for pixel from Ellie_Mouth_2/3 and
Ellie_Mouth_Sad_2/3), scaled so the old mouth line fits this sprite's closed mouth line.

Optional per-sprite keys in talking_mouths.json (only if the defaults look wrong):
  "pixel":  10      size of one art pixel on the canvas (auto-detected otherwise)
  "width":  3       closed-mouth width in art pixels (auto-detected otherwise)
  "scale":  0.75    size of the opening; 1.0 = the old talking head's size. Default: closed mouth width / 32
  "offset": [3, 0]  nudge the opening, in canvas pixels of the PNG as saved (+x = right in the file). Callers
                    are flipped in the call, so +x moves it LEFT on screen. Use it to keep it off a nose pixel.
  "open_down": true  pin the top of the opening to the top of the closed mouth, so it only opens downwards
                    (never rises into the nose). Off by default, which centres the opening on the mouth like
                    the old talking head.
  "corners": ["up_right"]  where to look for a raised mouth-corner pixel ([] = none, "up_left" too)
Needs Pillow and numpy:  pip install pillow numpy
"""
from __future__ import annotations
import json, sys
from collections import Counter
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
# Talking_Sprites folder: next to this script's project root by default; override with --root.
DEFAULT_ROOT = HERE.parent.parent / "Image_Assets" / "Character_Sprites" / "Talking_Sprites"
CONFIG = HERE / "talking_mouths.json"

# ── the openings ─────────────────────────────────────────────────────────────
# Ellie's old talking-head mouths, one character per canvas pixel: # = inside of the mouth, p = tongue,
# . = untouched. On the old head the closed mouth line was 32 px wide and 8 px tall, and it sits at
# TEMPLATE_ANCHOR (the middle of that line) in these grids - that point goes on the sprite's own mouth.
INSIDE = (0, 0, 0)
TONGUE = (255, 174, 201)
OLD_LINE_WIDTH = 32.0
TEMPLATE_ANCHOR = (25.0, 12.0)
TEMPLATES = {
    "half": [
        "..................................................",
        "..................................................",
        "..................................................",
        "..................................................",
        "..................................................",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".....########################################.....",
        ".....#############pppppppppppppp#############.....",
        ".....##########pppppppppppppppppppp##########.....",
        ".....##########pppppppppppppppppppp##########.....",
        ".........pppppppppppppppppppppppppppppppp.........",
        ".........pppppppppppppppppppppppppppppppp.........",
        "..............ppppppppppppppppppppppp.............",
        "..............ppppppppppppppppppppppp.............",
        "..................................................",
        "..................................................",
        "..................................................",
        "..................................................",
    ],
    "open": [
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".################################################.",
        ".....#############pppppppppppppp#############.....",
        ".....#############pppppppppppppp#############.....",
        ".....##########pppppppppppppppppppp##########.....",
        ".....##########pppppppppppppppppppp##########.....",
        ".........pppppppppppppppppppppppppppppppp.........",
        ".........pppppppppppppppppppppppppppppppp.........",
        ".........pppppppppppppppppppppppppppppppp.........",
        "..............ppppppppppppppppppppppp.............",
        "..............ppppppppppppppppppppppp.............",
        "..............ppppppppppppppppppppppp.............",
        "..............ppppppppppppppppppppppp.............",
        "..................................................",
    ],
    "sad_half": [
        "..................................................",
        "..................................................",
        "..................................................",
        "..................................................",
        "..................................................",
        "..................................................",
        ".....#######################################......",
        ".....#######################################......",
        ".....#######################################......",
        ".....#######################################......",
        "################################################..",
        "#################pppppppppppppp#################..",
        "#################pppppppppppppp#################..",
        "##############pppppppppppppppppppp##############..",
        "##############pppppppppppppppppppp##############..",
        "########pppppppppppppppppppppppppppppppp########..",
        "########pppppppppppppppppppppppppppppppp########..",
        "########pppppppppppppppppppppppppppppppp########..",
        "..................................................",
        "..................................................",
        "..................................................",
        "..................................................",
    ],
    "sad_open": [
        "..................................................",
        "........################################..........",
        "........################################..........",
        "........################################..........",
        "........################################..........",
        "....########################################......",
        "....########################################......",
        "....########################################......",
        "....########################################......",
        "################################################..",
        "################################################..",
        "#################pppppppppppppp#################..",
        "#################pppppppppppppp#################..",
        "##############pppppppppppppppppppp##############..",
        "##############pppppppppppppppppppp##############..",
        "########pppppppppppppppppppppppppppppppp########..",
        "########pppppppppppppppppppppppppppppppp########..",
        "########pppppppppppppppppppppppppppppppp########..",
        ".............ppppppppppppppppppppppp..............",
        ".............ppppppppppppppppppppppp..............",
        ".............ppppppppppppppppppppppp..............",
        ".............ppppppppppppppppppppppp..............",
    ],
}
# file suffix -> (what the closed mouth becomes, template stamped on top or None)
#   "all" erases the mouth line and its corner, "corner" only the raised corner (a flat, sad mouth)
SETS = {
    "Mouth":     [(None, None), ("all", "half"), ("all", "open")],
    "Sad_Mouth": [("corner", None), ("all", "sad_half"), ("all", "sad_open")],
}


# ── grid ─────────────────────────────────────────────────────────────────────
def _boundaries(a: np.ndarray, axis: int) -> np.ndarray:
    if axis == 1:
        d = np.any(a[:, 1:] != a[:, :-1], axis=(0, 2))
    else:
        d = np.any(a[1:] != a[:-1], axis=(1, 2))
    return np.where(d)[0] + 1


def detect_grid(a: np.ndarray, mx: int, my: int, pixel: int | None):
    """(pixel size, x offset, y offset): canvas x belongs to art column (x - ox) // p."""
    H, W = a.shape[:2]
    win = a[max(0, my - 80):min(H, my + 80), max(0, mx - 80):min(W, mx + 80)]
    x0, y0 = max(0, mx - 80), max(0, my - 80)
    bx = _boundaries(win, 1) + x0
    by = _boundaries(win, 0) + y0

    def best_offset(b, p):
        tol = 1 if p >= 6 else 0
        scores = []
        for o in range(p):
            r = (b - o) % p
            hit = np.minimum(r, p - r) <= tol
            exact = (r == 0).sum()
            scores.append((hit.mean() if len(b) else 0, exact, o))
        s, _, o = max(scores)
        return s, o

    if pixel is None:
        pixel = 1
        for p in range(16, 1, -1):
            sx, _ = best_offset(bx, p)
            sy, _ = best_offset(by, p)
            if min(sx, sy) >= 0.9:
                pixel = p
                break
    _, ox = best_offset(bx, pixel)
    _, oy = best_offset(by, pixel)
    return pixel, ox, oy


class Grid:
    def __init__(self, a, p, ox, oy):
        self.a, self.p, self.ox, self.oy = a.astype(int), p, ox, oy
        self.cache = {}

    def cell(self, c, r):
        if (c, r) not in self.cache:
            H, W = self.a.shape[:2]
            x0, y0 = c * self.p + self.ox, r * self.p + self.oy
            blk = self.a[max(0, y0):min(H, y0 + self.p), max(0, x0):min(W, x0 + self.p)].reshape(-1, 4)
            if len(blk) == 0:
                self.cache[(c, r)] = np.array([0, 0, 0, 0])
            else:
                v, n = np.unique(blk, axis=0, return_counts=True)
                self.cache[(c, r)] = v[n.argmax()]
        return self.cache[(c, r)]

    def at(self, x, y):
        return (x - self.ox) // self.p, (y - self.oy) // self.p


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


# ── the closed mouth ─────────────────────────────────────────────────────────
def find_mouth(g: Grid, mx, my, width):
    c, r = g.at(mx, my)
    m = g.cell(c, r)
    if width:
        c0 = c - (width - 1) // 2
        return r, list(range(c0, c0 + width))
    cols = [c]
    while (g.cell(cols[0] - 1, r) == m).all() and len(cols) < 6:
        cols.insert(0, cols[0] - 1)
    while (g.cell(cols[-1] + 1, r) == m).all() and len(cols) < 6:
        cols.append(cols[-1] + 1)
    return r, cols


def face_skin(g: Grid, r, cols):
    """Most common light, opaque colour around the mouth - what the closed mouth is erased to."""
    cnt = Counter()
    for rr in (r - 1, r, r + 1):
        for cc in range(cols[0] - 2, cols[-1] + 3):
            if rr == r and cc in cols:
                continue
            v = tuple(int(x) for x in g.cell(cc, rr))
            if v[3] == 255 and lum(v) > 110:
                cnt[v[:3]] += 1
    return cnt.most_common(1)[0][0]


def corner_cells(g: Grid, r, cols, skin, corners):
    """The mouth's raised corner: a single pixel diagonally above an end of the mouth line, darker than
    the skin round it (Alexander and Ellie both have one, up and to the right). Only up-right by
    default - up-left of a mouth is often the nose."""
    found = []
    for where in corners:
        c, rr = (cols[-1] + 1, r - 1) if where == "up_right" else (cols[0] - 1, r - 1)
        v = tuple(int(x) for x in g.cell(c, rr))
        if v[3] == 255 and v[:3] != skin and lum(v) < lum(skin) - 10 and lum(v) > 70:
            found.append((c, rr))
    return found


# ── rendering ────────────────────────────────────────────────────────────────
def render(g: Grid, shape: dict) -> np.ndarray:
    """Overlay that repaints whole art pixels ({(col, row): rgb}), keeping any resampling blend columns
    between neighbours correct."""
    a = g.a
    H, W = a.shape[:2]
    ov = np.zeros((H, W, 4), np.uint8)
    if not shape:
        return ov
    p, ox, oy = g.p, g.ox, g.oy

    def new(c, r):
        if (c, r) in shape:
            return np.array(list(shape[(c, r)]) + [255])
        return g.cell(c, r)

    cells = set(shape)
    cs = [c for c, _ in cells]
    rs = [r for _, r in cells]
    x0 = max(0, (min(cs) - 1) * p + ox); x1 = min(W, (max(cs) + 2) * p + ox)
    y0 = max(0, (min(rs) - 1) * p + oy); y1 = min(H, (max(rs) + 2) * p + oy)
    for y in range(y0, y1):
        for x in range(x0, x1):
            px = a[y, x]
            c, r = (x - ox) // p, (y - oy) // p
            cand = [(c + i, r + j) for j in (0, -1, 1) for i in (0, -1, 1)]
            if not any(k in cells for k in cand):
                continue
            if (c, r) in cells and p == 1:
                q = new(c, r)
            else:
                hit = next((k for k in cand if (g.cell(*k) == px).all()), None)
                if hit is not None:
                    q = new(*hit)
                else:  # a resampling blend between two neighbours: keep its mix ratio
                    best = None
                    for A in cand:
                        for B in cand:
                            if A >= B:
                                continue
                            va, vb = g.cell(*A), g.cell(*B)
                            dv = vb - va
                            den = (dv * dv).sum()
                            if den == 0:
                                continue
                            t = np.clip(((px - va) * dv).sum() / den, 0, 1)
                            err = np.abs(va + t * dv - px).sum()
                            if best is None or err < best[0]:
                                best = (err, A, B, t)
                    if best is None:
                        continue
                    _, A, B, t = best
                    q = np.round(new(*A) * (1 - t) + new(*B) * t).astype(int)
            if not (q == px).all():
                ov[y, x] = np.clip(q, 0, 255)
    return ov


def stamp(img: np.ndarray, template: list[str], cx: float, cy: float, s: float):
    """Paints a template onto img (in place), its anchor on canvas point (cx, cy), scaled by s,
    nearest-neighbour so the old mouth's hard pixel edges stay hard."""
    H, W = img.shape[:2]
    th, tw = len(template), len(template[0])
    ax, ay = TEMPLATE_ANCHOR
    for y in range(int(cy - ay * s) - 1, int(cy + (th - ay) * s) + 2):
        ty = int(np.floor((y + 0.5 - cy) / s + ay))
        if not (0 <= ty < th) or not (0 <= y < H):
            continue
        for x in range(int(cx - ax * s) - 1, int(cx + (tw - ax) * s) + 2):
            tx = int(np.floor((x + 0.5 - cx) / s + ax))
            if not (0 <= tx < tw) or not (0 <= x < W):
                continue
            ch = template[ty][tx]
            if ch == "#":
                img[y, x] = list(INSIDE) + [255]
            elif ch == "p":
                img[y, x] = list(TONGUE) + [255]


def build(root: Path, key: str, cfg: dict, preview_rows: list | None):
    src = root / "Characters" / f"{key}.png"
    stem = Path(key).name
    if not src.exists():
        print(f"  !! {key}: no sprite at {src}")
        return False
    a = np.array(Image.open(src).convert("RGBA"))
    mx, my = cfg["mouth"]
    p, ox, oy = detect_grid(a, mx, my, cfg.get("pixel"))
    g = Grid(a, p, ox, oy)
    r, cols = find_mouth(g, mx, my, cfg.get("width"))
    if g.cell(cols[0], r)[3] == 0:
        print(f"  !! {key}: the mouth point {cfg['mouth']} is on a transparent pixel")
        return False
    skin = face_skin(g, r, cols)
    corners = corner_cells(g, r, cols, skin, cfg.get("corners", ["up_right"]))
    erase = {
        "all": {**{(c, r): skin for c in cols}, **{k: skin for k in corners}},
        "corner": {k: skin for k in corners},
    }
    # the middle of the closed mouth line, in canvas pixels
    cx = ((cols[0] + cols[-1] + 1) / 2.0) * p + ox
    cy = (r + 0.5) * p + oy
    s = float(cfg.get("scale", len(cols) * p / OLD_LINE_WIDTH))
    dx, dy = cfg.get("offset", [0, 0])
    cx += dx
    cy += dy
    line_top = r * p + oy + dy
    open_down = bool(cfg.get("open_down", False))

    def anchor_y(tmpl: str) -> float:
        """Where the template's anchor goes. With open_down, the top of the opening sits exactly on the
        top of the closed mouth, so the mouth only ever opens DOWNWARDS and never rises into the nose."""
        if not open_down:
            return cy
        rows = TEMPLATES[tmpl]
        first = next(i for i, row in enumerate(rows) if row.strip("."))
        return line_top + (TEMPLATE_ANCHOR[1] - first) * s

    out_dir = root / "Mouths"
    out_dir.mkdir(parents=True, exist_ok=True)
    frames = []
    for suffix, recipe in SETS.items():
        for i, (wipe, tmpl) in enumerate(recipe, 1):
            ov = render(g, erase[wipe]) if wipe else np.zeros_like(a)
            if tmpl:
                img = a.copy()
                m = ov[:, :, 3] > 0
                img[m] = ov[m]
                stamp(img, TEMPLATES[tmpl], cx, anchor_y(tmpl), s)
                diff = np.any(img != a, axis=2)
                ov = np.zeros_like(a)
                ov[diff] = img[diff]
            Image.fromarray(ov).save(out_dir / f"{stem}_{suffix}_{i}.png")
            frames.append(ov)
        # a set is read until the first missing number, so stale higher frames would join the cycle
        n = len(recipe) + 1
        while (out_dir / f"{stem}_{suffix}_{n}.png").exists():
            (out_dir / f"{stem}_{suffix}_{n}.png").unlink()
            imp = out_dir / f"{stem}_{suffix}_{n}.png.import"
            if imp.exists():
                imp.unlink()
            print(f"  {stem}: removed old frame {stem}_{suffix}_{n}.png")
            n += 1
    print(f"  {stem}: art pixel {p}px, closed mouth {len(cols)} art px at art row {r}"
          f"{' + raised corner' if corners else ''}, opening scale {s:.2f} -> 3 frames + 3 sad")
    if preview_rows is not None:
        preview_rows.append((stem, a, frames, (cx, cy, p)))
    return True


def write_preview(rows, path):
    S = 220
    n = max(len(f) for _, _, f, _ in rows)
    sheet = Image.new("RGB", (n * (S + 6) + 140, len(rows) * (S + 6)), (230, 230, 230))
    from PIL import ImageDraw
    d = ImageDraw.Draw(sheet)
    for j, (stem, a, frames, (cx, cy, p)) in enumerate(rows):
        half = 6 * p
        box = (int(cx - half), int(cy - half * 1.2), int(cx + half), int(cy + half * 0.8))
        d.text((6, j * (S + 6) + S // 2), stem, fill=(0, 0, 0))
        for i, ov in enumerate(frames):
            im = Image.fromarray(a.copy())
            im.alpha_composite(Image.fromarray(ov))
            bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
            bg.alpha_composite(im)
            sheet.paste(bg.crop(box).resize((S, S), Image.NEAREST), (140 + i * (S + 6), j * (S + 6)))
    sheet.save(path)
    print(f"preview: {path}")


def main(argv):
    root = DEFAULT_ROOT
    if "--root" in argv:
        root = Path(argv[argv.index("--root") + 1]); del argv[argv.index("--root"):argv.index("--root") + 2]
    force = "--force" in argv
    preview = "--preview" in argv
    only = [x for x in argv if not x.startswith("--")]
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    rows = [] if preview else None
    for key, cfg in config.items():
        if key.startswith("_"):
            continue
        stem = Path(key).name
        if only and stem not in only and key not in only:
            continue
        if not force and not only and (root / "Mouths" / f"{stem}_Mouth_1.png").exists() and not preview:
            print(f"  {stem}: already has mouths (use --force to rebuild)")
            continue
        build(root, key, cfg, rows)
    if preview and rows:
        write_preview(rows, HERE / "mouth_preview.png")


if __name__ == "__main__":
    main(sys.argv[1:])
