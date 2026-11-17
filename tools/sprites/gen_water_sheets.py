"""Generate the overworld water dual-grid sheets (issue: world-edge water,
south beach + waves). Frames are stacked vertically: each sheet is
256 x (256 * FRAMES), frame f at y = f * 256, 16 dual-grid cells of 64 px
per frame (mask = foreground-corner bits TL=1 TR=2 BR=4 BL=8, row-major).

Outputs:
  assets/sprites/terrain/dualgrid_water_on_sand.png  - water on sand (beach)
  assets/sprites/terrain/dualgrid_water_on_cliff.png - water at the cliff foot

Method: reuse the geometry of the shipped sheets (dualgrid_grass_on_sand,
dualgrid_cliff_on_grass) so the shorelines match the existing art exactly -
the grass side becomes animated water. Water texture/foam: gen_water_tex
(slynyrd blob-network lines, wolthera expand/contract foam + underwave,
wet-sand / waterline stain on the land side). Deterministic, no RNG state.

Usage (Pillow + numpy):
  python3 -I tools/sprites/gen_water_sheets.py
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_water_tex import (FRAMES, LINE, SPARKLE, banded, foam_color,
                           wave_line, sparkle, _hash2, _vnoise)

CELL = 64
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
TERRAIN = os.path.join(ROOT, "assets", "sprites", "terrain")


def load(name):
    return np.asarray(Image.open(os.path.join(TERRAIN, name)).convert("RGB")).astype(np.int16)


def chamfer_dt(mask):
    """Approximate euclidean distance to the nearest True pixel (px)."""
    INF = 10 ** 6
    h, w = mask.shape
    d = np.where(mask, 0.0, INF)
    # forward pass
    for y in range(h):
        for x in range(w):
            best = d[y, x]
            if x > 0:
                best = min(best, d[y, x - 1] + 1.0)
            if y > 0:
                best = min(best, d[y - 1, x] + 1.0)
                if x > 0:
                    best = min(best, d[y - 1, x - 1] + 1.4142)
                if x < w - 1:
                    best = min(best, d[y - 1, x + 1] + 1.4142)
            d[y, x] = best
    # backward pass
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            best = d[y, x]
            if x < w - 1:
                best = min(best, d[y, x + 1] + 1.0)
            if y < h - 1:
                best = min(best, d[y + 1, x] + 1.0)
                if x < w - 1:
                    best = min(best, d[y + 1, x + 1] + 1.4142)
                if x > 0:
                    best = min(best, d[y + 1, x - 1] + 1.4142)
            d[y, x] = best
    return d


def grass_mask(cell):
    """True where the pixel is the grass/water side (green family)."""
    r, g, b = cell[..., 0], cell[..., 1], cell[..., 2]
    return (g - r) > 20


def rock_mask(cell):
    """True where the pixel is the cliff rock side (keep as-is)."""
    mx = cell.max(axis=2)
    mn = cell.min(axis=2)
    return ((mx - mn) < 40) & (mx < 170)


def gen_sheet(src_name, out_name, land_kind):
    """land_kind: 'sand' (wet-sand band) or 'cliff' (waterline stain)."""
    src = load(src_name)
    out = np.zeros((256 * FRAMES, 256, 3), dtype=np.uint8)
    for mask in range(16):
        # Output bits are water corners. In the sand source the bits are
        # grass corners (1:1); in the cliff source they are cliff corners,
        # so the geometry lives in the inverted cell.
        src_mask = mask if land_kind == "sand" else mask ^ 15
        cx, cy = (src_mask % 4) * CELL, (src_mask // 4) * CELL
        cell = src[cy:cy + CELL, cx:cx + CELL]
        # Draw into the OUTPUT cell position.
        ox, oy = (mask % 4) * CELL, (mask // 4) * CELL
        # Green family becomes water, but only the component connected to
        # a water corner of the cell: moss pockets inside solid cliff stay
        # rock (otherwise every all-cliff tile grows white foam flecks).
        green = grass_mask(cell)
        water = np.zeros_like(green)
        corners = [(0, 0), (CELL - 1, 0), (CELL - 1, CELL - 1), (0, CELL - 1)]
        stack = [(corners[k][0], corners[k][1]) for k in range(4)
                 if mask & (1 << k) and green[corners[k][1], corners[k][0]]]
        while stack:
            x, y = stack.pop()
            if x < 0 or y < 0 or x >= CELL or y >= CELL or water[y, x] or not green[y, x]:
                continue
            water[y, x] = True
            stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
        keep = ~water
        water = ~keep
        if not water.any():
            for f in range(FRAMES):
                out[f * 256 + oy:f * 256 + oy + CELL, ox:ox + CELL] = cell.astype(np.uint8)
            continue
        dist_land = chamfer_dt(keep)          # water px: distance to land
        dist_water = chamfer_dt(water)        # land px: distance to water
        full = bool(water.all())
        yy, xx = np.mgrid[0:CELL, 0:CELL]
        # Global coords keep the noise fields continuous across tiles.
        gx, gy = xx + ox, yy + oy
        for f in range(FRAMES):
            frame_img = cell.copy()
            if full:
                depth = 18.0 + np.vectorize(lambda a, b: _vnoise(a / 22.0, b / 22.0, 51))(gx, gy) * 22.0
            else:
                depth = dist_land
            # base bands (dithered at the edges)
            base = np.empty((CELL, CELL, 3), dtype=np.int16)
            for i in range(CELL):
                for j in range(CELL):
                    base[i, j] = banded(int(gx[i, j]), int(gy[i, j]), float(depth[i, j]))
            frame_img[water] = base[water]
            # blob-network lines + sparkles (global coords)
            for i in range(CELL):
                for j in range(CELL):
                    if not water[i, j]:
                        continue
                    if not full and dist_land[i, j] <= 8.0:
                        continue  # foam zone owns the shore pixels
                    if wave_line(float(gx[i, j]), float(gy[i, j]), f):
                        frame_img[i, j] = LINE
                    elif sparkle(int(gx[i, j]), int(gy[i, j]), f):
                        frame_img[i, j] = SPARKLE
            # foam at the shoreline
            if not full:
                for i in range(CELL):
                    for j in range(CELL):
                        if not water[i, j]:
                            continue
                        fc = foam_color(float(dist_land[i, j]), int(gx[i, j]), int(gy[i, j]), f)
                        if fc is not None:
                            frame_img[i, j] = fc
                # land-side shore effects
                if land_kind == "sand":
                    wet = (~water) & (dist_water < 7.0 + (f % 2))
                    frame_img[wet] = (frame_img[wet] * 0.78).astype(np.int16)
                else:
                    stain = (~water) & (dist_water < 5.0)
                    dark = np.array((40, 44, 56), dtype=np.int16)
                    frame_img[stain] = (frame_img[stain] * 0.6 + dark * 0.4).astype(np.int16)
            out[f * 256 + oy:f * 256 + oy + CELL, ox:ox + CELL] = np.clip(frame_img, 0, 255).astype(np.uint8)
        print(out_name, "mask", mask, "water px", int(water.sum()))
    Image.fromarray(out).save(os.path.join(TERRAIN, out_name))
    print("wrote", out_name, out.shape)


def main():
    gen_sheet("dualgrid_grass_on_sand.png", "dualgrid_water_on_sand.png", "sand")
    gen_sheet("dualgrid_cliff_on_grass.png", "dualgrid_water_on_cliff.png", "cliff")


if __name__ == "__main__":
    main()
