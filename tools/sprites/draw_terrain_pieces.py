"""Bake the painted terrain-piece atlas (option 2: layered pieces, not tiles).

One atlas, two layers with the same layout:
  terrain_pieces_base.png  under characters: trunks, ground shadows, boulders,
                           tuft / flower / pebble clusters
  terrain_pieces_top.png   above characters: tree and pine crowns, bushes, pillars

Layout (read by game/world/terrain/terrain_pieces.gd - keep them in sync):
  CELL 48x64 art px, 8 variants per row, foot (trunk base / ground contact) at
  (24, 56) inside each cell. Rows = TerrainPieces.Kind order:
  0 tree, 1 pine, 2 bush, 3 pillar, 4 boulder, 5 tufts, 6 flowers, 7 pebbles.
  Variants grow with the index (tree/pine/pillar/boulder) so the game can
  pick a variant whose size fits a decor radius.

The painters are the landscape sample's (draw_landscape_sample.py), so pieces
match the painted landscape exactly: per-clump lit crowns, tiered pines,
mossy pillar caps, light from the upper left.

Usage: uv run --with pillow --with numpy python tools/sprites/draw_terrain_pieces.py [OUT_DIR]
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import draw_landscape_sample as L  # noqa: E402

CELL_W, CELL_H = 48, 64
FOOT = (24, 56)
VARIANTS = 8
KINDS = ["tree", "pine", "bush", "pillar", "boulder", "tufts", "flowers", "pebbles"]
SENTINEL = np.array([255, 0, 255], np.float32)

def tree_r(v): return 11 + v * 6 / (VARIANTS - 1)
def pine_r(v): return 8.5 + v * 4.5 / (VARIANTS - 1)
def pillar_r(v): return 6 + v * 3 / (VARIANTS - 1)
def boulder_r(v): return 3 + v * 3 / (VARIANTS - 1)

def tufts(cv, rng, x, y):
    for _ in range(int(3 + rng.random() * 4)):
        tx, ty = x + (rng.random() - 0.5) * 20, y - rng.random() * 8
        pal = L.GRASS
        tip = pal[5] if rng.random() < 0.5 else pal[4]
        cv.px(tx, ty, pal[1]); cv.px(tx - 1, ty, pal[1]); cv.px(tx + 1, ty, pal[1])
        cv.px(tx - 1, ty - 1, pal[3]); cv.px(tx + 1, ty - 2, tip); cv.px(tx, ty - 1, pal[4])
        if rng.random() < 0.5:
            cv.px(tx - 2, ty - 2, tip)
        if rng.random() < 0.4:
            cv.px(tx + 2, ty - 1, pal[3]); cv.px(tx + 2, ty - 3, tip)

def flowers(cv, rng, x, y):
    c = L.FLOWERS[rng.integers(0, 4)]                       # one species per cluster reads natural
    for _ in range(int(3 + rng.random() * 5)):
        fx, fy = x + (rng.random() - 0.5) * 18, y - rng.random() * 9
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            cv.px(fx + dx, fy + dy, c)
        cv.px(fx, fy, L.FLOWERS[1] if c is not L.FLOWERS[1] else L.DIRT[4])
        cv.px(fx, fy + 2, L.LEAF[3])

def pebbles(cv, rng, x, y):
    for _ in range(int(2 + rng.random() * 3)):
        px, py = x + (rng.random() - 0.5) * 16, y - rng.random() * 6
        cv.px(px, py, L.STONE[3]); cv.px(px + 1, py, L.STONE[2]); cv.px(px, py - 1, L.STONE[5])
        if rng.random() < 0.4:
            cv.px(px + 1, py - 1, L.STONE[4]); cv.px(px + 2, py, L.STONE[1])
        cv.shade(np.zeros((L.H, L.W), bool) | ((L.YY == int(py) + 1) & (np.abs(L.XX - px - 0.5) < 1.5)), 0.4)

def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/sprites/terrain")
    aw, ah = CELL_W * VARIANTS, CELL_H * len(KINDS)
    L.W, L.H = aw, ah
    L.YY, L.XX = np.mgrid[0:ah, 0:aw]
    L.TEX = L.fbm(ah, aw, 3, 2, np.random.default_rng(991))
    cv = L.Canvas()
    cv.c[:] = SENTINEL
    cv.ground_ao = np.zeros((ah, aw), np.float32)            # every shadow, never cleared by owners
    no_pond = np.zeros((ah, aw), bool)
    for row, kind in enumerate(KINDS):
        for v in range(VARIANTS):
            rng = np.random.default_rng(1000 + row * 31 + v)
            x, y = v * CELL_W + FOOT[0], row * CELL_H + FOOT[1]
            if kind == "tree":
                L.draw_tree(cv, rng, x, y, tree_r(v))
            elif kind == "pine":
                L.draw_pine(cv, rng, x, y, pine_r(v))
            elif kind == "bush":
                L.draw_bush(cv, rng, x, y, 5 + (v % 4) * 0.8)
            elif kind == "pillar":
                L.draw_pillar(cv, rng, x, y - 14, pillar_r(v))
            elif kind == "boulder":
                L.draw_boulder(cv, x, y, boulder_r(v), no_pond)
            elif kind == "tufts":
                tufts(cv, rng, x, y)
            elif kind == "flowers":
                flowers(cv, rng, x, y)
            elif kind == "pebbles":
                pebbles(cv, rng, x, y)
    painted = np.any(cv.c != SENTINEL, axis=-1)
    base = np.zeros((ah, aw, 4), np.float32)
    shadow = cv.ground_ao * 0.75
    base[..., :3] = np.array([12, 24, 16])
    base[..., 3] = shadow * 255
    solid = painted & ~cv.over
    base[solid, :3] = cv.c[solid] * (1 - cv.ao[solid, None] * 0.75)
    base[solid, 3] = 255
    top = np.zeros((ah, aw, 4), np.float32)
    top[cv.over, :3] = cv.c[cv.over] * (1 - cv.ao[cv.over, None] * 0.75)
    top[cv.over, 3] = 255
    Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGBA").save(out / "terrain_pieces_base.png", optimize=True)
    Image.fromarray(np.clip(top, 0, 255).astype(np.uint8), "RGBA").save(out / "terrain_pieces_top.png", optimize=True)
    print("wrote", out, (aw, ah))

if __name__ == "__main__":
    main()
