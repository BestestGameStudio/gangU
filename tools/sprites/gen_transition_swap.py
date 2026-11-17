#!/usr/bin/env python3
"""Swap one flat fill family for another inside a dualgrid sheet.

Used to derive missing transition sheets without touching mask geometry:
  sand_on_dirt  = grass_on_dirt with the grass fill -> flat sand + dunes
  water_on_grass bg = generated water sheet's sand bg -> flat grass + blades
  water_on_dirt bg  = same -> flat dirt + pebble specks

Colours come from gen_base_fill's family model so shades (dune +-6, wet
stain) all map. Deterministic.

Usage: gen_transition_swap.py <src.png> <dst.png> <from> <to>
  from/to in {grass, sand, dirt}; 'to' gets that family's flat base look.
"""
import sys
import math
import random
from PIL import Image

CELL = 64
BASES = {
    "grass": (66, 118, 58),
    "sand": (216, 188, 132),
    "dirt": (166, 130, 86),
}


def family(px):
    r, g, b = px[:3]
    if g > r + 12 and g > b + 12:
        return "grass"
    if r > 150 and g > 120 and b < r - 40 and abs(r - g) < 70:
        return "sand"  # dirt browns land here too; 'from' picks the tone
    return None


def shade(col, d):
    return tuple(max(0, min(255, v + d)) for v in col)


def near(c1, c2, tol=60):
    return all(abs(a - b) <= tol for a, b in zip(c1, c2))


def swap(src_path, dst_path, frm, to, seed=11):
    random.seed(seed)
    im = Image.open(src_path).convert("RGBA")
    px = im.load()
    W, H = im.size
    base_from, base_to = BASES[frm], BASES[to]
    stained_from = tuple(int(v * 0.78) for v in base_from)
    stained_to = tuple(int(v * 0.78) for v in base_to)
    swapped = {}
    for y in range(H):
        for x in range(W):
            p = px[x, y]
            if p[3] < 200 or family(p) != frm:
                continue
            c = p[:3]
            if not near(c, base_from, 70) and not near(c, stained_from, 60):
                continue
            if near(c, stained_from, 55) and not near(c, base_from, 45):
                px[x, y] = stained_to + (255,)
            else:
                px[x, y] = base_to + (255,)
            swapped[(x, y)] = True

    # Detail pass for the new surface, matching gen_base_fill's look.
    if to == "grass":
        dark, light = shade(base_to, -14), shade(base_to, +12)
        for cy in range(0, H, CELL):
            for cx in range(0, W, CELL):
                # Frame-relative seed: stacked animation frames get identical
                # bg detail (no shimmer between frames).
                rng = random.Random((seed, cx, cy % (CELL * 4)))
                for _ in range(rng.randint(7, 11)):
                    x = cx + rng.randrange(CELL - 3)
                    y = cy + rng.randrange(2, CELL)
                    if not swapped.get((x, y)):
                        continue
                    h = rng.choice((2, 2, 3))
                    col = dark if rng.random() < 0.6 else light
                    for k in range(h):
                        if swapped.get((x, y - k)):
                            px[x, y - k] = (light if k == h - 1 else col) + (255,)
    elif to in ("sand", "dirt"):
        up, down = shade(base_to, +6), shade(base_to, -6)
        phases = {}
        for cy in range(0, H, CELL):
            for cx in range(0, W, CELL):
                rng = random.Random((seed, "dune", cx, cy % (CELL * 4)))
                phases[(cx, cy)] = tuple(rng.uniform(0, 6.283) for _ in range(3))
        for (x, y) in list(swapped):
            a, b, c = phases[(x // CELL * CELL, (y // CELL * CELL) % (CELL * 4))]
            v = (math.sin(x * 0.09 + a) + math.sin(y * 0.12 + b)
                 + math.sin((x + y) * 0.05 + c)) / 3.0
            if v > 0.45:
                px[x, y] = up + (255,)
            elif v < -0.45:
                px[x, y] = down + (255,)

    im.save(dst_path, optimize=True)
    print(f"{dst_path}: {frm}->{to} swapped={len(swapped)}")


if __name__ == "__main__":
    swap(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
