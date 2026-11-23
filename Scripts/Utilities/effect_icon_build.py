"""Effect icon builder — draws the card-search EFFECT icons (one per CATEGORIES key).

    python Scripts/Utilities/effect_icon_build.py            -> Image_Assets/Icons/Effect_Icons/effect_<key>.png
    python Scripts/Utilities/effect_icon_build.py --sheet P  -> also writes a labelled contact sheet to P

Style (modelled on the Yu-Gi-Oh "genre" icons the user referenced): a rounded-square BADGE in the
effect's group colour with a single white GLYPH on it. Every icon is drawn in vectors at 512px and
downsampled, so it stays crisp at the 26px it is shown at on a search chip.

The keys and groups MUST match CATEGORIES in card_effect_tags_build.py; a missing glyph is an error.
Re-run after adding a category, then let the Godot editor import the new PNG.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Image_Assets", "Icons", "Effect_Icons")
FONT = os.path.join(ROOT, "UI_Themes", "ChakraPetch-Bold.ttf")
sys.path.insert(0, os.path.dirname(__file__))
from card_effect_tags_build import CATEGORIES  # noqa: E402

S = 512                 # drawing canvas
OUT_PX = 64             # saved size (TWEAKABLE: the chip draws it at CardSearchOverlay.EFFECT_GLYPH)
W = (250, 248, 255, 255)
INK = (24, 18, 40, 255)
GOLD = (246, 196, 62, 255)
GOLD_D = (178, 124, 20, 255)
RED = (235, 64, 70, 255)

# Badge colour per group, and per-key overrides for the five Special Conditions (their own colours).
GROUP_COL = {
    "DAMAGE":  (214, 72, 62),
    "DEFENCE": (52, 160, 92),
    "STATUS":  (120, 90, 170),
    "ENERGY":  (222, 150, 30),
    "CARDS":   (58, 118, 210),
    "BOARD":   (30, 150, 150),
    "RULES":   (122, 92, 196),
    "SYNERGY": (204, 86, 140),
    "VERSUS":  (132, 150, 44),
}
KEY_COL = {
    "poison": (138, 64, 180), "burn": (232, 104, 36), "sleep": (70, 112, 205),
    "paralyze": (214, 176, 28), "confuse": (212, 78, 150), "self_status": (110, 100, 150),
}


def font(px):
    return ImageFont.truetype(FONT, px)


class Pen:
    def __init__(self, d):
        self.d = d

    # ── primitives ───────────────────────────────────────────────────────────
    def line(self, pts, w=34, c=W):
        self.d.line(pts, fill=c, width=w, joint="curve")
        for p in (pts[0], pts[-1]):
            self.d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=c)

    def poly(self, pts, c=W):
        self.d.polygon(pts, fill=c)

    def circle(self, cx, cy, r, c=W):
        self.d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c)

    def ring(self, cx, cy, r, w=30, c=W):
        self.d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c, width=w)

    def rect(self, x0, y0, x1, y1, r=18, c=W, outline=None, ow=0):
        self.d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=c, outline=outline, width=ow)

    def arc(self, cx, cy, r, a0, a1, w=32, c=W):
        self.d.arc([cx - r, cy - r, cx + r, cy + r], a0, a1, fill=c, width=w)

    def head(self, tip, ang, size=70, c=W):
        """Arrow head at `tip` pointing along `ang` degrees (0 = right, 90 = down)."""
        a = math.radians(ang)
        bx, by = tip[0] - math.cos(a) * size, tip[1] - math.sin(a) * size
        px, py = -math.sin(a) * size * 0.62, math.cos(a) * size * 0.62
        self.poly([tip, (bx + px, by + py), (bx - px, by - py)], c)

    def arrow(self, p0, p1, w=34, size=70, c=W):
        ang = math.degrees(math.atan2(p1[1] - p0[1], p1[0] - p0[0]))
        a = math.radians(ang)
        stop = (p1[0] - math.cos(a) * size * 0.7, p1[1] - math.sin(a) * size * 0.7)
        self.line([p0, stop], w, c)
        self.head(p1, ang, size, c)

    def text(self, cx, cy, s, px=150, c=W):
        f = font(px)
        self.d.text((cx, cy), s, font=f, fill=c, anchor="mm")

    # ── composite shapes ─────────────────────────────────────────────────────
    def coin(self, cx, cy, r, mark=None):
        self.circle(cx, cy, r, GOLD_D)
        self.circle(cx, cy, r * 0.84, GOLD)
        self.ring(cx, cy, r * 0.62, max(6, int(r * 0.09)), GOLD_D)
        if mark:
            self.text(cx, cy + 2, mark, int(r * 1.0), GOLD_D)

    def burst(self, cx, cy, r0, r1, n=8, c=W):
        pts = []
        for i in range(n * 2):
            a = math.pi * i / n - math.pi / 2
            r = r1 if i % 2 == 0 else r0
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
        self.poly(pts, c)

    def heart(self, cx, cy, s, c=W):
        self.circle(cx - s * 0.5, cy - s * 0.2, s * 0.55, c)
        self.circle(cx + s * 0.5, cy - s * 0.2, s * 0.55, c)
        self.poly([(cx - s * 1.03, cy - s * 0.02), (cx + s * 1.03, cy - s * 0.02), (cx, cy + s * 1.05)], c)

    def shield(self, cx, cy, s, c=W):
        self.poly([(cx - s, cy - s * 0.95), (cx, cy - s * 1.2), (cx + s, cy - s * 0.95),
                   (cx + s * 0.9, cy + s * 0.15), (cx, cy + s * 1.15), (cx - s * 0.9, cy + s * 0.15)], c)

    def card(self, x0, y0, x1, y1, c=W, inner=None):
        self.rect(x0, y0, x1, y1, r=22, c=c)
        if inner:
            self.rect(x0 + 18, y0 + 18, x1 - 18, y1 - 18, r=12, c=inner)

    def orb(self, cx, cy, r, c=W, inner=None):
        """An Energy symbol: a disc with a ring of four petals cut into it."""
        self.circle(cx, cy, r, c)
        ink = inner or INK
        for i in range(4):
            a = math.pi / 2 * i + math.pi / 4
            ex, ey = cx + math.cos(a) * r * 0.48, cy + math.sin(a) * r * 0.48
            self.circle(ex, ey, r * 0.17, ink)
        self.circle(cx, cy, r * 0.2, ink)

    def skull(self, cx, cy, s, c=W, ink=INK):
        self.circle(cx, cy - s * 0.15, s * 0.95, c)
        self.rect(cx - s * 0.55, cy + s * 0.35, cx + s * 0.55, cy + s * 1.05, r=12, c=c)
        self.circle(cx - s * 0.38, cy - s * 0.1, s * 0.27, ink)
        self.circle(cx + s * 0.38, cy - s * 0.1, s * 0.27, ink)
        self.poly([(cx, cy + s * 0.18), (cx - s * 0.13, cy + s * 0.42), (cx + s * 0.13, cy + s * 0.42)], ink)
        for dx in (-0.28, 0, 0.28):
            self.d.line([(cx + s * dx, cy + s * 0.65), (cx + s * dx, cy + s * 1.05)], fill=ink, width=int(s * 0.1))

    def flame(self, cx, cy, s, c=W, inner=None):
        self.poly([(cx, cy - s * 1.2), (cx + s * 0.55, cy - s * 0.35), (cx + s * 0.85, cy + s * 0.3),
                   (cx + s * 0.6, cy + s * 0.95), (cx, cy + s * 1.15), (cx - s * 0.6, cy + s * 0.95),
                   (cx - s * 0.85, cy + s * 0.3), (cx - s * 0.35, cy - s * 0.2), (cx - s * 0.2, cy - s * 0.7)], c)
        self.circle(cx, cy + s * 0.55, s * 0.62, c)
        if inner:
            self.poly([(cx, cy - s * 0.1), (cx + s * 0.38, cy + s * 0.5), (cx, cy + s * 0.95),
                       (cx - s * 0.38, cy + s * 0.5)], inner)

    def bolt(self, cx, cy, s, c=W):
        self.poly([(cx + s * 0.25, cy - s * 1.2), (cx - s * 0.75, cy + s * 0.15), (cx - s * 0.05, cy + s * 0.15),
                   (cx - s * 0.3, cy + s * 1.2), (cx + s * 0.75, cy - s * 0.2), (cx + s * 0.05, cy - s * 0.2)], c)

    def spiral(self, cx, cy, s, w=30, c=W):
        pts = []
        for i in range(160):
            t = i / 159 * math.pi * 4.2
            r = s * 0.08 + s * 0.92 * (t / (math.pi * 4.2))
            pts.append((cx + math.cos(t) * r, cy + math.sin(t) * r))
        self.line(pts, w, c)

    def crosshair(self, cx, cy, r, c=W, w=26):
        self.ring(cx, cy, r, w, c)
        self.circle(cx, cy, w * 0.6, c)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            self.d.line([(cx + dx * r * 0.45, cy + dy * r * 0.45), (cx + dx * r * 1.3, cy + dy * r * 1.3)], fill=c, width=w)

    def ban(self, cx, cy, r, c=RED, w=30):
        """The red 'prohibited' roundel, drawn OVER another glyph."""
        self.ring(cx, cy, r, w + 16, INK)
        self.ring(cx, cy, r, w, c)
        a = math.radians(45)
        self.d.line([(cx - math.cos(a) * r, cy - math.sin(a) * r), (cx + math.cos(a) * r, cy + math.sin(a) * r)],
                    fill=INK, width=w + 16)
        self.d.line([(cx - math.cos(a) * r, cy - math.sin(a) * r), (cx + math.cos(a) * r, cy + math.sin(a) * r)],
                    fill=c, width=w)

    def badge_plus(self, cx, cy, r, sign="+", fill=W, ink=INK):
        self.circle(cx, cy, r + 10, ink)
        self.circle(cx, cy, r, fill)
        w = int(r * 0.32)
        self.d.line([(cx - r * 0.55, cy), (cx + r * 0.55, cy)], fill=ink, width=w)
        if sign == "+":
            self.d.line([(cx, cy - r * 0.55), (cx, cy + r * 0.55)], fill=ink, width=w)
        elif sign == "x":
            self.d.line([(cx - r * 0.45, cy - r * 0.45), (cx + r * 0.45, cy + r * 0.45)], fill=ink, width=w)
            self.d.line([(cx - r * 0.45, cy + r * 0.45), (cx + r * 0.45, cy - r * 0.45)], fill=ink, width=w)
            self.d.line([(cx - r * 0.55, cy), (cx + r * 0.55, cy)], fill=fill, width=w + 2)
            self.d.line([(cx - r * 0.45, cy - r * 0.45), (cx + r * 0.45, cy + r * 0.45)], fill=ink, width=w)
            self.d.line([(cx - r * 0.45, cy + r * 0.45), (cx + r * 0.45, cy - r * 0.45)], fill=ink, width=w)

    def counter(self, cx, cy, r, c=(235, 70, 70, 255), label="10"):
        self.circle(cx, cy, r + 10, INK)
        self.circle(cx, cy, r, c)
        self.text(cx, cy + 3, label, int(r * 1.05), W)

    def bench(self, y, c=W):
        for x in (120, 256, 392):
            self.rect(x - 52, y - 36, x + 52, y + 36, r=14, c=c)

    def uturn(self, cx, cy, s, w=34, c=W, flip=False):
        """A U-shaped boomerang arrow — 'comes back at you'."""
        if not flip:
            self.arc(cx, cy, s, 180, 360, w, c)
            self.line([(cx - s, cy), (cx - s, cy + s * 0.6)], w, c)
            self.head((cx + s, cy + s * 0.95), 90, 64, c)
            self.line([(cx + s, cy), (cx + s, cy + s * 0.45)], w, c)
        else:
            self.arc(cx, cy, s, 0, 180, w, c)
            self.line([(cx + s, cy), (cx + s, cy - s * 0.6)], w, c)
            self.head((cx - s, cy - s * 0.95), -90, 64, c)
            self.line([(cx - s, cy), (cx - s, cy - s * 0.45)], w, c)

    def chevrons(self, cx, cy, s, up=True, n=2, c=W, w=40):
        k = -1 if up else 1
        for i in range(n):
            y = cy + (i - (n - 1) / 2) * s * 0.9 * -k
            self.line([(cx - s, y - k * s * 0.5), (cx, y + k * s * 0.5 - k * s * 0.5 - k * s * 0.5 + k * s * 0.5),
                       (cx + s, y - k * s * 0.5)], w, c)

    def chev(self, cx, cy, s, up=True, c=W, w=42):
        k = -1 if up else 1
        self.line([(cx - s, cy - k * s * 0.5), (cx, cy + k * s * 0.5), (cx + s, cy - k * s * 0.5)], w, c)


# ════════════════════════════════════════════════════════════════════════════════════════════
# One function per key. Canvas is 512x512; the badge leaves the middle ~400px for the glyph.
# ════════════════════════════════════════════════════════════════════════════════════════════
def g_bonus_damage(p):
    p.burst(236, 270, 92, 178, 9)
    p.badge_plus(372, 150, 70)

def g_scaling_damage(p):
    for i, h in enumerate((110, 190, 280)):
        x = 120 + i * 120
        p.rect(x - 44, 400 - h, x + 44, 400, r=14)
    p.arrow((110, 200), (390, 70), 26, 60)

def g_damage_boost(p):
    p.burst(256, 300, 80, 158, 9)
    p.chev(256, 150, 120, True, W, 46)
    p.chev(256, 90, 120, True, W, 46)

def g_flip_bonus(p):
    p.coin(220, 290, 150, "")
    p.badge_plus(376, 150, 74)

def g_flip_multiply(p):
    p.coin(220, 290, 150, "")
    p.badge_plus(376, 150, 74, "x")

def g_risky(p):
    p.coin(256, 270, 160, "")
    p.d.line([(250, 110), (290, 210), (230, 280), (280, 350), (250, 430)], fill=INK, width=24)
    p.text(256, 270, "!", 160, RED)

def g_bench_snipe(p):
    p.bench(400)
    p.crosshair(256, 200, 96)

def g_bench_own(p):
    p.bench(400)
    p.crosshair(256, 190, 84)
    p.arrow((256, 300), (256, 345), 22, 46)

def g_recoil(p):
    p.burst(256, 330, 50, 100, 8)
    p.arc(256, 230, 140, 200, 340, 36)
    p.head((256 + math.cos(math.radians(340)) * 140 - 10, 230 + math.sin(math.radians(340)) * 140 + 40), 110, 70)
    p.line([(256 + math.cos(math.radians(200)) * 140, 230 + math.sin(math.radians(200)) * 140), (110, 300)], 36)

def g_place_counters(p):
    p.arrow((256, 70), (256, 210), 32, 66)
    p.counter(256, 330, 112)

def g_move_counters(p):
    p.counter(140, 300, 82)
    p.counter(372, 300, 82)
    p.arc(256, 260, 120, 200, 340, 30)
    p.head((370, 200), 70, 60)

def g_pierce(p):
    p.shield(300, 270, 130, (255, 255, 255, 150))
    p.arrow((70, 420), (440, 100), 34, 84)

def g_instant_ko(p):
    p.skull(256, 230, 150)

def g_counter_damage(p):
    p.line([(140, 80), (140, 330), (360, 330)], 52)
    p.head((450, 330), 0, 110)

def g_copy_attack(p):
    p.card(90, 70, 300, 340, (255, 255, 255, 140))
    p.card(200, 170, 410, 440, W)
    p.burst(305, 305, 34, 74, 8, INK)

def g_extra_attack(p):
    # a Technical Machine: a card with an attack burst and a plus badge
    p.card(130, 70, 360, 430, W)
    p.burst(245, 250, 40, 90, 8, INK)
    p.badge_plus(372, 110, 70)

def g_weak_resist(p):
    # a shield with "x2" (Weakness) and a minus badge (Resistance)
    p.shield(240, 270, 150)
    p.text(240, 270, "x2", 130, INK)
    p.badge_plus(392, 120, 66, "-")

def g_setup_boost(p):
    # a clock face with an "up" chevron: more damage NEXT turn
    p.ring(220, 290, 130, 30)
    p.line([(220, 290), (220, 200)], 28)
    p.line([(220, 290), (284, 330)], 28)
    p.chev(392, 150, 100, True, W, 40)
    p.chev(392, 100, 100, True, W, 40)

def g_block_effects(p):
    p.shield(256, 260, 150)
    p.spiral(256, 250, 70, 22, INK)
    p.ban(256, 256, 190)

def g_attack_condition(p):
    p.burst(256, 260, 120, 196, 10)
    p.text(256, 262, "?", 230, INK)

def g_heal(p):
    p.heart(256, 260, 150)
    p.badge_plus(380, 140, 66)

def g_damage_reduce(p):
    p.shield(256, 260, 150)
    p.d.line([(176, 270), (336, 270)], fill=INK, width=48)

def g_prevent_damage(p):
    p.shield(256, 260, 150)
    p.line([(180, 270), (240, 330), (340, 200)], 40, INK)

def g_hp_boost(p):
    p.heart(236, 290, 136)
    p.arrow((390, 330), (390, 70), 36, 80)

def g_type_change(p):
    p.circle(256, 256, 118, (90, 170, 255, 255))
    p.d.pieslice([138, 138, 374, 374], 90, 270, fill=(255, 120, 80, 255))
    p.ring(256, 256, 118, 16, W)
    p.arc(256, 256, 180, 200, 330, 30)
    p.head((256 + 180 * math.cos(math.radians(330)), 256 + 180 * math.sin(math.radians(330))), 60, 58)
    p.arc(256, 256, 180, 20, 150, 30)
    p.head((256 + 180 * math.cos(math.radians(150)), 256 + 180 * math.sin(math.radians(150))), 240, 58)

def g_status_cure(p):
    # a capsule pill, tilted
    pill = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    q = ImageDraw.Draw(pill)
    q.rounded_rectangle([86, 196, 426, 316], radius=60, fill=W)
    q.rounded_rectangle([256, 196, 426, 316], radius=60, fill=(255, 210, 90, 255))
    q.rectangle([256, 196, 300, 316], fill=(255, 210, 90, 255))
    q.line([(256, 190), (256, 322)], fill=INK, width=12)
    pill = pill.rotate(35, resample=Image.BICUBIC)
    p.d._image.alpha_composite(pill)

def g_poison(p):
    p.poly([(256, 70), (360, 250), (152, 250)])
    p.circle(256, 300, 118)
    p.skull(256, 300, 60, INK, W)

def g_burn(p):
    p.flame(256, 250, 150, W, (255, 160, 60, 255))

def g_sleep(p):
    p.text(190, 300, "Z", 230)
    p.text(340, 170, "z", 170)
    p.text(410, 90, "z", 110)

def g_paralyze(p):
    p.bolt(256, 256, 165)

def g_confuse(p):
    p.spiral(256, 256, 160, 34)

def g_self_status(p):
    p.spiral(220, 230, 110, 28)
    p.arc(256, 256, 200, 20, 120, 30)
    p.head((256 + 200 * math.cos(math.radians(120)), 256 + 200 * math.sin(math.radians(120))), 210, 60)

def g_energy_attach(p):
    p.orb(220, 290, 150, W, (222, 150, 30, 255))
    p.badge_plus(380, 140, 70)

def g_energy_remove(p):
    p.orb(220, 290, 150, W, (222, 150, 30, 255))
    p.circle(380, 140, 82, INK)
    p.circle(380, 140, 72, RED)
    p.d.line([(345, 105), (415, 175)], fill=W, width=24)
    p.d.line([(345, 175), (415, 105)], fill=W, width=24)

def g_energy_discard(p):
    p.orb(256, 170, 112, W, (222, 150, 30, 255))
    p.arrow((256, 300), (256, 395), 26, 52)
    p.rect(150, 400, 362, 440, r=10)

def g_energy_move(p):
    p.orb(130, 300, 86, W, (222, 150, 30, 255))
    p.orb(382, 300, 86, (255, 255, 255, 150), (222, 150, 30, 255))
    p.arc(256, 280, 130, 200, 340, 30)
    p.head((256 + 130 * math.cos(math.radians(340)) + 6, 280 + 130 * math.sin(math.radians(340)) + 30), 75, 60)

def g_energy_supply(p):
    p.orb(190, 300, 110, (255, 255, 255, 170), (222, 150, 30, 255))
    p.orb(320, 220, 120, W, (222, 150, 30, 255))
    p.text(330, 420, "x2", 120, W)

def g_cost_change(p):
    p.orb(256, 200, 120, W, (222, 150, 30, 255))
    p.text(170, 410, "+", 150)
    p.text(340, 400, "-", 160)

def g_draw(p):
    p.card(110, 220, 330, 440, (255, 255, 255, 150))
    p.card(190, 80, 410, 330, W, (58, 118, 210, 255))
    p.arrow((300, 250), (300, 130), 26, 54)

def g_search_deck(p):
    p.card(80, 90, 290, 380, (255, 255, 255, 150))
    p.ring(300, 240, 100, 36)
    p.line([(370, 312), (440, 400)], 50)

def g_bench_call(p):
    p.card(196, 60, 316, 200, W)
    p.arrow((256, 210), (256, 320), 30, 60)
    p.bench(400, (255, 255, 255, 150))

def g_recover(p):
    # gravestone + up arrow (the Yu-Gi-Oh "recover from Graveyard" read)
    p.d.pieslice([110, 200, 330, 420], 180, 360, fill=W)
    p.rect(110, 308, 330, 450, r=8)
    p.d.line([(220, 270), (220, 380)], fill=INK, width=20)
    p.d.line([(185, 305), (255, 305)], fill=INK, width=20)
    p.arrow((380, 400), (380, 80), 36, 84)

def g_discard_hand(p):
    for i, a in enumerate((-18, 0, 18)):
        c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(c).rounded_rectangle([190, 80, 322, 260], radius=18, fill=W if i == 2 else (255, 255, 255, 170))
        p.d._image.alpha_composite(c.rotate(-a, center=(256, 320), resample=Image.BICUBIC))
    p.arrow((256, 300), (256, 400), 26, 52)
    p.rect(150, 405, 362, 445, r=10)

def g_hand_disrupt(p):
    for i, a in enumerate((-22, 0, 22)):
        c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(c).rounded_rectangle([186, 110, 326, 300], radius=18, fill=W if i == 1 else (255, 255, 255, 170))
        p.d._image.alpha_composite(c.rotate(-a, center=(256, 380), resample=Image.BICUBIC))
    p.ban(360, 360, 80)

def g_mill(p):
    for i in range(3):
        p.rect(110, 300 - i * 34, 330, 440 - i * 34, r=16, c=(255, 255, 255, 120 + i * 60), outline=INK, ow=6)
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(c).rounded_rectangle([250, 70, 400, 240], radius=18, fill=W)
    p.d._image.alpha_composite(c.rotate(-24, center=(325, 155), resample=Image.BICUBIC))
    p.arrow((410, 270), (430, 400), 24, 50)

def g_peek(p):
    p.d.ellipse([60, 150, 452, 362], fill=W)
    p.circle(256, 256, 84, INK)
    p.circle(256, 256, 40, (58, 118, 210, 255))
    p.circle(280, 232, 16, W)

def g_prize(p):
    p.card(120, 70, 392, 440, W, (58, 118, 210, 255))
    p.burst(256, 255, 50, 110, 5, GOLD)

def g_bounce(p):
    p.card(150, 220, 362, 450, W, (58, 118, 210, 255))
    p.uturn(256, 170, 110, 32, W, flip=True)

def g_switch(p):
    p.arrow((180, 420), (180, 90), 40, 90)
    p.arrow((332, 90), (332, 420), 40, 90)

def g_gust(p):
    for y, x1 in ((170, 330), (260, 420), (350, 300)):
        p.line([(90, y), (x1, y)], 34)
    p.arc(330, 215, 45, 270, 450, 30)
    p.arc(300, 395, 45, -90, 90, 30)
    p.head((60, 260), 180, 80)

def g_retreat_aid(p):
    p.arrow((420, 200), (90, 200), 40, 90)
    p.text(300, 360, "-1", 170)

def g_retreat_lock(p):
    p.arrow((420, 256), (90, 256), 40, 90)
    p.ban(256, 256, 170)

def g_attack_lock(p):
    p.burst(256, 256, 90, 170, 9)
    p.ban(256, 256, 180)

def g_self_lock(p):
    p.poly([(140, 80), (372, 80), (256, 256)])
    p.poly([(256, 256), (140, 432), (372, 432)])
    p.rect(120, 60, 392, 96, r=10)
    p.rect(120, 416, 392, 452, r=10)
    p.poly([(200, 380), (312, 380), (256, 300)], (30, 150, 150, 255))

def g_evolve(p):
    p.chev(256, 330, 150, True, W, 52)
    p.chev(256, 200, 150, True, W, 52)

def g_devolve(p):
    p.chev(256, 180, 150, False, W, 52)
    p.chev(256, 310, 150, False, W, 52)

def g_evo_block(p):
    p.chev(256, 300, 140, True, W, 50)
    p.chev(256, 190, 140, True, W, 50)
    p.ban(256, 256, 180)

def g_play_as_pokemon(p):
    # a fossil bone
    p.line([(150, 362), (362, 150)], 62)
    for cx, cy in ((150, 362), (362, 150)):
        a = math.radians(45)
        p.circle(cx + math.cos(a + 1.57) * 42, cy + math.sin(a + 1.57) * 42, 52)
        p.circle(cx - math.cos(a + 1.57) * 42, cy - math.sin(a + 1.57) * 42, 52)

def _wrench(p, rot=-40):
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    q = ImageDraw.Draw(c)
    q.rounded_rectangle([226, 180, 286, 450], radius=28, fill=W)
    q.ellipse([166, 60, 346, 240], fill=W)
    q.rectangle([228, 40, 284, 150], fill=(0, 0, 0, 0))
    p.d._image.alpha_composite(c.rotate(rot, center=(256, 256), resample=Image.BICUBIC))


def _stadium(p, cy=200):
    # a stadium: roof triangle over three pillars
    p.poly([(256, cy - 130), (430, cy - 40), (82, cy - 40)])
    for x in (130, 236, 342):
        p.rect(x, cy - 30, x + 40, cy + 90, r=8)
    p.rect(82, cy + 96, 430, cy + 130, r=8)

def g_trainer_lock(p):
    p.card(140, 70, 372, 440, W, (122, 92, 196, 255))
    p.text(256, 258, "T", 190, W)
    p.ban(256, 256, 190)

def g_power_block(p):
    p.burst(256, 256, 60, 170, 4)
    p.burst(256, 256, 30, 90, 4, (122, 92, 196, 255))
    p.ban(256, 256, 190)

def g_markers(p):
    p.circle(256, 200, 128)
    p.poly([(150, 260), (362, 260), (256, 450)])
    p.circle(256, 200, 54, (122, 92, 196, 255))

def g_ko_on(p):
    p.skull(220, 250, 130)
    p.bolt(392, 170, 92, GOLD)

def g_self_ko(p):
    p.skull(256, 280, 120)
    p.burst(256, 120, 40, 110, 9, GOLD)

def g_ko_prevent(p):
    p.shield(256, 260, 160)
    p.skull(256, 250, 80, INK, W)

def g_prize_count(p):
    p.card(110, 90, 300, 400, W, (122, 92, 196, 255))
    p.card(212, 130, 402, 440, W, (122, 92, 196, 255))
    p.text(307, 290, "#", 150, W)

def g_drawback(p):
    p.poly([(256, 60), (452, 430), (60, 430)])
    p.text(256, 290, "!", 230, INK)

def g_coin_flip(p):
    p.coin(256, 256, 180, "")
    p.burst(256, 256, 40, 90, 5, GOLD_D)

def g_recoil_cond(p):
    # the Self Damage hit, crossed out: recoil you can avoid
    p.burst(256, 256, 70, 150, 8)
    p.ban(256, 256, 175)

def g_deck_disrupt(p):
    # a deck being shuffled: two offset cards inside a circular two-arrow loop
    p.card(150, 150, 300, 360, (255, 255, 255, 150))
    p.card(212, 150, 362, 360, W)
    p.arc(256, 256, 205, 200, 330, 34)
    p.head((256 + math.cos(math.radians(330)) * 205, 256 + math.sin(math.radians(330)) * 205), 60, 70)
    p.arc(256, 256, 205, 20, 150, 34)
    p.head((256 + math.cos(math.radians(150)) * 205, 256 + math.sin(math.radians(150)) * 205), 240, 70)

def g_form_change(p):
    # two Pokemon silhouettes (circles) trading places along a refresh loop
    p.circle(165, 180, 78)
    p.circle(347, 332, 78, (255, 255, 255, 150))
    p.arc(256, 256, 190, 300, 400, 34)
    p.head((256 + math.cos(math.radians(40)) * 190, 256 + math.sin(math.radians(40)) * 190), 130, 72)
    p.arc(256, 256, 190, 120, 220, 34)
    p.head((256 + math.cos(math.radians(220)) * 190, 256 + math.sin(math.radians(220)) * 190), 310, 72)

def g_bench_size(p):
    # the three bench slots with a hard stop bar after them
    for x in (108, 216):
        p.rect(x - 52, 300, x + 52, 372, r=14)
    p.rect(324 - 52, 300, 324 + 52, 372, r=14, c=(255, 255, 255, 150))
    p.rect(410, 120, 446, 430, r=12, c=RED)
    p.arrow((90, 200), (380, 200), 34, 72)

def g_energy_lock(p):
    p.orb(256, 256, 150, W)
    p.ban(256, 256, 185)

def g_synergy(p):
    # two interlocking chain links
    p.ring(190, 256, 105, 44)
    p.ring(322, 256, 105, 44)
    # redraw the overlap so the links read as woven, not stacked
    p.arc(190, 256, 105, -40, 40, 44)


def _links(p, cy=360):
    """Small chain link along the bottom - the shared mark of every SYNERGY icon."""
    p.ring(206, cy, 52, 26)
    p.ring(306, cy, 52, 26)


def g_syn_species(p):
    # two Pokemon heads (circles with ears) linked
    for cx, a in ((170, 255), (342, 150)):
        col = (255, 255, 255, a)
        p.circle(cx, 200, 82, col)
        p.poly([(cx - 70, 160), (cx - 50, 70), (cx - 20, 140)], col)
        p.poly([(cx + 70, 160), (cx + 50, 70), (cx + 20, 140)], col)
    _links(p, 380)

def g_syn_named(p):
    # a trainer card with a name banner
    p.card(150, 60, 362, 330, W)
    p.rect(176, 90, 336, 130, r=10, c=INK)
    p.circle(256, 230, 58, INK)
    _links(p, 410)

def g_syn_type(p):
    # three type orbs
    p.orb(150, 200, 78, (255, 255, 255, 255))
    p.orb(362, 200, 78, (255, 255, 255, 170))
    p.orb(256, 110, 70, (255, 255, 255, 210))
    _links(p, 370)

def g_syn_dark_light(p):
    # half dark / half light disc
    p.circle(256, 210, 140, W)
    p.d.pieslice([116, 70, 396, 350], 90, 270, fill=INK)
    p.ring(256, 210, 140, 16, W)
    _links(p, 420)

def g_syn_react(p):
    # energy orb with a reaction burst ring
    p.burst(256, 210, 120, 170, 10, (255, 255, 255, 140))
    p.orb(256, 210, 105, W)
    _links(p, 420)

def g_syn_holon(p):
    # H inside a ring
    p.ring(256, 210, 150, 30)
    p.text(256, 214, "H", 210)
    _links(p, 420)

def g_syn_delta(p):
    # hand-drawn δ (the UI font has no Greek): a round bowl with a hooked stem on top
    p.ring(256, 245, 92, 42)
    p.line([(220, 160), (190, 110), (215, 70), (300, 60), (330, 82)], 42)
    _links(p, 410)

def g_unown(p):
    # an Unown eye: ring with a pupil and a stalk
    p.ring(256, 210, 120, 40)
    p.circle(256, 210, 50)
    p.line([(256, 330), (256, 440)], 40)
    p.line([(256, 90), (256, 40)], 40)


def g_syn_special(p):
    # an Energy orb with a star on it
    p.orb(256, 210, 130, W)
    p.burst(256, 210, 26, 76, 5, INK)
    _links(p, 420)

def g_trainer_manip(p):
    # a Trainer card being plucked away: card + circling arrow
    p.card(150, 90, 340, 400, W)
    p.text(245, 245, "T", 170, INK)
    p.arc(256, 256, 200, 300, 40, 30)
    p.head((410, 380), 120, 64)


def _vs(p):
    """'VS' tag along the bottom - the shared mark of every VERSUS icon."""
    p.text(256, 420, "VS", 120)

def g_syn_status(p):
    # a drop + sleepy Z: a Pokemon with a Special Condition
    p.poly([(190, 60), (270, 200), (110, 200)])
    p.circle(190, 225, 82)
    p.text(345, 190, "Z", 190)
    _links(p, 410)

def g_syn_ex(p):
    p.text(256, 200, "EX", 220)
    _links(p, 400)

def g_syn_stage(p):
    p.rect(90, 230, 190, 310, r=12)
    p.rect(206, 150, 306, 310, r=12)
    p.rect(322, 70, 422, 310, r=12)
    _links(p, 400)

def g_status_immune(p):
    p.shield(256, 260, 160)
    p.poly([(256, 150), (310, 250), (202, 250)], INK)
    p.circle(256, 280, 60, INK)

def g_syn_tool(p):
    _wrench(p)
    _links(p, 410)

def g_syn_stadium(p):
    _stadium(p, 200)
    _links(p, 420)

def g_syn_supporter(p):
    p.card(160, 60, 352, 330, W)
    p.text(256, 200, "S", 170, INK)
    _links(p, 410)

def g_syn_damaged(p):
    p.counter(180, 200, 90)
    p.burst(352, 190, 40, 100, 8)
    _links(p, 410)

def g_anti_tool(p):
    _wrench(p, -40)
    p.ban(256, 190, 140)
    _vs(p)

def g_anti_stadium(p):
    _stadium(p, 200)
    p.ban(256, 190, 140)
    _vs(p)

def g_vs_damaged(p):
    p.counter(256, 200, 120)
    _vs(p)

def g_vs_ex(p):
    p.text(256, 200, "EX", 220)
    _vs(p)

def g_vs_stage(p):
    # three rising steps
    p.rect(90, 250, 190, 330, r=12)
    p.rect(206, 170, 306, 330, r=12)
    p.rect(322, 90, 422, 330, r=12)
    _vs(p)

def g_vs_dark_light(p):
    p.circle(256, 200, 130, W)
    p.d.pieslice([126, 70, 386, 330], 90, 270, fill=INK)
    p.ring(256, 200, 130, 16, W)
    _vs(p)

def g_vs_type(p):
    p.orb(256, 200, 120, W)
    p.head((256, 270), 90, 90, INK)
    _vs(p)


def badge_colour(key, group):
    return KEY_COL.get(key, GROUP_COL[group])


def render(key, group):
    big = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    col = badge_colour(key, group)
    dark = tuple(int(c * 0.55) for c in col)
    d.rounded_rectangle([6, 6, S - 6, S - 6], radius=96, fill=dark + (255,))
    d.rounded_rectangle([22, 22, S - 22, S - 22], radius=82, fill=col + (255,))
    # soft top sheen
    sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).rounded_rectangle([22, 22, S - 22, S // 2], radius=82, fill=(255, 255, 255, 34))
    big.alpha_composite(sheen)

    glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fn = globals().get("g_" + key)
    if fn is None:
        raise SystemExit("no glyph drawn for effect key: " + key)
    fn(Pen(ImageDraw.Draw(glyph)))
    # shrink the glyph a touch so it sits inside the badge with a margin, then drop-shadow it
    glyph = glyph.resize((int(S * 0.78), int(S * 0.78)), Image.LANCZOS)
    off = (S - glyph.width) // 2
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    a = glyph.split()[3].point(lambda v: int(v * 0.45))
    shadow.paste((0, 0, 0, 255), (off + 8, off + 10), a)
    big.alpha_composite(shadow)
    big.alpha_composite(glyph, (off, off))
    return big.resize((OUT_PX, OUT_PX), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    icons = []
    for key, label, group, _desc in CATEGORIES:
        im = render(key, group)
        im.save(os.path.join(OUT, "effect_%s.png" % key))
        icons.append((key, label, group, im))
    print("wrote %d icons to %s" % (len(icons), OUT))

    if "--sheet" in sys.argv:
        path = sys.argv[sys.argv.index("--sheet") + 1]
        cols, cw, ch = 8, 230, 150
        rows = (len(icons) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * cw, rows * ch), (30, 22, 48, 255))
        d = ImageDraw.Draw(sheet)
        f = font(18)
        for i, (key, label, group, im) in enumerate(icons):
            x, y = (i % cols) * cw, (i // cols) * ch
            sheet.alpha_composite(im.resize((96, 96), Image.LANCZOS), (x + (cw - 96) // 2, y + 8))
            d.text((x + cw // 2, y + 120), label.upper(), font=f, fill=(240, 236, 250), anchor="mm")
        sheet.save(path)
        print("sheet", path)


if __name__ == "__main__":
    main()
