"""League Points icon: a purple coin carrying the Pokemon TCG Legacy mark (dashes, full diamond, dark/light chevron).
Run: python Scripts/Utilities/league_icon_build.py  ->  Image_Assets/Icons/Reward_Icons/league_points_icon.png (170x170)
The mark's shading is folded into the coin's gradient: the upper chevron takes the deep end, the diamond and lower
chevron the light end, the dashes in between."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Image_Assets", "Icons", "Reward_Icons", "league_points_icon.png")
S = 170
SS = 4
N = S * SS

# the mark, from the logo (x 15..712, y 82..530)
DIAMOND = [(341, 193), (454, 306), (341, 418), (228, 306)]
TOP = [(367, 82), (590, 303), (480, 303), (367, 190)]
BOTTOM = [(480, 308), (590, 308), (367, 530), (367, 418)]
DASH_L = [(15, 306), (23, 301), (135, 301), (128, 306), (135, 311), (23, 311)]
DASH_R = [(593, 306), (601, 301), (705, 301), (712, 306), (705, 311), (601, 311)]

LIGHT = (240, 230, 255, 255)
MID = (190, 160, 240, 255)
DEEP = (52, 20, 118, 255)


def main():
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = cy = N / 2
    R = N * 0.47
    # coin: radial purple gradient, lit from the upper left
    for i in range(int(R), 0, -2):
        t = i / R
        col = (int(70 + 120 * (1 - t) * 0.9), int(25 + 60 * (1 - t)), int(150 + 80 * (1 - t)), 255)
        off = (1 - t) * N * 0.07
        d.ellipse([cx - i - off, cy - i - off, cx + i - off, cy + i - off], fill=col)
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=(36, 12, 86, 255), width=int(N * 0.035))
    d.ellipse([cx - R * 0.86, cy - R * 0.86, cx + R * 0.86, cy + R * 0.86], outline=(200, 160, 255, 200), width=int(N * 0.012))
    # the mark, centred and scaled to ~76% of the coin's width
    k = (2 * R * 0.86) / 697.0
    mx, my = 363.5, 306.0

    def P(pts):
        return [(cx + (x - mx) * k, cy + (y - my) * k) for x, y in pts]

    for poly, col in ((DASH_L, MID), (DASH_R, MID), (BOTTOM, LIGHT), (DIAMOND, LIGHT), (TOP, DEEP)):
        pts = P(poly)
        d.polygon(pts, fill=col)
        d.line(pts + [pts[0]], fill=(30, 8, 70, 255), width=int(N * 0.006), joint="curve")
    im = im.resize((S, S), Image.LANCZOS)
    im.save(OUT)
    bg = Image.new("RGB", (190, 190), (40, 48, 58))
    bg.paste(im, (10, 10), im)
    bg.save(os.path.join(ROOT, "audit_out", "lp_icon.png"))
    print("saved", OUT)


main()
