"""Generic concept-board -> Godot sprite sheet extractor (generalized from
extract_mustache_warrior.py, #177).

Concept boards (e.g. images attached to GitHub issues) are presentation art:
labels, panels, a flat background and uneven spacing. This tool cuts the
drawn frames out, keys out the background, anchors every frame (horizontal
anchor + feet baseline), downsamples by an integer factor and packs a uniform
grid that Godot AtlasTextures can address. Optionally it also writes a
SpriteFrames .tres for the packed sheet.

Usage (needs Pillow + numpy; run with python3 -I from a venv):
  # 1. find frame x-ranges inside a horizontal band of the board
  python3 -I tools/sprites/extract_frames.py segment BOARD.png --band X0 X1 Y0 Y1
  # 2. pack the sheet (and optionally the SpriteFrames) from a JSON spec
  python3 -I tools/sprites/extract_frames.py pack SPEC.json BOARD.png OUT.png [--tres OUT.tres]

Spec format: see tools/sprites/specs/mustache_warrior.json. Keys:
  scale, cell_w, cell_h, baseline, bg [r,g,b], key_dist,
  rows: [{name, y: [y0,y1], mode: bbox|anchor|center,
          frames: [[x0, x1, anchor_x_or_null], ...]}],
  texture_path (res:// path of OUT.png, for --tres),
  animations: [{name, speed, loop, frames: [[row, col, duration], ...]}]
anchor mode uses the hand-measured anchor_x (body / face centre in board px)
so slash / spin / speed-line FX do not skew the centre; bbox mode centres
on the art's bounding box; center mode centres props vertically in the cell.

The --tres output deliberately carries NO uid attributes: never hand-write
Godot UIDs. Godot resolves the texture by path and assigns UIDs itself.
"""
import json
import sys

import numpy as np
from PIL import Image


def art_mask(rgb, bg, key_dist):
    return np.abs(rgb.astype(int) - np.array(bg)).sum(2) > key_dist


def segment(board, x0, x1, y0, y1, bg, key_dist, min_gap=5):
    a = np.asarray(Image.open(board).convert("RGB"))
    m = art_mask(a[y0:y1, x0:x1], bg, key_dist)
    cols = m.any(0)
    runs, s, e, gap = [], None, None, 0
    for i, c in enumerate(cols):
        if c:
            if s is None:
                s = i
            e, gap = i, 0
        elif s is not None:
            gap += 1
            if gap >= min_gap:
                runs.append((s, e))
                s = None
    if s is not None:
        runs.append((s, e))
    for s, e in runs:
        if e - s < 4:
            continue
        rows = np.where(m[:, s:e + 1].any(1))[0]
        print(f"[{x0 + s}, {x0 + e}]  y {y0 + rows[0]}..{y0 + rows[-1]}")


def cut(src, spec, y0, y1, x0, x1, anchor_x, mode):
    pad = 6
    left = x0 - pad
    rgb = src[y0:y1, left:x1 + pad + 1, :3]
    mask = art_mask(rgb, spec["bg"], spec["key_dist"])
    ys, xs = np.nonzero(mask)
    bx0, bx1, by1 = xs.min(), xs.max(), ys.max()
    ax = (anchor_x - left) if anchor_x is not None else (bx0 + bx1) / 2.0
    if mode == "center":
        by1 = (ys.min() + ys.max()) / 2.0 + (spec["baseline"] - spec["cell_h"] / 2) * spec["scale"]
    return rgb, mask, ax, by1


def place(spec, rgb, mask, ax, by1):
    sc, cw, ch = spec["scale"], spec["cell_w"], spec["cell_h"]
    bw, bh = cw * sc, ch * sc
    canvas = np.zeros((bh, bw, 4), dtype=float)
    ox = int(round(bw / 2 - ax))
    oy = int(round(spec["baseline"] * sc - by1 - 1))
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
    c = canvas.reshape(ch, sc, cw, sc, 4)
    a = c[..., 3].sum(axis=(1, 3))
    col = (c[..., :3] * c[..., 3:4]).sum(axis=(1, 3)) / np.maximum(a, 1e-6)[..., None]
    alpha = (a / (sc * sc)) >= 0.45
    out = np.zeros((ch, cw, 4), dtype=np.uint8)
    out[..., :3] = np.clip(col, 0, 255).astype(np.uint8)
    out[..., 3] = np.where(alpha, 255, 0)
    out[~alpha, :3] = 0
    return out


def pack(spec, board, out_png):
    src = np.asarray(Image.open(board).convert("RGBA"))
    cw, ch, rows = spec["cell_w"], spec["cell_h"], spec["rows"]
    cols = max(len(r["frames"]) for r in rows)
    sheet = np.zeros((ch * len(rows), cw * cols, 4), dtype=np.uint8)
    for ri, row in enumerate(rows):
        y0, y1 = row["y"]
        for i, (x0, x1, anchor_x) in enumerate(row["frames"]):
            rgb, mask, ax, by1 = cut(src, spec, y0, y1, x0, x1, anchor_x, row["mode"])
            sheet[ri * ch:(ri + 1) * ch, i * cw:(i + 1) * cw] = place(spec, rgb, mask, ax, by1)
        print(f"row {ri}: {row['name']} x{len(row['frames'])}")
    Image.fromarray(sheet, "RGBA").save(out_png)
    print("wrote", out_png, sheet.shape[1], "x", sheet.shape[0])


def write_tres(spec, out_tres):
    cw, ch = spec["cell_w"], spec["cell_h"]
    anims = spec["animations"]
    cells = sorted({(r, c) for a in anims for r, c, _ in a["frames"]})
    out = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]\n' % (len(cells) + 2),
           '[ext_resource type="Texture2D" path="%s" id="1_sheet"]\n' % spec["texture_path"]]
    for r, c in cells:
        out.append('[sub_resource type="AtlasTexture" id="AtlasTexture_r%dc%d"]\n'
                   'atlas = ExtResource("1_sheet")\nregion = Rect2(%d, %d, %d, %d)\n'
                   % (r, c, c * cw, r * ch, cw, ch))
    blocks = []
    for a in anims:
        frames = ", ".join('{\n"duration": %s,\n"texture": SubResource("AtlasTexture_r%dc%d")\n}'
                           % (repr(float(d)), r, c) for r, c, d in a["frames"])
        blocks.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}'
                      % (frames, "true" if a["loop"] else "false", a["name"], repr(float(a["speed"]))))
    out.append("[resource]\nanimations = [%s]\n" % ", ".join(blocks))
    with open(out_tres, "w") as f:
        f.write("\n".join(out))
    print("wrote", out_tres)


def main(argv):
    if len(argv) >= 7 and argv[1] == "segment" and argv[3] == "--band":
        x0, x1, y0, y1 = map(int, argv[4:8])
        segment(argv[2], x0, x1, y0, y1, [21, 18, 28], 60)
        return
    if len(argv) >= 5 and argv[1] == "pack":
        with open(argv[2]) as f:
            spec = json.load(f)
        pack(spec, argv[3], argv[4])
        if "--tres" in argv:
            write_tres(spec, argv[argv.index("--tres") + 1])
        return
    print(__doc__)
    sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
