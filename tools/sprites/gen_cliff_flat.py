"""#820: flatten the rock side of dualgrid_cliff_on_sand.png.

Every low-saturation grey/brown rock pixel becomes one flat colour, so the
rock-meets-sand seam matches the flat rock the engine draws in the cliff band
(overworld_cliff_rock.gd). Sand pixels are untouched. Deterministic; run once
from the repo root:  python3 tools/sprites/gen_cliff_flat.py
"""
import os

import numpy as np
from PIL import Image

ROCK_BASE = (88, 82, 88)
PATH = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sprites", "terrain", "dualgrid_cliff_on_sand.png")


def main():
    im = Image.open(PATH).convert("RGBA")
    a = np.array(im)
    rgb = a[..., :3].astype(int)
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    sand = (rgb[..., 0] - rgb[..., 2]) > 40 # warm, saturated: sand
    rock = (a[..., 3] > 0) & ~sand & ((mx - mn) < 60) & (mx < 190)
    a[rock, :3] = ROCK_BASE
    Image.fromarray(a).save(PATH)
    print("flattened", int(rock.sum()), "rock pixels")


if __name__ == "__main__":
    main()
