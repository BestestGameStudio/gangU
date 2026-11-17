#!/usr/bin/env python3
"""Draw assets/sprites/stone_hammer.png, the Stone Hammer spell art (#839).

Atlas 64x32 art px (drawn at 2x in game, so the head is 30x18 world px, the
size of the old code-drawn rectangle):
  (0,0)   15x9  hammer head, flat striking faces, lit upper left
  (16,0)  2x4   handle strip, stretched along the swing (wood, shaded right)
  (24,0)  32x32 radial crack star, centred, drawn under the dust ring
Palette matches the old code colours (STONE, STONE_DARK, HANDLE).
usage: python3 tools/sprites/gen_stone_hammer.py
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/sprites/stone_hammer.png")
OUTLINE = (69, 64, 59, 255)
STONE = (148, 140, 128, 255)
LIGHT = (186, 179, 168, 255)
SHADE = (112, 106, 97, 255)
WOOD = (128, 84, 46, 255)
WOOD_DARK = (92, 60, 32, 255)
CRACK = (51, 43, 36, 255)


def head(im, ox, oy):
    for y in range(9):
        for x in range(15):
            edge = x in (0, 14) or y in (0, 8)
            if edge:
                c = OUTLINE
            elif y <= 2:
                c = LIGHT
            elif y >= 6 or x >= 12:
                c = SHADE
            else:
                c = STONE
            im.putpixel((ox + x, oy + y), c)
    # a couple of chips so it reads as stone, not a block
    for x, y in ((4, 4), (9, 5), (6, 3)):
        im.putpixel((ox + x, oy + y), SHADE)


def handle(im, ox, oy):
    for y in range(4):
        im.putpixel((ox, oy + y), WOOD)
        im.putpixel((ox + 1, oy + y), WOOD_DARK)


def cracks(im, ox, oy):
    # 7 radial cracks, same angles as the old lines (TAU*i/7 + 0.4), 1 px wide
    import math
    cx = cy = 15.5
    for i in range(7):
        a = math.tau * i / 7 + 0.4
        r0 = 0.15 * 16 / 0.8
        r1 = (0.6 + 0.2 * math.sin(i * 1.7)) * 16 / 0.8
        n = int(r1 - r0) * 2
        for s in range(n + 1):
            r = r0 + (r1 - r0) * s / n
            x, y = int(round(cx + math.cos(a) * r)), int(round(cy + math.sin(a) * r))
            if 0 <= x < 32 and 0 <= y < 32:
                im.putpixel((ox + x, oy + y), CRACK)


def main():
    im = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    head(im, 0, 0)
    handle(im, 16, 0)
    cracks(im, 24, 0)
    im.save(OUT)


if __name__ == "__main__":
    main()
