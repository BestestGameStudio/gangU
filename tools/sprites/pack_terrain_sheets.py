"""Terrain art packer: slices the two AI-generated terrain sheets into
Godot-ready 64x64 atlases (first used for the terrain art pass after #448).

Inputs (committed under tools/sprites/sources/, a .gdignore'd folder so
Godot never imports them):
  terrain_tiles_sheet.webp   - floors (11 rows x 4) + autotile sets
                               (7 rows x 13 pieces), cells split by thin
                               transparent grid gaps, NOT pixel exact
                               (~83x85 px floor cells, ~81x74 px autotile
                               cells).
  terrain_objects_sheet.webp - trees / pines / stone block on a
                               transparent background (8 x 6 cells of
                               ~181 px, faint near-white fringe pixels).

Outputs:
  assets/sprites/terrain_tiles.png    16 x 25 cells of 64x64, opaque.
    rows 0-10: floor sets, cols 0-3 = the sheet's 4 variants (water: the
               4 frames of its loop), in TerrainArt.FLOOR_ROWS order.
    rows 11-24: two rows per autotile set (A uses the sheet's first corner
               pieces, B its second corner pieces), col = exposed-side
               mask (N=1, E=2, S=4, W=8; mask 0 = interior).
  assets/sprites/terrain_objects.png  8 x 6 cells of 80x80, transparent
    (drawn centred on a 64 px game cell).
    rows: tree spring / summer / autumn / winter, pine, block; cols 0-3
    idle variants, cols 4-7 destroy sequence (pine: 4 variants only).

Usage (Pillow + numpy, from a venv):
  python3 -I tools/sprites/pack_terrain_sheets.py SOURCES_DIR OUT_DIR

Grid detection: each sheet's cell lines are predicted from its outer
bounds and snapped to the local alpha minimum (the grid gaps are
transparent), then every cell interior is box-resampled to 64x64.
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

CELL = 64
# Object cells are larger than a game cell so canopies overhang their
# neighbours a little (Godot centres an oversized tile on its cell).
OBJ = 80

FLOOR_NAMES = ["ground", "grass_spring", "grass_summer", "grass_autumn",
               "grass_winter", "meadow", "scree", "snow", "ice", "mud", "water"]
# Autotile sets in sheet order; base = what an interior (mask 0) cell is
# made of: "fill" = the sheet's full piece, "bg" = the set's flat
# background colour (chasm: the pit).
AUTOTILE_SETS = [("obstacle_slate", "fill"), ("obstacle_brown", "fill"),
                 ("obstacle_purple", "fill"), ("obstacle_green", "fill"),
                 ("mountain", "fill"), ("cliff", "fill"), ("chasm", "bg")]
N, E, S, W = 1, 2, 4, 8
# Exposed side / corner -> (sheet piece, flip vertically). Default: the
# sheet's own order (1 top, 2 bottom, 3 left, 4 right; 5-8 = top-left,
# top-right, bottom-left, bottom-right corners, 9-12 their alternates).
DEFAULT_SIDES = {N: (1, False), S: (2, False), W: (3, False), E: (4, False)}
DEFAULT_CORNERS = {(N, W): (5, False), (N, E): (6, False), (S, W): (7, False), (S, E): (8, False)}
# Cliff: the sheet's "top" pieces are grass over a dirt face. Seen top
# down a cliff face shows on its SOUTH side, so those pieces are used where
# the south side is exposed, and the thin grass-lip pieces (sheet bottom
# ones, flipped) where the north side is.
CLIFF_SIDES = {N: (2, True), S: (1, False), W: (3, False), E: (4, False)}
CLIFF_CORNERS = {(N, W): (7, True), (N, E): (8, True), (S, W): (5, False), (S, E): (6, False)}


def snap_lines(alpha_profile, predicted, radius=6):
    out = []
    for p in predicted:
        lo = max(0, int(round(p)) - radius)
        hi = min(len(alpha_profile), int(round(p)) + radius + 1)
        out.append(lo + int(np.argmin(alpha_profile[lo:hi])))
    return out


def cut(img, x0, x1, y0, y1, inset=2):
    # Trim the predicted box until every edge row/column is fully opaque
    # (the gaps and the sheet's outer margin are transparent and carry
    # garbage RGB), then drop `inset` more px of the darker line fringe.
    a = np.asarray(img)[:, :, 3].astype(float)
    while x0 < x1 and np.median(a[y0:y1 + 1, x0]) < 245:
        x0 += 1
    while x1 > x0 and np.median(a[y0:y1 + 1, x1]) < 245:
        x1 -= 1
    while y0 < y1 and np.median(a[y0, x0:x1 + 1]) < 245:
        y0 += 1
    while y1 > y0 and np.median(a[y1, x0:x1 + 1]) < 245:
        y1 -= 1
    box = (x0 + inset, y0 + inset, x1 - inset + 1, y1 - inset + 1)
    return img.crop(box).resize((CELL, CELL), Image.BOX, reducing_gap=None)


def slice_tiles_sheet(path):
    img = Image.open(path).convert("RGBA")
    a = np.asarray(img)[:, :, 3].astype(float)
    # floors: 4 cols x 11 rows in the top-left block
    fx = snap_lines(a[0:930, :].mean(0), np.linspace(5, 338, 5))
    fy = snap_lines(a[:, 0:330].mean(1), np.linspace(3, 944, 12))
    floors = []
    for r in range(11):
        floors.append([cut(img, fx[c], fx[c + 1], fy[r], fy[r + 1]) for c in range(4)])
    # autotiles: 13 cols x 7 rows below
    bx = snap_lines(a[960:, :].mean(0), np.linspace(5, 1063, 14))
    by = snap_lines(a[:, 400:].mean(1), np.linspace(944, 1464, 8))
    sets = []
    for r in range(7):
        # row 0 sits under the water floor row: skip 3 px more of its cyan bleed
        sets.append([cut(img, bx[c], bx[c + 1], by[r] + (3 if r == 0 else 0), by[r + 1], inset=4) for c in range(13)])
    return floors, sets


def flatten_lighting(row, radius=10):
    """Seam fix for floor variants: the generator shaded every cell on its
    own (vignette, slight per-cell brightness), which shows as a grid when
    cells are mixed. Each cell's low-frequency lighting (a wide blur) is
    swapped for the row's mean colour, keeping the small details (tufts,
    cracks, pebbles) so any variant meets any other without a visible
    edge."""
    arrs = [opaque_rgb(c) for c in row]
    mean = np.mean([a.reshape(-1, 3).mean(0) for a in arrs], axis=0)
    out = []
    for a, cell in zip(arrs, row):
        img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")
        # wrap-pad so the blur sees the opposite edge instead of a mirror
        pad = np.pad(a, ((CELL, CELL), (CELL, CELL), (0, 0)), mode="wrap")
        pad_img = Image.fromarray(np.clip(pad, 0, 255).astype(np.uint8), "RGB")
        blur = np.asarray(pad_img.filter(ImageFilter.GaussianBlur(radius))).astype(float)
        low = blur[CELL:2 * CELL, CELL:2 * CELL]
        fixed = a - low + mean
        del img
        out.append(Image.fromarray(np.clip(fixed, 0, 255).astype(np.uint8), "RGB").convert("RGBA"))
    return out


def opaque_rgb(im):
    return np.asarray(im.convert("RGB")).astype(float)


def bg_colour(pieces):
    # Background = what the rim pieces show away from their rim: the top
    # band of the bottom-rim piece and the left band of the right-rim piece.
    p2 = opaque_rgb(pieces[2])[4:22, 8:56].reshape(-1, 3)
    p4 = opaque_rgb(pieces[4])[8:56, 4:22].reshape(-1, 3)
    return np.median(np.concatenate([p2, p4]), axis=0)


def overlay_alpha(rgb, bg, lo=14.0, hi=40.0):
    d = np.sqrt(((rgb - bg) ** 2).sum(2))
    return np.clip((d - lo) / (hi - lo), 0.0, 1.0)


def compose_set(pieces, base_kind, corner_offset, sides=None, corners=None):
    sides = sides or DEFAULT_SIDES
    corners = corners or DEFAULT_CORNERS
    bg = bg_colour(pieces)
    if base_kind == "fill":
        base = opaque_rgb(flatten_lighting([pieces[0]])[0])
        if corner_offset:
            base = base[:, ::-1]  # the B row mirrors the fill: 2 interior looks
    else:
        rng = np.random.default_rng(7)
        base = np.tile(bg, (CELL, CELL, 1)) + rng.normal(0, 2.0, (CELL, CELL, 1))

    def layer(k, flip):
        rgb = opaque_rgb(pieces[k])
        if flip:
            rgb = rgb[::-1]
        return rgb, overlay_alpha(rgb, bg)[:, :, None]

    out = []
    for mask in range(16):
        acc = base.copy()
        covered = 0
        for (s1, s2), (k, flip) in corners.items():
            if mask & s1 and mask & s2:
                rgb, al = layer(k + corner_offset, flip)
                acc = acc * (1 - al) + rgb * al
                covered |= s1 | s2
        for s, (k, flip) in sides.items():
            if mask & s and not covered & s:
                rgb, al = layer(k, flip)
                acc = acc * (1 - al) + rgb * al
        out.append(Image.fromarray(np.clip(acc, 0, 255).astype(np.uint8), "RGB").convert("RGBA"))
    return out


def slice_objects_sheet(path):
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    pw, ph = w / 8.0, h / 6.0
    arr = np.asarray(img).astype(float)
    # Key out the faint near-white fringe the generator left around every
    # object: anything below alpha 96 is background.
    alpha = arr[:, :, 3]
    alpha[alpha < 96] = 0
    # Premultiply so the box downsample never pulls white from cleared
    # pixels into the edge colours.
    pre = arr.copy()
    pre[:, :, :3] *= (alpha[:, :, None] / 255.0)
    pre[:, :, 3] = alpha
    pre_img = Image.fromarray(np.clip(pre, 0, 255).astype(np.uint8), "RGBA")
    # A 160 px window around each cell centre (the art spans ~150 px),
    # 2:1 into an 80 px object cell: a tree's canopy (~70 px) slightly
    # overhangs its 64 px game cell, so a forest reads as one canopy.
    win = 160
    rows = []
    for r in range(6):
        row = []
        for c in range(8):
            cx, cy = (c + 0.5) * pw, (r + 0.5) * ph
            box = (int(round(cx - win / 2)), int(round(cy - win / 2)),
                   int(round(cx + win / 2)), int(round(cy + win / 2)))
            cell = np.asarray(pre_img.crop(box).resize((OBJ, OBJ), Image.BOX)).astype(float)
            al = cell[:, :, 3]
            rgb = np.zeros_like(cell[:, :, :3])
            nz = al > 0
            rgb[nz] = cell[:, :, :3][nz] * 255.0 / al[nz][:, None]
            # Hard pixel edges: a half-covered edge pixel becomes opaque,
            # the rest clear (no grey/white halo against the floor).
            al = np.where(al >= 110, 255, 0)
            rgb[al == 0] = 0
            out = np.dstack([rgb, al])
            row.append(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA"))
        rows.append(row)
    return rows


def main():
    src, out_dir = sys.argv[1], sys.argv[2]
    floors, sets = slice_tiles_sheet(src + "/terrain_tiles_sheet.webp")
    tiles = Image.new("RGBA", (16 * CELL, 25 * CELL), (0, 0, 0, 0))
    for r, row in enumerate(floors):
        for c, cell in enumerate(flatten_lighting(row)):
            tiles.paste(cell, (c * CELL, r * CELL))
    for i, (name, base) in enumerate(AUTOTILE_SETS):
        for v, off in enumerate((0, 4)):
            remap = (CLIFF_SIDES, CLIFF_CORNERS) if name == "cliff" else (None, None)
            for mask, cell in enumerate(compose_set(sets[i], base, off, *remap)):
                tiles.paste(cell, (mask * CELL, (11 + i * 2 + v) * CELL))
    tiles.save(out_dir + "/terrain_tiles.png", optimize=True)

    objs = slice_objects_sheet(src + "/terrain_objects_sheet.webp")
    sheet = Image.new("RGBA", (8 * OBJ, 6 * OBJ), (0, 0, 0, 0))
    for r, row in enumerate(objs):
        for c, cell in enumerate(row):
            if r == 4 and c >= 4:
                continue  # the pine row draws 4 variants only
            sheet.paste(cell, (c * OBJ, r * OBJ))
    sheet.save(out_dir + "/terrain_objects.png", optimize=True)


if __name__ == "__main__":
    main()
