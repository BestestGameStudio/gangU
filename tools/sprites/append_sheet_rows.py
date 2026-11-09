"""Append new spell rows to an existing gangU sprite sheet (first used for
#302 bolt upgrade sprites; see specs/spell_upgrades_bolt_rows.json).

pack_alpha_strip.py builds a sheet from scratch; this tool extends one in
place: it appends `start_row`-onward rows of cells cut from a source strip
with the same premultiplied-alpha box downsample, then patches the matching
SpriteFrames .tres with AtlasTexture sub-resources and
"<name>_start" (one-shot) + "<name>" (looping flight) animations following
the #289 convention (6 cells per row: start = cells 0-2, flight = 3,4,5,4).

Usage (needs Pillow + numpy; run with python3 -I from a venv):
  python3 -I tools/sprites/append_sheet_rows.py pack SPEC.json STRIP.png SHEET.png --tres OUT.tres

Spec keys: scale, cell_w, cell_h, alpha_floor, columns, start_row,
texture_path, and rows: [{name, windows: [[x, y] ...], cell_fill: [f..]}].
Each window is the top-left of a cell_w*scale x cell_h*scale source rect;
cell_fill maps the row's cells onto window indices.
"""
import importlib.util
import json
import os
import re
import sys

import numpy as np
from PIL import Image


def _pack_alpha_strip():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pack_alpha_strip.py")
    spec = importlib.util.spec_from_file_location("pack_alpha_strip", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pack(spec, strip, sheet_path):
    pas = _pack_alpha_strip()
    src = np.asarray(Image.open(strip).convert("RGBA"))
    sc, cw, ch = spec["scale"], spec["cell_w"], spec["cell_h"]
    cols, start = spec["columns"], spec["start_row"]
    sheet = np.asarray(Image.open(sheet_path).convert("RGBA")).copy()
    assert sheet.shape[1] == cw * cols, "sheet width mismatch"
    rows = spec["rows"]
    need_h = ch * (start + len(rows))
    if sheet.shape[0] < need_h:
        grown = np.zeros((need_h, sheet.shape[1], 4), dtype=np.uint8)
        grown[: sheet.shape[0]] = sheet
        sheet = grown
    for ri, row in enumerate(rows):
        fills = row["cell_fill"]
        assert len(fills) == cols, "one fill entry per cell"
        for ci, fi in enumerate(fills):
            x, y = row["windows"][fi][:2]
            window = src[y : y + ch * sc, x : x + cw * sc].copy()
            assert window.shape[0] == ch * sc and window.shape[1] == cw * sc, "window off the strip"
            sheet[(start + ri) * ch : (start + ri + 1) * ch, ci * cw : (ci + 1) * cw] = pas.downsample(
                window, sc, spec["alpha_floor"]
            )
    Image.fromarray(sheet, "RGBA").save(sheet_path)
    print("wrote", sheet_path, sheet.shape[1], "x", sheet.shape[0])


def patch_tres(spec, tres_path):
    cw, ch, cols, start = spec["cell_w"], spec["cell_h"], spec["columns"], spec["start_row"]
    with open(tres_path) as f:
        text = f.read()
    subs = []
    anims = []
    for ri, row in enumerate(spec["rows"]):
        r = start + ri
        for c in range(cols):
            subs.append(
                '\n[sub_resource type="AtlasTexture" id="AtlasTexture_r%dc%d"]\n'
                "atlas = ExtResource(\"1_sheet\")\nregion = Rect2(%d, %d, %d, %d)\n"
                % (r, c, c * cw, r * ch, cw, ch)
            )
        ids = ["AtlasTexture_r%dc%d" % (r, c) for c in range(cols)]
        def anim(name, cell_idx, fps, loop):
            frames = ", ".join(
                '{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % ids[i] for i in cell_idx
            )
            return (
                ', {\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}'
                % (frames, "true" if loop else "false", name, fps)
            )
        anims.append(anim("%s_start" % row["name"], [0, 1, 2], 18.0, False))
        anims.append(anim(row["name"], [3, 4, 5, 4], 12.0, True))
    m = re.search(r"\[gd_resource type=\"SpriteFrames\" load_steps=(\d+) format=3\]", text)
    text = text.replace(m.group(0), m.group(0).replace(m.group(1), str(int(m.group(1)) + len(subs))))
    # Sub-resources go before the [resource] block; new animations append at
    # the end of the animations array (which closes with "]" just before EOF).
    head, res = text.split("[resource]", 1)
    head = head.rstrip("\n") + "\n" + "".join(subs) + "\n"
    res = res.rstrip("\n")
    assert res.endswith("]"), "animations array must close the resource"
    res = res[:-1] + "".join(anims) + "]\n"
    with open(tres_path, "w") as f:
        f.write(head + "[resource]" + res)
    print("patched", tres_path, "+%d sub-resources, +%d animations" % (len(subs), len(anims)))


def main(argv):
    if len(argv) == 7 and argv[1] == "pack" and argv[5] == "--tres":
        with open(argv[2]) as f:
            spec = json.load(f)
        pack(spec, argv[3], argv[4])
        patch_tres(spec, argv[6])
        return
    print(__doc__)
    sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
