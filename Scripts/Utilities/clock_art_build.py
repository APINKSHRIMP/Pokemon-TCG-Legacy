#!/usr/bin/env python3
"""Builds the overworld clock art into Image_Assets/Clock/. Source of truth for every PNG there.

    py Scripts/Utilities/clock_art_build.py [preview.png]

Layers, all pixel-aligned, bottom to top (Overworld_Clock.gd stacks them the same way):
  Clock_Face_<Slot>.png   face colour and scenery (one per time slot, 52x52)
  Clock_Dots.png          the 12 white hour dots
  Clock_Icon_<Slot>.png   sunrise / sun + cloud / sunset / crescent / full moon
  Clock_Hand.png          120 pre-drawn hand angles (12 x 10 sheet of 52x52 cells, one per
                          3 degrees = one time point), frame 0 pointing at 12, going clockwise
  Clock_Glyphs.png        0-9 a p m as 9x11 cells, each with its own dark outline
  Clock_Frame.png         the metal ring, on top of everything

A drawn hand rather than a rotated sprite: rotating pixel art at run time smears it.
"""
import math
import os
import sys

from PIL import Image

SIZE = 52
C = (SIZE - 1) / 2.0  # the centre falls between pixels, so the dots stay symmetrical

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Image_Assets", "Clock")

NAVY = (16, 18, 58, 255)

# Face: (top, middle, bottom) colour per slot. TWEAKABLE - the clock's slot colours.
FACES = {
    "Morning":   ((163, 224, 247), (136, 208, 240), (112, 191, 232)),
    "Afternoon": ((64, 146, 245), (43, 122, 235), (30, 101, 218)),
    "Evening":   ((206, 98, 78), (182, 76, 78), (146, 60, 84)),
    "Night":     ((66, 76, 150), (56, 65, 134), (47, 55, 118)),
    "Bedtime":   ((29, 32, 86), (24, 27, 74), (19, 21, 62)),
}


def blank():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def polar(x, y):
    dx, dy = x - C, y - C
    return math.hypot(dx, dy), math.atan2(dy, dx), dx, dy


def put(img, x, y, col):
    """Coordinates relative to the centre, in whole pixels (0,0 = just right of and below it)."""
    px, py = int(round(C - 0.5 + x)), int(round(C - 0.5 + y))
    if 0 <= px < SIZE and 0 <= py < SIZE:
        img.putpixel((px, py), col if len(col) == 4 else col + (255,))


def disc(img, cx, cy, r, col, clip=None):
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x - C, y - C
            if (dx - cx) ** 2 + (dy - cy) ** 2 <= r * r and (clip is None or clip(dx, dy)):
                img.putpixel((x, y), col if len(col) == 4 else col + (255,))


# ---------------------------------------------------------------- frame
RING_OUTLINE = 25.9
RING_OUTER = 25.0
RING_GROOVE = 23.1
RING_INNER = 22.1
RING_LIP = 20.9
GREYS = [(44, 46, 66), (74, 77, 96), (108, 112, 130), (146, 150, 166), (186, 190, 204), (226, 229, 238), (250, 251, 255)]


def grey(level):
    return GREYS[max(0, min(len(GREYS) - 1, int(round(level))))] + (255,)


def build_frame():
    img = blank()
    light = math.radians(-125)  # top-left, slightly up
    for y in range(SIZE):
        for x in range(SIZE):
            r, a, _, _ = polar(x, y)
            lit = math.cos(a - light)  # 1 facing the light, -1 away from it
            if r > RING_OUTLINE:
                continue
            if r > RING_OUTER:
                img.putpixel((x, y), NAVY)
            elif r > RING_GROOVE:
                # Outer band: bright crown, with a hard glint across the top-left.
                level = 3.2 + 2.0 * lit + (1.0 if r > 24.1 else 0.0)
                if abs(a - light) < 0.22:
                    level = 6
                img.putpixel((x, y), grey(level))
            elif r > RING_INNER:
                img.putpixel((x, y), grey(0.6 + 0.8 * lit))   # the machined groove
            elif r > RING_LIP:
                img.putpixel((x, y), grey(3.2 - 2.2 * lit))   # inner band: lit the opposite way
            elif r > RING_LIP - 1.0:
                img.putpixel((x, y), NAVY)
    return img


# ---------------------------------------------------------------- faces
def build_face(slot):
    img = blank()
    top, mid, bot = FACES[slot]
    for y in range(SIZE):
        for x in range(SIZE):
            r, _, _, dy = polar(x, y)
            if r > RING_LIP + 0.5:
                continue
            t = (dy + RING_LIP) / (2 * RING_LIP)
            # Three flat bands with a checker dither on the seams, not a smooth gradient.
            band = t * 3.0
            i = int(band)
            frac = band - i
            if frac > 0.72 and (x + y) % 2 == 0:
                i += 1
            col = (top, mid, bot, bot)[min(i, 3)]
            # A soft shadow under the rim along the top.
            if r > RING_LIP - 2.4 and dy < 0:
                col = tuple(int(c * 0.82) for c in col)
            img.putpixel((x, y), col + (255,))

    if slot == "Morning":
        for cx, cy, w in [(-13, 2, 3), (12, 0, 2)]:
            cloud(img, cx, cy, w, (240, 250, 255), (200, 228, 244))
    elif slot == "Afternoon":
        for cx, cy, w in [(-13, 1, 3), (13, -2, 2)]:
            cloud(img, cx, cy, w, (255, 255, 255), (178, 212, 246))
    elif slot == "Evening":
        for cx, cy, w in [(-13, 1, 3), (13, -1, 2)]:
            cloud(img, cx, cy, w, (240, 158, 116), (156, 66, 92))
    elif slot == "Night":
        for sx, sy, col in [(-13, -5, (240, 214, 130)), (13, -7, (240, 214, 130)), (-12, 3, (150, 158, 214)), (14, 2, (150, 158, 214))]:
            put(img, sx, sy, col)
    elif slot == "Bedtime":
        for sx, sy, col in [(-14, -4, (214, 214, 240)), (13, -8, (240, 214, 130)), (-11, 2, (118, 124, 186)),
                            (14, 1, (240, 214, 130)), (-9, -13, (118, 124, 186)), (11, 4, (118, 124, 186)),
                            (-14, 4, (118, 124, 186))]:
            put(img, sx, sy, col)
    return img


def cloud(img, cx, cy, w, hi, lo):
    for x in range(-w, w + 1):
        put(img, cx + x, cy, lo)
        if abs(x) < w:
            put(img, cx + x, cy - 1, hi)
    put(img, cx, cy - 2, hi)


# ---------------------------------------------------------------- dots
def build_dots():
    img = blank()
    ring = 17.6
    for h in range(12):
        a = math.radians(h * 30 - 90)
        x = C + ring * math.cos(a)
        y = C + ring * math.sin(a)
        px, py = int(round(x - 0.5)), int(round(y - 0.5))
        for oy in (0, 1):
            for ox in (0, 1):
                img.putpixel((px + ox, py + oy), (255, 255, 255, 255))
        # A faint drop shadow so white reads on the pale Morning face.
        for ox in (0, 1):
            if img.getpixel((px + ox, py + 2))[3] == 0:
                img.putpixel((px + ox, py + 2), (16, 18, 58, 90))
    return img


# ---------------------------------------------------------------- icons
def icon_morning():
    img = blank()
    horizon = -4.0
    above = lambda dx, dy: dy < horizon
    disc(img, 0, horizon, 6.4, (255, 176, 58), above)
    disc(img, -1, horizon - 1, 4.2, (255, 214, 92), above)
    disc(img, -2, horizon - 2.5, 1.6, (255, 244, 176), above)
    for deg in (-150, -120, -90, -60, -30):
        a = math.radians(deg)
        for r in (8.2, 9.2):
            put(img, 0.5 + r * math.cos(a), horizon + 0.5 + r * math.sin(a), (255, 200, 80))
    for x in range(-10, 11):
        put(img, x + 0.5, horizon + 0.5, (255, 244, 200))
    for x in range(-6, 7):
        put(img, x + 0.5, horizon + 2.5, (240, 250, 255))
    return img


def icon_afternoon():
    img = blank()
    cx, cy = 2.0, -9.0
    disc(img, cx, cy, 4.3, (255, 186, 44))
    disc(img, cx - 0.6, cy - 0.6, 3.0, (255, 222, 90))
    disc(img, cx - 1.4, cy - 1.4, 1.0, (255, 248, 196))
    for i in range(8):
        a = math.radians(i * 45)
        put(img, cx + 0.5 + 6.2 * math.cos(a), cy + 0.5 + 6.2 * math.sin(a), (255, 214, 92))
    # A plump cloud across the sun's lower left.
    lo, hi = (186, 212, 240), (255, 255, 255)
    for dx, dy, r, col in [(-7, -3, 2.6, lo), (-3.5, -4, 3.4, lo), (0.5, -3, 2.6, lo),
                           (-7, -3.7, 2.2, hi), (-3.5, -4.8, 3.0, hi), (0.5, -3.7, 2.2, hi)]:
        disc(img, dx, dy, r, col)
    return img


def icon_evening():
    img = blank()
    horizon = -2.0
    def body(dx, dy):
        return dy < horizon
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x - C, y - C
            if dx * dx + (dy - horizon) ** 2 <= 8.2 ** 2 and body(dx, dy):
                # Yellow at the crown to deep orange at the waterline, with retro cut lines.
                t = (dy - (horizon - 8.2)) / 8.2
                col = (255, 226, 110) if t < 0.3 else (255, 176, 64) if t < 0.62 else (242, 104, 54)
                if t > 0.55 and int(round(dy)) % 2 == 0:
                    col = (196, 70, 66)
                img.putpixel((x, y), col + (255,))
    for x in range(-11, 12):
        put(img, x + 0.5, horizon + 0.5, (96, 36, 76))
    for x in range(-6, 7):
        put(img, x + 0.5, horizon + 2.5, (246, 142, 92))
    return img


def icon_night():
    img = blank()
    cx, cy = -0.5, -7.5
    def crescent(dx, dy):
        return (dx - (cx + 3.4)) ** 2 + (dy - (cy - 2.0)) ** 2 > 5.6 ** 2
    disc(img, cx, cy, 6.8, (216, 178, 86), crescent)
    def crescent_hi(dx, dy):
        return (dx - (cx + 2.4)) ** 2 + (dy - (cy - 2.0)) ** 2 > 5.8 ** 2
    disc(img, cx - 0.5, cy - 0.3, 6.2, (250, 232, 158), crescent_hi)
    for sx, sy, big in [(5, -13, True), (8, -6, False)]:
        put(img, sx, sy, (255, 255, 230))
        if big:
            for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                put(img, sx + ox, sy + oy, (240, 214, 130))
    return img


def icon_bedtime():
    img = blank()
    cx, cy = 0.0, -7.5
    disc(img, cx, cy, 8.0, (96, 96, 150, 110))   # faint halo
    disc(img, cx, cy, 6.8, (214, 196, 142))
    disc(img, cx - 0.6, cy - 0.6, 6.0, (248, 238, 196))
    for dx, dy, r in [(-2.5, -2.5, 1.3), (2.5, -0.5, 1.7), (-1.0, 2.8, 1.1), (3.0, -4.0, 0.7)]:
        disc(img, cx + dx, cy + dy, r, (214, 200, 154))
    return img


ICONS = {"Morning": icon_morning, "Afternoon": icon_afternoon, "Evening": icon_evening,
         "Night": icon_night, "Bedtime": icon_bedtime}


# ---------------------------------------------------------------- hand
HAND_LEN = 14.8     # TWEAKABLE - tip distance from the centre
HAND_HUB = 2.2      # TWEAKABLE - radius of the round end at the centre
HAND_COLS, HAND_ROWS = 12, 10


def build_hand_frame(index):
    a = math.radians(index * 3.0 - 90.0)
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux  # perpendicular
    cell = [[None] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x - C, y - C
            along = dx * ux + dy * uy
            side = dx * px + dy * py
            if along <= 0.0:
                inside = dx * dx + dy * dy <= HAND_HUB * HAND_HUB
                width = HAND_HUB
            else:
                width = HAND_HUB * (1.0 - along / HAND_LEN) ** 0.75 if along < HAND_LEN else 0.0
                inside = abs(side) <= max(width, 0.0) and along < HAND_LEN
            if inside:
                shaded = side > width * 0.25 and side > 0.4
                cell[y][x] = (205, 212, 228, 255) if shaded else (255, 255, 255, 255)
    img = blank()
    for y in range(SIZE):
        for x in range(SIZE):
            if cell[y][x] is not None:
                img.putpixel((x, y), cell[y][x])
                continue
            for oy in (-1, 0, 1):
                for ox in (-1, 0, 1):
                    nx, ny = x + ox, y + oy
                    if 0 <= nx < SIZE and 0 <= ny < SIZE and cell[ny][nx] is not None:
                        img.putpixel((x, y), NAVY)
    # The pin at the centre.
    for ox, oy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        img.putpixel((int(C - 0.5) + ox, int(C - 0.5) + oy), (118, 126, 150, 255))
    return img


def build_hand_sheet():
    sheet = Image.new("RGBA", (SIZE * HAND_COLS, SIZE * HAND_ROWS), (0, 0, 0, 0))
    for i in range(HAND_COLS * HAND_ROWS):
        sheet.paste(build_hand_frame(i), ((i % HAND_COLS) * SIZE, (i // HAND_COLS) * SIZE))
    return sheet


# ---------------------------------------------------------------- digital time
# Rows of each glyph; "#" = lit. Overworld_Clock.GLYPH_WIDTH must match these widths.
GLYPHS = {
    "0": ["#####", "##.##", "##.##", "##.##", "##.##", "##.##", "#####"],
    "1": [".##", "###", ".##", ".##", ".##", ".##", ".##"],
    "2": ["#####", "...##", "...##", "#####", "##...", "##...", "#####"],
    "3": ["#####", "...##", "...##", ".####", "...##", "...##", "#####"],
    "4": ["##.##", "##.##", "##.##", "#####", "...##", "...##", "...##"],
    "5": ["#####", "##...", "##...", "#####", "...##", "...##", "#####"],
    "6": ["#####", "##...", "##...", "#####", "##.##", "##.##", "#####"],
    "7": ["#####", "...##", "...##", "..##.", ".##..", ".##..", ".##.."],
    "8": ["#####", "##.##", "##.##", "#####", "##.##", "##.##", "#####"],
    "9": ["#####", "##.##", "##.##", "#####", "...##", "...##", "#####"],
    "a": [".....", ".....", "####.", "...##", "#####", "##.##", "#####"],
    "p": [".....", ".....", "#####", "##.##", "#####", "##...", "##..."],
    "m": [".......", ".......", "######.", "##.#.##", "##.#.##", "##.#.##", "##.#.##"],
}
GLYPH_ORDER = "0123456789apm"
CELL_W, CELL_H = 9, 9   # the widest glyph (7) + a 1px outline each side; 7 tall + outline


def build_glyphs():
    sheet = Image.new("RGBA", (CELL_W * len(GLYPH_ORDER), CELL_H), (0, 0, 0, 0))
    for i, ch in enumerate(GLYPH_ORDER):
        rows = GLYPHS[ch]
        lit = {(x, y) for y, row in enumerate(rows) for x, c in enumerate(row) if c == "#"}
        for (x, y) in lit:
            for oy in (-1, 0, 1):
                for ox in (-1, 0, 1):
                    if (x + ox, y + oy) not in lit:
                        sheet.putpixel((i * CELL_W + x + ox + 1, y + oy + 1), NAVY)
        for (x, y) in lit:
            sheet.putpixel((i * CELL_W + x + 1, y + 1), (255, 255, 255, 255))
    return sheet


# ---------------------------------------------------------------- output
def compose(slot, hours, parts, label):
    """Same stack as Overworld_Clock._draw(); only used for the preview."""
    img = parts["faces"][slot].copy()
    img.alpha_composite(parts["dots"])
    img.alpha_composite(parts["icons"][slot])
    frame = int(round((hours % 12.0) / 12.0 * 120.0)) % 120
    box = ((frame % HAND_COLS) * SIZE, (frame // HAND_COLS) * SIZE)
    img.alpha_composite(parts["hand"].crop((box[0], box[1], box[0] + SIZE, box[1] + SIZE)))
    widths = [len(GLYPHS[c][0]) for c in label]
    total = sum(widths) + len(widths) - 1
    x = int(C - total / 2.0 + 0.5)
    y = int(C + 5)
    for c, w in zip(label, widths):
        i = GLYPH_ORDER.index(c)
        img.alpha_composite(parts["glyphs"].crop((i * CELL_W, 0, (i + 1) * CELL_W, CELL_H)), (x - 1, y - 1))
        x += w + 1
    img.alpha_composite(parts["frame"])
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    parts = {
        "faces": {s: build_face(s) for s in FACES},
        "icons": {s: ICONS[s]() for s in FACES},
        "dots": build_dots(),
        "hand": build_hand_sheet(),
        "glyphs": build_glyphs(),
        "frame": build_frame(),
    }
    for s in FACES:
        parts["faces"][s].save(os.path.join(OUT, "Clock_Face_%s.png" % s))
        parts["icons"][s].save(os.path.join(OUT, "Clock_Icon_%s.png" % s))
    parts["dots"].save(os.path.join(OUT, "Clock_Dots.png"))
    parts["hand"].save(os.path.join(OUT, "Clock_Hand.png"))
    parts["glyphs"].save(os.path.join(OUT, "Clock_Glyphs.png"))
    parts["frame"].save(os.path.join(OUT, "Clock_Frame.png"))

    if len(sys.argv) > 1:
        samples = [("Morning", 8.0, "8am"), ("Morning", 9.8, "9am"), ("Afternoon", 13.0, "1pm"),
                   ("Afternoon", 12.0, "12pm"), ("Evening", 16.0, "4pm"), ("Night", 21.0, "9pm"),
                   ("Night", 23.5, "11pm"), ("Bedtime", 25.0, "1am"), ("Bedtime", 24.0, "12am"),
                   ("Evening", 18.4, "6pm")]
        scale = 5
        pad = 8
        cols = 5
        rows = (len(samples) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * (SIZE * scale + pad) + pad, rows * (SIZE * scale + pad) + pad), (60, 110, 70, 255))
        for i, (slot, hours, label) in enumerate(samples):
            big = compose(slot, hours, parts, label).resize((SIZE * scale, SIZE * scale), Image.NEAREST)
            sheet.alpha_composite(big, (pad + (i % cols) * (SIZE * scale + pad), pad + (i // cols) * (SIZE * scale + pad)))
        sheet.save(sys.argv[1])
    print("Wrote clock art to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
