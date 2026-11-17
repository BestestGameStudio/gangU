#!/usr/bin/env python3
"""Flatten grass/sand base fills in dualgrid terrain sheets.

Mitra (#812 follow-up): base tiles read as "a big blob repeated". This
rewrites only the grass/sand FILL regions of a sheet: one flat colour per
surface plus sparse, low-contrast detail (1-2 px grass-blade tufts; soft
sand dune shading). Edge silhouettes, other surfaces and alpha are kept.

Usage: gen_base_fill.py <sheet.png> [--seed N]  (in place; deterministic)
"""
import sys
import random
from PIL import Image, ImageFilter

CELL = 64


def colour_family(px):
    r, g, b = px[:3]
    if g > r + 12 and g > b + 12:
        return "grass"
    if r > 150 and g > 120 and b < r - 40 and abs(r - g) < 70:
        return "sand"
    return None


def dominant(img, fam):
    from collections import Counter
    c = Counter()
    for px in img.getdata():
        if px[3] > 200 and colour_family(px) == fam:
            c[px[:3]] += 1
    # mid-green / mid-sand: take the most common mid-tone, not the darkest
    for col, _ in c.most_common(8):
        r, g, b = col
        if fam == "grass" and 60 <= g <= 200:
            return col
        if fam == "sand" and 150 <= r <= 245:
            return col
    return c.most_common(1)[0][0] if c else None


def shade(col, d):
    return tuple(max(0, min(255, v + d)) for v in col)


def rework(path, seed=7):
    random.seed(seed)
    im = Image.open(path).convert("RGBA")
    px = im.load()
    W, H = im.size
    # Rework only families that cover a real share of the sheet; minority
    # colours (flowers, pebbles, dirt patches) are decorations - keep them.
    from collections import Counter
    cover = Counter()
    opaque = 0
    for p in im.getdata():
        if p[3] < 200:
            continue
        opaque += 1
        f = colour_family(p)
        if f:
            cover[f] += 1
    grass_base = dominant(im, "grass") if cover["grass"] >= 0.25 * opaque else None
    sand_base = dominant(im, "sand") if cover["sand"] >= 0.25 * opaque else None

    # Pass 1: flatten family pixels to the base colour.
    fam_map = {}
    for y in range(H):
        for x in range(W):
            p = px[x, y]
            if p[3] < 200:
                continue
            f = colour_family(p)
            if f == "grass" and grass_base:
                px[x, y] = grass_base + (255,)
                fam_map[(x, y)] = "grass"
            elif f == "sand" and sand_base:
                px[x, y] = sand_base + (255,)
                fam_map[(x, y)] = "sand"

    # Pass 1b: remove the original sand "+" marks (Mitra: looks weird).
    # Small dark-brown clusters enclosed by sand; keep gray pebbles.
    if sand_base:
        seen = set()
        for y in range(H):
            for x in range(W):
                if (x, y) in seen:
                    continue
                p = px[x, y]
                r, g, b = p[:3]
                if p[3] < 200 or not (r > b + 20 and r + g + b < 480) or colour_family(p) == "sand":
                    continue
                comp = [(x, y)]
                stack = [(x, y)]
                seen.add((x, y))
                ok = True
                while stack:
                    cx, cy = stack.pop()
                    for nx, ny in ((cx+1,cy),(cx-1,cy),(cx,cy+1),(cx,cy-1)):
                        if not (0 <= nx < W and 0 <= ny < H) or (nx, ny) in seen:
                            continue
                        q = px[nx, ny]
                        qr, qg, qb = q[:3]
                        if q[3] >= 200 and qr > qb + 20 and qr + qg + qb < 480 and colour_family(q) != "sand":
                            seen.add((nx, ny))
                            comp.append((nx, ny))
                            stack.append((nx, ny))
                    if len(comp) > 12:
                        ok = False
                        break
                if ok and len(comp) <= 12:
                    for cx, cy in comp:
                        px[cx, cy] = sand_base + (255,)

    # Pass 2: sparse grass-blade tufts (1-2 px, +-10 shade) per 64px cell.
    if grass_base:
        dark, light = shade(grass_base, -14), shade(grass_base, +12)
        for cy in range(0, H, CELL):
            for cx in range(0, W, CELL):
                rng = random.Random((seed, cx, cy))
                for _ in range(rng.randint(7, 11)):
                    x = cx + rng.randrange(CELL - 3)
                    y = cy + rng.randrange(2, CELL)
                    if fam_map.get((x, y)) != "grass":
                        continue
                    # Taller blades (Mitra): a 2-3 px vertical stalk, tip lighter.
                    h = rng.choice((2, 2, 3))
                    col = dark if rng.random() < 0.6 else light
                    for k in range(h):
                        if fam_map.get((x, y - k)) == "grass":
                            px[x, y - k] = (light if k == h - 1 else col) + (255,)
                    if rng.random() < 0.5 and fam_map.get((x + 1, y - 1)) == "grass":
                        px[x + 1, y - 1] = dark + (255,)

    # Pass 3: sand dune shading - soft non-periodic patches: per-cell random
    # phases over a few broad sine fields keep dunes drifting instead of
    # striping (kept subtle, +-6).
    import math
    if sand_base:
        up, down = shade(sand_base, +6), shade(sand_base, -6)
        phases = {}
        for cy in range(0, H, CELL):
            for cx in range(0, W, CELL):
                rng = random.Random((seed, "dune", cx, cy))
                phases[(cx, cy)] = tuple(rng.uniform(0, 6.283) for _ in range(3))
        for (x, y), f in list(fam_map.items()):
            if f != "sand":
                continue
            a, b, c = phases[(x // CELL * CELL, y // CELL * CELL)]
            v = (math.sin(x * 0.09 + a) + math.sin(y * 0.12 + b)
                 + math.sin((x + y) * 0.05 + c)) / 3.0
            if v > 0.45:
                px[x, y] = up + (255,)
            elif v < -0.45:
                px[x, y] = down + (255,)

    im.save(path, optimize=True)
    print(f"{path}: grass={grass_base} sand={sand_base} fill_px={len(fam_map)}")


if __name__ == "__main__":
    seed = 7
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--seed" in sys.argv:
        seed = int(sys.argv[sys.argv.index("--seed") + 1])
    for p in args:
        rework(p, seed)
