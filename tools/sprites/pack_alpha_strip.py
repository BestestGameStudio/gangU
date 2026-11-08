"""RGBA sprite strip -> Godot sprite sheet (first used for the #238 upgrade
chevron; see specs/upgrade_chevron.json).

extract_frames.py keys a flat backdrop out of opaque concept boards and cuts
to hard alpha. Sheets that already carry real transparency need neither: this
tool cuts fixed windows and box-downsamples with premultiplied alpha, so soft
glow frames keep their partial alpha.

Usage (needs Pillow + numpy; run with python3 -I from a venv):
  python3 -I tools/sprites/pack_alpha_strip.py pack SPEC.json STRIP.png OUT.png --tres OUT.tres

Spec keys: scale, cell_w, cell_h, alpha_floor (source pixels below this alpha
are dropped first: they are generator noise), origins ([x, y] top-left of each
frame window in strip px), texture_path, animations (as extract_frames.py).
"""
import importlib.util
import json
import os
import sys

import numpy as np
from PIL import Image


def _extract_frames():
    # python3 -I leaves the script directory off sys.path: load by file path.
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "extract_frames.py")
    spec = importlib.util.spec_from_file_location("extract_frames", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def downsample(window, scale, alpha_floor):
    h, w = window.shape[:2]
    rgba = window.astype(float)
    rgba[rgba[..., 3] < alpha_floor] = 0.0
    blocks = rgba.reshape(h // scale, scale, w // scale, scale, 4)
    alpha = blocks[..., 3].sum(axis=(1, 3))
    premultiplied = (blocks[..., :3] * blocks[..., 3:4]).sum(axis=(1, 3))
    out = np.zeros((h // scale, w // scale, 4), dtype=np.uint8)
    out[..., :3] = np.clip(premultiplied / np.maximum(alpha, 1e-6)[..., None], 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(alpha / (scale * scale), 0, 255).astype(np.uint8)
    return out


def pack(spec, strip, out_png):
    src = np.asarray(Image.open(strip).convert("RGBA"))
    sc, cw, ch = spec["scale"], spec["cell_w"], spec["cell_h"]
    origins = spec["origins"]
    sheet = np.zeros((ch, cw * len(origins), 4), dtype=np.uint8)
    for i, (x, y) in enumerate(origins):
        window = src[y:y + ch * sc, x:x + cw * sc]
        sheet[:, i * cw:(i + 1) * cw] = downsample(window, sc, spec["alpha_floor"])
    Image.fromarray(sheet, "RGBA").save(out_png)
    print("wrote", out_png, sheet.shape[1], "x", sheet.shape[0])


def main(argv):
    if len(argv) == 7 and argv[1] == "pack" and argv[5] == "--tres":
        with open(argv[2]) as f:
            spec = json.load(f)
        pack(spec, argv[3], argv[4])
        _extract_frames().write_tres(spec, argv[6])
        return
    print(__doc__)
    sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
