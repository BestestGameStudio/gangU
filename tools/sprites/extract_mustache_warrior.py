"""#177: extract the Mustache Warrior frames from the issue's concept sheet.

The art attached to #177 is a 1536x1024 presentation sheet (labels, panels,
dark background, non-uniform spacing), not an engine-ready grid. This script
cuts each drawn frame out of its panel, keys out the background, anchors it
(body / mustache centre = horizontal anchor, feet = baseline), downsamples it to
game scale and packs everything into a uniform grid that Godot AtlasTextures
can address: assets/sprites/mustache_warrior.png.

Usage (Pillow + numpy):
    python3 tools/sprites/extract_mustache_warrior.py <issue_sheet.png> <out.png>

Output grid: CELL_W x CELL_H px cells, one animation per row, frames left to right
(ROWS below is the source of truth for row order and frame counts).
"""
import sys

import numpy as np
from PIL import Image

SCALE = 3          # source px per game px (source art pixel is ~3.3 px)
CELL_W = 64        # output cell width, game px (room for slash / spin arcs)
CELL_H = 48        # output cell height, game px
BASELINE = 44      # feet line inside the cell, game px
BG = np.array([21, 18, 28])
KEY_DIST = 54      # summed RGB distance from the background that counts as art

# (name, panel y-range, [(x0, x1, anchor_x)], anchor mode)
# Frame x-ranges come from a column-projection segmentation of each panel.
# anchor_x is the hand-measured mustache centre (source px) for frames whose
# slash / spin / speed-line FX would skew a bounding-box centre; None means
# "bounding-box centre" (the clean idle / walk frames and the FX props).
ROWS = [
    ("idle",   (428, 552), [(70, 125, None), (179, 234, None), (287, 341, None), (395, 451, None)], "bbox"),
    ("walk",   (428, 552), [(572, 626, None), (691, 746, None), (808, 865, None), (926, 987, None),
                            (1054, 1109, None), (1174, 1227, None), (1292, 1346, None),
                            (1412, 1466, None)], "bbox"),
    ("attack", (612, 750), [(64, 140, 113), (192, 295, 233), (320, 442, 372), (483, 539, 511)], "anchor"),
    ("hurt",   (612, 750), [(633, 695, 675), (727, 804, 763), (827, 894, 866)], "anchor"),
    ("death",  (612, 750), [(972, 1038, 1005), (1053, 1114, 1079), (1139, 1214, 1168),
                            (1236, 1321, 1253), (1337, 1410, 1350), (1428, 1500, 1452)], "anchor"),
    ("lunge",  (856, 960), [(51, 119, 99), (135, 262, 240)], "anchor"),
    ("spin",   (856, 960), [(309, 409, 363), (424, 528, 469), (546, 647, 590)], "anchor"),
    ("ranged", (856, 960), [(697, 740, 718), (772, 813, 794), (841, 893, 861)], "anchor"),
    # Single-cell props: the ranged orb and the FX elements (centred in-cell).
    ("orb",    (856, 960), [(905, 956, None)], "center"),
    ("fx",     (840, 965), [(1040, 1126, None), (1130, 1235, None), (1255, 1324, None),
                            (1338, 1401, None)], "center"),
]


def art_mask(rgb):
    return np.abs(rgb.astype(int) - BG).sum(2) > KEY_DIST


def cut(src, y0, y1, x0, x1, anchor_x, mode):
    pad = 6
    left = x0 - pad
    crop = src[y0:y1, left:x1 + pad + 1]
    rgb = crop[..., :3]
    mask = art_mask(rgb)
    ys, xs = np.nonzero(mask)
    bx0, bx1, by1 = xs.min(), xs.max(), ys.max()
    ax = (anchor_x - left) if anchor_x is not None else (bx0 + bx1) / 2.0
    if mode == "center":
        by1 = (ys.min() + ys.max()) / 2.0 + (BASELINE - CELL_H / 2) * SCALE
    return rgb, mask, ax, by1


def place(rgb, mask, ax, by1):
    """Downsample one keyed frame into a CELL_W x CELL_H RGBA tile."""
    bw, bh = CELL_W * SCALE, CELL_H * SCALE
    canvas = np.zeros((bh, bw, 4), dtype=float)
    ox = int(round(bw / 2 - ax))
    oy = int(round(BASELINE * SCALE - by1 - 1))
    h, w = mask.shape
    for y in range(h):
        ty = y + oy
        if not (0 <= ty < bh):
            continue
        for x in range(w):
            tx = x + ox
            if 0 <= tx < bw and mask[y, x]:
                canvas[ty, tx, :3] = rgb[y, x]
                canvas[ty, tx, 3] = 1.0
    # Alpha-weighted box filter, then a hard alpha cut so edges stay pixel-crisp.
    c = canvas.reshape(CELL_H, SCALE, CELL_W, SCALE, 4)
    a = c[..., 3].sum(axis=(1, 3))
    col = (c[..., :3] * c[..., 3:4]).sum(axis=(1, 3)) / np.maximum(a, 1e-6)[..., None]
    alpha = (a / (SCALE * SCALE)) >= 0.45
    out = np.zeros((CELL_H, CELL_W, 4), dtype=np.uint8)
    out[..., :3] = np.clip(col, 0, 255).astype(np.uint8)
    out[..., 3] = np.where(alpha, 255, 0)
    out[~alpha, :3] = 0
    return out


def main(src_path, out_path):
    src = np.asarray(Image.open(src_path).convert("RGBA"))
    cols = max(len(r[2]) for r in ROWS)
    sheet = np.zeros((CELL_H * len(ROWS), CELL_W * cols, 4), dtype=np.uint8)
    for row, (name, (y0, y1), frames, mode) in enumerate(ROWS):
        for i, (x0, x1, anchor_x) in enumerate(frames):
            rgb, mask, ax, by1 = cut(src, y0, y1, x0, x1, anchor_x, mode)
            tile = place(rgb, mask, ax, by1)
            sheet[row * CELL_H:(row + 1) * CELL_H, i * CELL_W:(i + 1) * CELL_W] = tile
        print(f"row {row}: {name} x{len(frames)}")
    Image.fromarray(sheet, "RGBA").save(out_path)
    print("wrote", out_path, sheet.shape[1], "x", sheet.shape[0])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
