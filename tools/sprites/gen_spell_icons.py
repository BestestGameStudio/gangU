#!/usr/bin/env python3
"""Generate the spell-icon glyph rows for assets/sprites/spell_icons.png.

One raw glyph per spell AND per spell upgrade (Mitra, 2026-11-15), drawn as crisp
hand-composed pixel art: dark 1px outline, three-tone shading, light from upper
left, no baked frame/chevrons/sweep and no muddy glow halo - the game assembles
the frame and all state art around the glyph.

Sheet layout: 7 columns x 47x48 cells, one glyph per row in column 0 (row order
= GLYPHS dict order: fireball, mana, bolt first to match the committed anims).
Revamp pass (Mitra, 2026-11-15): sledgehammer family, base fireball/mana/bolt
redrawn as primitives (no baked glow-on-black), rim-light + ambient-shade polish
on every glyph.

usage: python3 -I tools/sprites/gen_spell_icons.py
"""
import math, os, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHEET = os.path.join(ROOT, "assets/sprites/spell_icons.png")
CW, CH = 47, 48
RING = 8  # frame + corner gems live in the outer 8 px of the committed tiles


# ------------------------------------------------------------ palette ---
# (outline, dark, mid, light) per family; hue follows the projectile colour.
WATER = ((14, 48, 110, 255), (26, 95, 208, 255), (58, 160, 255, 255), (191, 230, 255, 255))
FROST = ((20, 80, 110, 255), (47, 168, 216, 255), (127, 231, 255, 255), (232, 251, 255, 255))
FIRE = ((90, 25, 5, 255), (200, 60, 10, 255), (255, 120, 20, 255), (255, 220, 120, 255))
MANA = ((40, 28, 90, 255), (90, 70, 200, 255), (150, 115, 255, 255), (225, 215, 255, 255))
BOLT = ((12, 50, 100, 255), (30, 120, 220, 255), (90, 190, 255, 255), (215, 240, 255, 255))
STONE = ((40, 40, 45, 255), (98, 98, 105, 255), (160, 160, 168, 255), (215, 215, 220, 255))
WOOD = ((52, 30, 16, 255), (104, 62, 34, 255), (150, 92, 50, 255), (190, 130, 80, 255))
GHOST = ((50, 60, 120, 255), (122, 143, 224, 255), (185, 200, 255, 255), (242, 246, 255, 255))
LEAF = ((16, 60, 30, 255), (47, 138, 79, 255), (94, 201, 107, 255), (200, 255, 208, 255))


def P(d, pts, fill, ol):
    """Outlined polygon: silhouette-first crisp pixel shape."""
    d.polygon(pts, fill=fill, outline=ol, width=1)


def sparkles(d, pts, c):
    for x, y in pts:
        d.point((x, y), fill=c)
        d.point((x - 1, y), fill=(c[0], c[1], c[2], 150))
        d.point((x, y - 1), fill=(c[0], c[1], c[2], 150))


def drop(d, cx, cy, s, cols, sparkle=True):
    """Water drop: plump teardrop, light streak upper left."""
    ol, dk, md, lt = cols
    P(d, [(cx, cy - s), (cx + s * 0.8, cy + s * 0.1), (cx + s * 0.6, cy + s * 0.75),
          (cx, cy + s), (cx - s * 0.6, cy + s * 0.75), (cx - s * 0.8, cy + s * 0.1)], md, ol)
    P(d, [(cx - s * 0.15, cy - s * 0.55), (cx + s * 0.35, cy + s * 0.15),
          (cx - s * 0.1, cy + s * 0.5), (cx - s * 0.45, cy + s * 0.1)], lt, lt)
    P(d, [(cx + s * 0.3, cy + s * 0.4), (cx + s * 0.55, cy + s * 0.6),
          (cx + s * 0.1, cy + s * 0.75)], dk, dk)
    if sparkle:
        sparkles(d, [(cx + s + 3, cy - s), (cx - s - 3, cy - s * 0.4)], lt)


def flame(d, cx, cy, s, cols=FIRE):
    """Fireball flame: teardrop with a wavy tip, hot core."""
    ol, dk, md, lt = cols
    P(d, [(cx, cy - s), (cx + s * 0.5, cy - s * 0.5), (cx + s * 0.75, cy + s * 0.1),
          (cx + s * 0.55, cy + s * 0.7), (cx, cy + s), (cx - s * 0.55, cy + s * 0.7),
          (cx - s * 0.75, cy + s * 0.1), (cx - s * 0.4, cy - s * 0.45)], md, ol)
    P(d, [(cx + s * 0.05, cy - s * 0.4), (cx + s * 0.4, cy + s * 0.2),
          (cx, cy + s * 0.6), (cx - s * 0.35, cy + s * 0.15)], lt, lt)
    P(d, [(cx + s * 0.45, cy + s * 0.3), (cx + s * 0.5, cy + s * 0.65),
          (cx + s * 0.1, cy + s * 0.8)], dk, dk)


def bolt_stroke(d, pts, w, cols):
    """Lightning polyline: dark underlay, bright core."""
    ol, dk, md, lt = cols
    d.line(pts, fill=ol, width=w + 2, joint="curve")
    d.line(pts, fill=md, width=w, joint="curve")
    d.line([(x, y) for x, y in pts], fill=lt, width=max(1, w - 2), joint="curve")


def stone_block(d, x0, y0, x1, y1, cols=STONE, band=True):
    """Bevelled stone block: top-light, dark base edge, optional metal band."""
    ol, dk, md, lt = cols
    P(d, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], md, ol)
    d.line([(x0 + 1, y0 + 1), (x1 - 2, y0 + 1)], fill=lt, width=2)      # top bevel
    d.line([(x0 + 1, y0 + 2), (x0 + 1, y1 - 2)], fill=lt, width=1)      # left bevel
    d.line([(x0 + 1, y1 - 2), (x1 - 1, y1 - 2)], fill=dk, width=2)      # base shade
    d.line([(x1 - 2, y0 + 3), (x1 - 2, y1 - 2)], fill=dk, width=1)      # right shade
    if band:
        xm = (x0 + x1) // 2
        d.line([(xm - 1, y0 + 1), (xm - 1, y1 - 1)], fill=ol, width=2)  # strap
        d.point((xm - 1, (y0 + y1) // 2), fill=lt)                      # rivet


def draw_fireball(d):
    """Fireball: fat flame with hot core and licking wisps."""
    flame(d, 23, 24, 13, FIRE)
    ol, dk, md, lt = FIRE
    d.arc([9, 7, 37, 41], start=200, end=320, fill=dk, width=2)   # smoke wisp
    sparkles(d, [(8, 12), (38, 10), (36, 38)], lt)


def draw_mana(d):
    """Mana orb: deep sphere, bright glare, under-shade."""
    ol, dk, md, lt = MANA
    d.ellipse([10, 10, 36, 36], fill=md, outline=ol, width=2)
    d.ellipse([15, 13, 25, 23], fill=lt)                          # glare
    d.arc([13, 24, 33, 37], start=20, end=160, fill=dk, width=3)  # under-shade
    sparkles(d, [(38, 11), (7, 33), (30, 5)], lt)


def draw_bolt(d):
    """Lightning bolt: classic hard zigzag, bright core."""
    bolt_stroke(d, [(28, 3), (17, 20), (25, 20), (15, 44)], 5, BOLT)
    sparkles(d, [(35, 8), (8, 38), (33, 30)], BOLT[3])


def polish(tile):
    """Painterly-adapted finish: rim light on up-left silhouette edges, ambient
    shade on down-right edges. Outlines stay hard; alpha untouched."""
    px = tile.load()
    tw, th = tile.size

    def solid(x, y):
        return 0 <= x < tw and 0 <= y < th and px[x, y][3] > 200

    def blend(c, t, k):
        return (int(c[0] + (t[0] - c[0]) * k), int(c[1] + (t[1] - c[1]) * k),
                int(c[2] + (t[2] - c[2]) * k), c[3])

    ops = []
    for y in range(th):
        for x in range(tw):
            c = px[x, y]
            if c[3] <= 200:
                continue
            if 0.3 * c[0] + 0.5 * c[1] + 0.2 * c[2] < 70:
                continue  # keep the dark outline hard
            if not solid(x, y - 1) or not solid(x - 1, y):
                ops.append((x, y, blend(c, (255, 255, 255), 0.45)))
            elif not solid(x, y + 1) or not solid(x + 1, y):
                ops.append((x, y, blend(c, (0, 0, 16), 0.35)))
    for x, y, c in ops:
        px[x, y] = c


# ------------------------------------------------------------ glyphs ---

def draw_water(d):
    drop(d, 23, 24, 13, WATER)


def draw_frost(d):
    """Six-arm snowflake: crisp arms with barbs, bright core."""
    ol, dk, md, lt = FROST
    cx, cy = 23, 23
    for k in range(6):
        a = math.radians(k * 60 + 30)
        ux, uy = math.cos(a), math.sin(a)
        bolt_stroke(d, [(cx, cy), (cx + ux * 14, cy + uy * 14)], 2, FROST)
        bx, by = cx + ux * 8, cy + uy * 8
        for s in (1, -1):
            ba = a + s * math.radians(45)
            d.line([(bx, by), (bx + math.cos(ba) * 5, by + math.sin(ba) * 5)], fill=md, width=2)
    d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=md, outline=ol)
    d.point((cx, cy), fill=lt)
    sparkles(d, [(11, 11), (36, 12), (35, 34), (12, 33)], lt)


def _sledge(d, cx, cy, half_len, half_th, hlen, hw, ang=40):
    """Proper sledgehammer on a descending diagonal: big blocky rectangular head
    with flat striking faces on BOTH ends, short thick collar at the eye, long
    straight handle with a wrapped grip. u = handle/head axis, n = normal."""
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    ol, dk, md, lt = STONE

    def pt(s, t):  # s along u, t along n
        return (cx + s * ux + t * nx, cy + s * uy + t * ny)

    # handle first (head draws over its top end)
    b0 = pt(2, 0)
    b1 = pt(2 + hlen, 0)
    w_ol, w_dk, w_md, w_lt = WOOD
    d.line([b0, b1], fill=w_ol, width=hw + 2)
    d.line([b0, b1], fill=w_md, width=hw)
    d.line([pt(3, -hw * 0.28), pt(2 + hlen - 1, -hw * 0.28)], fill=w_lt, width=1)
    # wrapped grip: darker butt section with two light bands
    g0 = pt(2 + hlen * 0.62, 0)
    d.line([g0, b1], fill=w_ol, width=hw + 2)
    d.line([g0, b1], fill=w_dk, width=hw)
    for f in (0.72, 0.88):
        p = pt(2 + hlen * f, 0)
        d.line([(p[0] - nx * hw * 0.5, p[1] - ny * hw * 0.5),
                (p[0] + nx * hw * 0.5, p[1] + ny * hw * 0.5)], fill=w_lt, width=1)
    d.point(b1, fill=w_ol)
    # blocky rectangular head
    P(d, [pt(-half_len, -half_th), pt(half_len, -half_th),
          pt(half_len, half_th), pt(-half_len, half_th)], md, ol)
    # flat striking faces on both ends: light face up-left, dark face down-right
    P(d, [pt(-half_len, -half_th), pt(-half_len + 2.4, -half_th),
          pt(-half_len + 2.4, half_th), pt(-half_len, half_th)], lt, ol)
    P(d, [pt(half_len - 2.4, -half_th), pt(half_len, -half_th),
          pt(half_len, half_th), pt(half_len - 2.4, half_th)], dk, ol)
    # head bevels: light along the up-left long edge, dark along the down-right one
    d.line([pt(-half_len + 2.8, -half_th + 1.4), pt(half_len - 2.8, -half_th + 1.4)],
           fill=lt, width=1)
    d.line([pt(-half_len + 2.8, half_th - 1.4), pt(half_len - 2.8, half_th - 1.4)],
           fill=dk, width=2)
    # short thick collar around the eye
    P(d, [pt(-2.6, -half_th - 1), pt(2.6, -half_th - 1),
          pt(2.6, half_th + 1), pt(-2.6, half_th + 1)], dk, ol)
    d.line([pt(-2.2, -half_th - 0.4), pt(2.2, -half_th - 0.4)], fill=lt, width=1)
    d.point(pt(0, 0), fill=ol)  # eye rivet


def draw_hammer(d):
    """Sledgehammer: long straight handle, blocky double-faced head."""
    _sledge(d, 16.5, 14.5, 9, 5.5, 24, 4)
    sparkles(d, [(4, 30), (40, 9)], (220, 220, 225, 255))


def draw_punch(d):
    """Spectral fist, knuckles forward: four finger blocks, thumb, wrist."""
    ol, dk, md, lt = GHOST
    # palm
    P(d, [(14, 18), (32, 18), (33, 30), (29, 36), (17, 36), (13, 30)], md, ol)
    d.line([(15, 19), (31, 19)], fill=lt, width=1)
    # fingers: four bars with knuckle highlights and dark gaps
    for i in range(4):
        x = 14 + i * 5
        P(d, [(x, 10), (x + 4, 10), (x + 4, 21), (x, 21)], md, ol)
        d.line([(x + 1, 11), (x + 2, 11)], fill=lt, width=1)
    # thumb
    P(d, [(32, 24), (38, 20), (39, 24), (34, 30)], md, ol)
    d.point((35, 23), fill=lt)
    # wrist wisp
    d.line([(20, 36), (19, 41)], fill=dk, width=3)
    d.line([(25, 36), (26, 41)], fill=md, width=2)
    sparkles(d, [(10, 9), (39, 12)], lt)


def draw_block(d):
    """Stone brick, iso cube."""
    ol, dk, md, lt = STONE
    P(d, [(23, 9), (35, 15), (23, 21), (11, 15)], lt, ol)      # top
    P(d, [(11, 15), (23, 21), (23, 37), (11, 31)], md, ol)     # left face
    P(d, [(35, 15), (35, 31), (23, 37), (23, 21)], dk, ol)     # right face
    d.line([(14, 18), (21, 22)], fill=dk, width=1)             # mortar
    d.line([(32, 18), (25, 22)], fill=(60, 60, 66, 255), width=1)
    sparkles(d, [(37, 10), (9, 34)], (215, 215, 220, 255))


def draw_summon(d):
    """Ally wisp over a summoning ring."""
    ol, dk, md, lt = LEAF
    d.ellipse([10, 34, 36, 42], outline=ol, width=2)            # ring
    d.ellipse([14, 36, 32, 41], outline=md, width=1)
    P(d, [(23, 10), (28, 14), (30, 21), (28, 28), (25, 32), (21, 32), (18, 28),
          (16, 21), (18, 14)], md, ol)                          # body
    P(d, [(21, 14), (26, 17), (27, 22), (24, 28), (21, 27), (19, 21)], lt, lt)  # chest light
    d.point((21, 18), fill=ol); d.point((25, 18), fill=ol)      # eyes
    d.line([(18, 27), (15, 31)], fill=md, width=2)              # arms
    d.line([(28, 27), (31, 31)], fill=md, width=2)
    sparkles(d, [(12, 12), (36, 11)], lt)


# ---- water family upgrades ----

def draw_water_guided(d):
    ol, dk, md, lt = WATER
    d.arc([4, 16, 44, 46], start=190, end=340, fill=ol, width=3)
    d.arc([4, 16, 44, 46], start=190, end=340, fill=md, width=1)
    P(d, [(38, 12), (44, 12), (40, 18)], lt, ol)                # path arrowhead
    drop(d, 23, 22, 10, WATER)


def draw_water_seeking(d):
    ol, dk, md, lt = WATER
    drop(d, 23, 23, 9, WATER)
    d.ellipse([8, 8, 38, 38], outline=ol, width=2)
    d.ellipse([10, 10, 36, 36], outline=md, width=1)
    for p0, p1 in (((23, 4), (23, 9)), ((23, 37), (23, 42)), ((4, 23), (9, 23)),
                   ((37, 23), (42, 23))):
        d.line([p0, p1], fill=lt, width=2)


def draw_water_tidal(d):
    ol, dk, md, lt = WATER
    P(d, [(4, 40), (8, 24), (16, 12), (26, 8), (22, 16), (30, 12), (38, 18),
          (43, 28), (42, 40)], md, ol)                          # wave body
    P(d, [(10, 36), (14, 24), (20, 16), (25, 13), (21, 19), (28, 16), (34, 20),
          (38, 28), (37, 36)], lt, lt)                          # face light
    P(d, [(4, 40), (42, 40), (38, 44), (8, 44)], dk, ol)        # foam base
    d.arc([18, 8, 36, 26], start=90, end=250, fill=lt, width=2)  # curl


def draw_water_barrage(d):
    for cx, cy, s in ((12, 29, 8), (24, 17, 9), (36, 29, 8)):
        drop(d, cx, cy, s, WATER, sparkle=False)
    sparkles(d, [(24, 34), (5, 14), (42, 14)], WATER[3])


def draw_water_bubble(d):
    ol, dk, md, lt = WATER
    d.ellipse([8, 8, 38, 38], outline=ol, width=4)
    d.ellipse([11, 11, 35, 35], outline=md, width=2)
    d.arc([13, 12, 30, 29], start=140, end=255, fill=lt, width=3)
    d.ellipse([30, 28, 35, 33], fill=lt)                        # bottom glint
    sparkles(d, [(38, 10), (8, 37)], lt)


def draw_water_splash(d):
    ol, dk, md, lt = WATER
    P(d, [(5, 40), (41, 40), (38, 44), (8, 44)], md, ol)        # surface
    # spray jets
    for p0, p1, w in (((12, 39), (5, 18), 3), ((19, 39), (16, 10), 4),
                      ((27, 39), (30, 14), 4), ((34, 39), (42, 20), 3)):
        d.line([p0, p1], fill=ol, width=w)
        d.line([p0, p1], fill=md, width=w - 2)
    for cx, cy in ((4, 14), (16, 6), (30, 9), (43, 16), (23, 12)):
        d.point((cx, cy), fill=lt)


def draw_big_ball(d):
    ol, dk, md, lt = WATER
    d.ellipse([5, 6, 41, 42], fill=md, outline=ol, width=2)
    d.ellipse([10, 9, 27, 26], fill=lt)                         # big glare
    d.arc([12, 26, 38, 41], start=20, end=140, fill=dk, width=3)  # under-shade
    sparkles(d, [(38, 10), (9, 36)], lt)


def draw_heavy_rain(d):
    ol, dk, md, lt = WATER
    P(d, [(7, 17), (10, 9), (20, 5), (30, 6), (37, 10), (39, 17)], md, ol)  # cloud
    d.line([(11, 14), (30, 14)], fill=lt, width=2)
    P(d, [(7, 17), (39, 17), (36, 20), (10, 20)], dk, ol)       # cloud base
    for x in (10, 17, 24, 31, 37):                              # rain
        d.line([(x, 25), (x - 4, 41)], fill=ol, width=3)
        d.line([(x, 25), (x - 4, 41)], fill=md, width=1)
        d.point((x - 4, 42), fill=lt)


def draw_surging_bubble(d):
    ol, dk, md, lt = WATER
    for x in (13, 23, 33):                                      # surge jets
        d.line([(x, 32), (x, 43)], fill=ol, width=4)
        d.line([(x, 32), (x, 43)], fill=md, width=2)
        P(d, [(x - 3, 34), (x, 30), (x + 3, 34)], lt, ol)
    d.ellipse([12, 5, 34, 27], outline=ol, width=4)             # bubble
    d.ellipse([15, 8, 31, 24], outline=md, width=1)
    d.arc([16, 8, 28, 20], start=150, end=260, fill=lt, width=2)


# ---- hammer family upgrades ----

def draw_hammer_gambler(d):
    draw_hammer(d)
    ol = (30, 30, 40, 255)
    P(d, [(30, 2), (44, 6), (42, 20), (28, 16)], (232, 232, 240, 255), ol)  # tilted die
    for p in ((34, 8), (39, 9), (33, 13), (38, 14), (36, 11)):
        d.point(p, fill=(40, 40, 60, 255))


def draw_hammer_leap(d):
    ol = STONE[0]
    d.arc([0, 14, 30, 50], start=210, end=330, fill=(200, 200, 210, 255), width=3)
    P(d, [(3, 15), (10, 10), (10, 19)], (220, 220, 230, 255), ol)  # leap arrowhead
    draw_hammer(d)


def draw_hammer_reaper(d):
    draw_hammer(d)
    ol, lt = STONE[0], STONE[3]
    d.arc([4, -2, 46, 36], start=265, end=55, fill=ol, width=6)     # scythe blade
    d.arc([7, 1, 43, 33], start=265, end=55, fill=lt, width=3)


def draw_hammer_rhythm(d):
    draw_hammer(d)
    n_ol, n = (60, 50, 10, 255), (240, 220, 130, 255)
    for x, y in ((33, 6), (40, 13)):                              # beat notes
        d.ellipse([x, y, x + 5, y + 4], fill=n, outline=n_ol)
        d.line([(x + 5, y + 1), (x + 5, y - 6)], fill=n_ol, width=1)
    d.line([(35, 1), (45, 8)], fill=n_ol, width=1)                # beam


def draw_hammer_titan(d):
    _sledge(d, 15.5, 13.5, 12, 7, 24, 5)
    d.line([(10, 38), (8, 43)], fill=STONE[1], width=2)           # ground crack
    d.line([(15, 38), (15, 44)], fill=STONE[1], width=1)
    d.line([(20, 39), (23, 44)], fill=STONE[0], width=1)
    sparkles(d, [(42, 6), (4, 25)], (220, 220, 225, 255))


def draw_hammer_vortex(d):
    draw_hammer(d)
    s_ol, s = (20, 60, 110, 255), (150, 200, 255, 255)
    d.arc([3, 3, 43, 43], start=300, end=180, fill=s_ol, width=4)
    d.arc([3, 3, 43, 43], start=300, end=180, fill=s, width=2)
    d.arc([11, 11, 35, 35], start=120, end=340, fill=s, width=2)


# ---- punch family upgrades ----

def draw_punch_bubble(d):
    ol, dk, md, lt = GHOST
    d.ellipse([5, 5, 41, 41], outline=ol, width=3)                # bubble
    d.ellipse([8, 8, 38, 38], outline=md, width=1)
    d.arc([10, 9, 27, 26], start=140, end=255, fill=lt, width=2)
    # small fist inside
    P(d, [(16, 20), (31, 20), (32, 29), (28, 33), (19, 33), (15, 29)], md, ol)
    for i in range(4):
        x = 16 + i * 4
        P(d, [(x, 14), (x + 3, 14), (x + 3, 22), (x, 22)], md, ol)
        d.point((x + 1, 15), fill=lt)
    P(d, [(31, 25), (35, 22), (36, 25), (33, 29)], md, ol)


def draw_punch_burst(d):
    draw_punch(d)
    w_ol, w = (150, 150, 180, 255), (255, 255, 255, 255)
    for p0, p1 in (((23, 2), (23, 8)), ((6, 10), (11, 14)), ((40, 10), (35, 14)),
                   ((8, 3), (13, 8)), ((38, 3), (33, 8))):
        d.line([p0, p1], fill=w_ol, width=3)
        d.line([p0, p1], fill=w, width=1)


def draw_punch_launch(d):
    ol, dk, md, lt = GHOST
    for x in (13, 20, 27):                                        # launch trail
        d.line([(x, 34), (x + 7, 45)], fill=dk, width=3)
        d.line([(x, 34), (x + 7, 45)], fill=md, width=1)
    P(d, [(17, 19), (34, 19), (35, 29), (31, 34), (20, 34), (16, 29)], md, ol)
    for i in range(4):                                            # fist high
        x = 16 + i * 5
        P(d, [(x, 8), (x + 4, 8), (x + 4, 21), (x, 21)], md, ol)
        d.point((x + 1, 9), fill=lt)
    P(d, [(34, 24), (39, 20), (40, 24), (36, 29)], md, ol)


# ---- mana family upgrades ----

def draw_mana_lance(d):
    ol, dk, md, lt = MANA
    P(d, [(7, 37), (28, 10), (40, 5), (37, 17), (15, 41)], md, ol)   # crystal lance
    P(d, [(13, 35), (29, 13), (36, 9), (33, 15), (17, 37)], lt, lt)
    d.line([(28, 13), (33, 16)], fill=dk, width=2)                   # facet
    sparkles(d, [(39, 23), (8, 29)], lt)


def draw_mana_volley(d):
    for pts in ([(10, 12), (14, 21), (10, 32)], [(22, 7), (27, 19), (22, 35)],
                [(34, 12), (38, 21), (34, 32)]):
        bolt_stroke(d, pts, 3, MANA)


# ---- bolt family upgrades ----

def draw_bolt_flurry(d):
    for pts in ([(9, 14), (13, 22), (9, 31)], [(21, 8), (26, 19), (21, 35)],
                [(33, 14), (37, 22), (33, 31)]):
        bolt_stroke(d, pts, 2, BOLT)


def draw_bolt_heavy(d):
    bolt_stroke(d, [(26, 4), (33, 17), (26, 21), (33, 43), (17, 24), (24, 20), (15, 7)],
                4, BOLT)


# ---- fireball family upgrades ----

def draw_fireball_beam(d):
    beam(d, 6, 41, 23, 5)
    flame(d, 11, 23, 6)


def beam(d, x0, x1, cy, w):
    ol, dk, md, lt = FIRE
    d.rounded_rectangle([x0, cy - w, x1, cy + w], radius=w, fill=md, outline=ol, width=1)
    d.line([(x0 + 2, cy - w + 2), (x1 - 2, cy - w + 2)], fill=lt, width=1)
    d.line([(x0 + 2, cy + w - 2), (x1 - 2, cy + w - 2)], fill=dk, width=2)
    d.line([(x0 + 3, cy), (x1 - 3, cy)], fill=lt, width=1)


def draw_fireball_beam_heavy(d):
    beam(d, 4, 43, 23, 8)
    flame(d, 12, 23, 7)


def draw_fireball_beam_long(d):
    beam(d, 1, 46, 23, 3)
    flame(d, 6, 23, 5)


def draw_fireball_beam_homing(d):
    ol, dk, md, lt = FIRE
    d.arc([3, 7, 41, 43], start=295, end=85, fill=ol, width=7)
    d.arc([3, 7, 41, 43], start=295, end=85, fill=md, width=4)
    d.arc([3, 7, 41, 43], start=295, end=85, fill=lt, width=1)
    P(d, [(36, 6), (44, 2), (43, 12)], md, ol)                    # arrowhead
    d.point((40, 6), fill=lt)
    flame(d, 11, 31, 6)


def draw_fireball_beam_piercing(d):
    beam(d, 2, 45, 23, 4)
    ol, dk, md, lt = FIRE
    d.ellipse([26, 13, 41, 33], outline=ol, width=3)              # pierced ring
    d.ellipse([28, 15, 39, 31], outline=lt, width=1)
    d.point((33, 23), fill=dk)


def draw_fireball_split(d):
    flame(d, 11, 24, 8)
    for cx, cy in ((29, 12), (34, 24), (29, 36)):
        flame(d, cx, cy, 5)


def draw_fireball_split_heavy(d):
    for cx, cy in ((13, 26), (32, 13), (34, 36)):
        flame(d, cx, cy, 8)


def draw_fireball_split_wide(d):
    flame(d, 9, 24, 6)
    for cx, cy in ((31, 7), (37, 24), (31, 41)):
        flame(d, cx, cy, 5)


# prefix -> glyph draw fn; dict order = sheet row order after the 3 committed rows
GLYPHS = {
    "fireball": draw_fireball,
    "mana": draw_mana,
    "bolt": draw_bolt,
    "water": draw_water,
    "frost": draw_frost,
    "hammer": draw_hammer,
    "punch": draw_punch,
    "block": draw_block,
    "summon": draw_summon,
    "water_guided": draw_water_guided,
    "water_seeking": draw_water_seeking,
    "water_tidal": draw_water_tidal,
    "water_barrage": draw_water_barrage,
    "water_bubble": draw_water_bubble,
    "water_splash": draw_water_splash,
    "big_ball": draw_big_ball,
    "heavy_rain": draw_heavy_rain,
    "surging_bubble": draw_surging_bubble,
    "hammer_gambler": draw_hammer_gambler,
    "hammer_leap": draw_hammer_leap,
    "hammer_reaper": draw_hammer_reaper,
    "hammer_rhythm": draw_hammer_rhythm,
    "hammer_titan": draw_hammer_titan,
    "hammer_vortex": draw_hammer_vortex,
    "punch_bubble": draw_punch_bubble,
    "punch_burst": draw_punch_burst,
    "punch_launch": draw_punch_launch,
    "mana_lance": draw_mana_lance,
    "mana_volley": draw_mana_volley,
    "bolt_flurry": draw_bolt_flurry,
    "bolt_heavy": draw_bolt_heavy,
    "fireball_beam": draw_fireball_beam,
    "fireball_beam_heavy": draw_fireball_beam_heavy,
    "fireball_beam_homing": draw_fireball_beam_homing,
    "fireball_beam_long": draw_fireball_beam_long,
    "fireball_beam_piercing": draw_fireball_beam_piercing,
    "fireball_split": draw_fireball_split,
    "fireball_split_heavy": draw_fireball_split_heavy,
    "fireball_split_wide": draw_fireball_split_wide,
}


def main():
    out = Image.new("RGBA", (CW * 7, CH * len(GLYPHS)), (0, 0, 0, 0))
    for i, (key, glyph_fn) in enumerate(GLYPHS.items()):
        tile = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
        glyph_fn(ImageDraw.Draw(tile))
        polish(tile)
        out.paste(tile, (0, CH * i))
    out.save(SHEET)
    print(f"{SHEET}: {out.size}, {len(GLYPHS)} raw-glyph rows")
    print("row order:", ", ".join(f"{i}={k}" for i, k in enumerate(GLYPHS)))


if __name__ == "__main__":
    main()
