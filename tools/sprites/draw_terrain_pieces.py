"""Bake the painted terrain-piece atlas used by the overworld.

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

Pieces are painted, not drawn from tiles: broadleaf crowns are 5-9 leaf
clumps each lit around its own centre, pines are tiered, pillars get mossy
caps; light comes from the upper left.

Usage: uv run --with pillow --with numpy python tools/sprites/draw_terrain_pieces.py [OUT_DIR]
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

CELL_W, CELL_H = 48, 64
FOOT = (24, 56)
VARIANTS = 8
KINDS = ["tree", "pine", "bush", "pillar", "boulder", "tufts", "flowers", "pebbles"]
W, H = CELL_W * VARIANTS, CELL_H * len(KINDS)
YY, XX = np.mgrid[0:H, 0:W]

def hexes(*hs):
    return np.array([[int(h[i:i + 2], 16) for i in (1, 3, 5)] for h in hs], dtype=np.float32)

# Grass matches the overworld ground shader's grass palette.
GRASS = hexes("#234830", "#2c5838", "#356634", "#42763a", "#4f8539", "#62963e")
DIRT = hexes("#3e3127", "#4f3f30", "#625039", "#776246", "#8c7655")
STONE = hexes("#262a35", "#3b4152", "#4d5568", "#5f687e", "#7a8399", "#959db0")
CLIFF = hexes("#251c1b", "#352826", "#4a3732", "#5e4740", "#755a4e", "#8e705f")
LEAF = hexes("#132016", "#1b3320", "#24472a", "#2f5c32", "#3f733a", "#548c42", "#70a84d", "#8cc057")
PINE = hexes("#0f1c17", "#16291f", "#1d3a28", "#264c31", "#31603a", "#437a45", "#5c9450")
BASALT = hexes("#1c2a24", "#273a30", "#33493b", "#405a44")
MOSS = hexes("#46603a", "#5a7745", "#71904f", "#8aa85e", "#a7c071", "#c3d68a")
FLOWERS = hexes("#f1e7d6", "#efc35a", "#d9686a", "#b993d6")
SENTINEL = np.array([255, 0, 255], np.float32)  # "not painted" marker

# ---------------------------------------------------------------- helpers

def vnoise(h, w, cell, rng):
    gh, gw = int(h / cell) + 3, int(w / cell) + 3
    g = rng.random((gh, gw))
    ys, xs = np.arange(h) / cell, np.arange(w) / cell
    y0, x0 = ys.astype(int), xs.astype(int)
    fy, fx = ys - y0, xs - x0
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a = g[np.ix_(y0, x0)]; b = g[np.ix_(y0, x0 + 1)]
    c = g[np.ix_(y0 + 1, x0)]; d = g[np.ix_(y0 + 1, x0 + 1)]
    fx, fy = fx[None, :], fy[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def fbm(h, w, cell, octaves, rng):
    out, amp, tot = np.zeros((h, w)), 1.0, 0.0
    for _ in range(octaves):
        out += vnoise(h, w, max(cell, 1.5), rng) * amp
        tot += amp; amp *= 0.5; cell /= 2
    out /= tot
    return (out - out.min()) / (out.max() - out.min() + 1e-9)

TEX = fbm(H, W, 3, 2, np.random.default_rng(991))  # leaf / rock grain

def shift(m, dy, dx):
    """Content moves by (dy, dx): out[y, x] = m[y - dy, x - dx]."""
    o = np.zeros_like(m)
    ys = slice(max(dy, 0), H + min(dy, 0)); yd = slice(max(-dy, 0), H + min(-dy, 0))
    xs = slice(max(dx, 0), W + min(dx, 0)); xd = slice(max(-dx, 0), W + min(-dx, 0))
    o[ys, xs] = m[yd, xd]
    return o

def outline_of(mask):
    grown = mask | shift(mask, 1, 0) | shift(mask, -1, 0) | shift(mask, 0, 1) | shift(mask, 0, -1)
    return grown & ~mask

def ellipse(cx, cy, rx, ry):
    return ((XX - cx) / rx) ** 2 + ((YY - cy) / ry) ** 2 <= 1.0

class Canvas:
    def __init__(self):
        self.c = np.zeros((H, W, 3), np.float32)
        self.c[:] = SENTINEL
        self.ao = np.zeros((H, W), np.float32)      # shading on objects (cleared under owners)
        self.shadow = np.zeros((H, W), np.float32)  # every ground shadow, never cleared
        self.objects = np.zeros((H, W), bool)
        self.over = np.zeros((H, W), bool)          # pixels for the above-characters layer

    def put(self, mask, col):
        self.c[mask] = col

    def px(self, x, y, col):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < W and 0 <= y < H:
            self.c[y, x] = col

    def shade(self, mask, amount):
        self.ao[mask] = np.maximum(self.ao[mask], amount)
        self.shadow[mask] = np.maximum(self.shadow[mask], amount)

    def own(self, mask, over):
        """An object now covers `mask` (+ outline): earlier shadows don't darken it."""
        full = mask | outline_of(mask)
        self.ao[full] = 0
        self.objects |= mask
        if over:
            self.over |= full

def shade_blob(cv, m, cx, cy, r, pal, light_bias=0.0):
    nx = (XX - cx) / r; ny = (YY - cy) / r
    light = -(nx * 0.55 + ny * 0.85) + light_bias
    t = np.clip((light + 1) / 2 * (len(pal) - 2) + (TEX - 0.5) * 2.4, 0, len(pal) - 2).astype(int) + 1
    cv.c[m] = pal[t][m]

# ---------------------------------------------------------------- painters

def draw_tree(cv, rng, x, y, r):
    """Broadleaf: 5-9 leaf clumps, each lit around its own centre (cauliflower crown)."""
    cv.shade(ellipse(x + 3, y + 2, r * 0.95, r * 0.45), 0.55)
    trunk = (np.abs(XX - x) <= 1.5) & (YY > y - 5) & (YY <= y + 1)
    cv.put(trunk, CLIFF[2]); cv.put(trunk & (XX < x), CLIFF[3])
    cy = y - r * 0.95
    tint = [np.array([1, 1, 1]), np.array([1.15, 1.1, 0.8]), np.array([0.82, 0.95, 1.0]), np.array([1.05, 1.0, 0.9])][rng.integers(0, 4)]
    pal = np.clip(LEAF * tint, 0, 255)
    clumps = []
    for _ in range(int(5 + rng.random() * 5)):
        a = rng.random() * 2 * np.pi
        d = r * 0.55 * np.sqrt(rng.random())
        clumps.append((x + np.cos(a) * d, cy + np.sin(a) * d * 0.8, r * (0.38 + rng.random() * 0.22)))
    clumps.sort(key=lambda c: c[1])
    crown = np.zeros((H, W), bool)
    for (ux, uy, cr) in clumps:
        m = ellipse(ux, uy, cr, cr * 0.85)
        m |= outline_of(m) & (TEX > 0.6)
        shade_blob(cv, m, ux, uy, cr, pal, 0.15 + (cy - uy) / r * 0.25)
        cv.put(m & ~shift(m, -1, 0) & crown, pal[1])               # crease over the clump behind
        crown |= m
    cv.put(outline_of(crown) & ~cv.objects, pal[0])
    cv.own(crown, True)
    if rng.random() < 0.15:                                         # occasional fruit
        for _ in range(5):
            fx, fy = x + (rng.random() - 0.5) * r * 1.2, cy + (rng.random() - 0.4) * r
            if crown[int(fy) % H, int(fx) % W]:
                cv.px(fx, fy, FLOWERS[2]); cv.px(fx - 1, fy - 1, FLOWERS[0])

def draw_pine(cv, rng, x, y, r):
    """Conifer: stacked feathery tiers, lit from the left."""
    cv.shade(ellipse(x + 4, y + 1, r, r * 0.4), 0.55)
    cv.put((np.abs(XX - x) <= 1) & (YY > y - 4) & (YY <= y + 1), CLIFF[1])
    height = r * 2.6
    tiers = 3 + int(rng.random() * 2)
    m = np.zeros((H, W), bool)
    shade_t = np.zeros((H, W))
    for i in range(tiers):
        t0 = y - 3 - height + i * height / tiers * 0.85
        th = height / tiers * 1.25
        wmax = r * (0.45 + 0.6 * (i + 1) / tiers)
        f = (YY - t0) / th
        tier = (f >= 0) & (f <= 1) & (np.abs(XX - x) <= wmax * f + (TEX - 0.5) * 3.5 + 0.5)
        tier &= ~((f > 0.8) & (np.sin((XX - x) * 1.6) > 0.3))      # hanging points
        m |= tier
        shade_t = np.where(tier, f, shade_t)
    light = -(XX - x) / r * 0.9 + (0.4 - shade_t) * 0.8
    t = np.clip((light + 1) / 2 * (len(PINE) - 2) + (TEX - 0.5) * 2.0, 0, len(PINE) - 2).astype(int) + 1
    cv.c[m] = PINE[t][m]
    cv.put(outline_of(m) & ~cv.objects, PINE[0])
    cv.own(m, True)

def draw_bush(cv, rng, x, y, r):
    cv.shade(ellipse(x + 2, y + 1, r, r * 0.45), 0.45)
    m = ellipse(x, y - r * 0.5, r, r * 0.75) | ellipse(x - r * 0.6, y - r * 0.3, r * 0.6, r * 0.5) | ellipse(x + r * 0.6, y - r * 0.3, r * 0.6, r * 0.5)
    m |= outline_of(m) & (TEX > 0.6)
    shade_blob(cv, m, x, y - r * 0.5, r, LEAF)
    cv.put(outline_of(m) & ~cv.objects, LEAF[0])
    cv.own(m, True)

def draw_pillar(cv, rng, x, y, r):
    """Basalt column with a mossy cap; y is the cap centre."""
    h = int(6 + rng.random() * 10)
    body = (np.abs(XX - x) <= r) & (YY >= y) & (YY <= y + h)
    t = np.clip(((-(XX - x) / r + 1) / 2 * 3 + (TEX - 0.5)).astype(int), 0, 3)
    cv.c[body] = BASALT[t][body]
    cv.put(body & (np.abs(XX - x - r * 0.33) < 0.5), BASALT[0])
    cv.put(ellipse(x, y + h, r, r * 0.5) & ~body & (YY > y + h), BASALT[0])
    cv.shade(ellipse(x + 3, y + h + 2, r * 1.1, r * 0.4), 0.5)
    cap = ellipse(x, y, r, r * 0.55)
    shade_blob(cv, cap, x, y, r, MOSS)
    cv.put(cap & ~shift(cap, 1, 0) & (XX < x + r * 0.3), MOSS[5])
    cv.put(outline_of(body | cap) & ~cv.objects, BASALT[0])
    for _ in range(2):
        gx, gy = x + (rng.random() - 0.5) * r, y + (rng.random() - 0.6) * r * 0.4
        cv.px(gx, gy, GRASS[5]); cv.px(gx + 1, gy - 1, MOSS[5]); cv.px(gx - 1, gy, GRASS[3])
    cv.own(body | cap, True)

def draw_boulder(cv, rng, x, y, r):
    m = ellipse(x, y - r * 0.4, r, r * 0.8)
    shade_blob(cv, m, x, y - r * 0.4, r, CLIFF)
    cv.put(outline_of(m) & ~cv.objects, CLIFF[0])
    cv.put(m & ~shift(m, 1, 0), CLIFF[5])
    cv.own(m, False)

def draw_tufts(cv, rng, x, y):
    # #838: upright blades (mid foot, lit tip), never a flat dark bar: the old
    # 3 px dark base row read as a random shadow streak on grass.
    for _ in range(int(3 + rng.random() * 4)):
        tx, ty = int(round(x + (rng.random() - 0.5) * 20)), int(round(y - rng.random() * 8))
        blades = [(-1, 2), (0, 3), (1, 2)]
        if rng.random() < 0.5:
            blades.append((2, 2))
        for dx, h in blades:
            if dx != 0 and rng.random() < 0.25:
                continue
            tip = GRASS[5] if (dx + int(rng.random() * 2)) % 2 == 0 else GRASS[4]
            for k in range(h):
                cv.px(tx + dx, ty - k, tip if k == h - 1 else GRASS[3] if k else GRASS[2])

def draw_flowers(cv, rng, x, y):
    c = FLOWERS[rng.integers(0, 4)]                                 # one species per cluster
    for _ in range(int(3 + rng.random() * 5)):
        fx, fy = x + (rng.random() - 0.5) * 18, y - rng.random() * 9
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            cv.px(fx + dx, fy + dy, c)
        cv.px(fx, fy, FLOWERS[1] if c is not FLOWERS[1] else DIRT[4])
        cv.px(fx, fy + 2, LEAF[3])

def draw_pebbles(cv, rng, x, y):
    for _ in range(int(2 + rng.random() * 3)):
        px, py = x + (rng.random() - 0.5) * 16, y - rng.random() * 6
        cv.px(px, py, STONE[3]); cv.px(px + 1, py, STONE[2]); cv.px(px, py - 1, STONE[5])
        if rng.random() < 0.4:
            cv.px(px + 1, py - 1, STONE[4]); cv.px(px + 2, py, STONE[1])
        cv.shade((YY == int(py) + 1) & (np.abs(XX - px - 0.5) < 1.5), 0.4)

# ---------------------------------------------------------------- bake

def paint(cv, row, kind, v, rng, x, y):
    if kind == "tree":
        draw_tree(cv, rng, x, y, 11 + v * 6 / (VARIANTS - 1))
    elif kind == "pine":
        draw_pine(cv, rng, x, y, 8.5 + v * 4.5 / (VARIANTS - 1))
    elif kind == "bush":
        draw_bush(cv, rng, x, y, 5 + (v % 4) * 0.8)
    elif kind == "pillar":
        draw_pillar(cv, rng, x, y - 14, 6 + v * 3 / (VARIANTS - 1))
    elif kind == "boulder":
        draw_boulder(cv, rng, x, y, 3 + v * 3 / (VARIANTS - 1))
    elif kind == "tufts":
        draw_tufts(cv, rng, x, y)
    elif kind == "flowers":
        draw_flowers(cv, rng, x, y)
    elif kind == "pebbles":
        draw_pebbles(cv, rng, x, y)

def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/sprites/terrain")
    cv = Canvas()
    for row, kind in enumerate(KINDS):
        for v in range(VARIANTS):
            rng = np.random.default_rng(1000 + row * 31 + v)
            before = cv.shadow.copy()
            paint(cv, row, kind, v, rng, v * CELL_W + FOOT[0], row * CELL_H + FOOT[1])
            # #838: a ground shadow must stay inside its own cell. A tree shadow
            # ran past its cell bottom into the top rows of the pine cell below
            # and drew a stray dark bar above every larger pine.
            keep = np.zeros((H, W), bool)
            keep[row * CELL_H:(row + 1) * CELL_H, v * CELL_W:(v + 1) * CELL_W] = True
            cv.shadow[~keep] = before[~keep]
    painted = np.any(cv.c != SENTINEL, axis=-1)
    solid = painted & ~cv.over
    base = np.zeros((H, W, 4), np.float32)
    base[..., :3] = np.array([12, 24, 16])                          # shadow colour
    base[..., 3] = cv.shadow * 0.75 * 255
    base[solid, :3] = cv.c[solid] * (1 - cv.ao[solid, None] * 0.75)
    base[solid, 3] = 255
    top = np.zeros((H, W, 4), np.float32)
    top[cv.over, :3] = cv.c[cv.over] * (1 - cv.ao[cv.over, None] * 0.75)
    top[cv.over, 3] = 255
    Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGBA").save(out / "terrain_pieces_base.png", optimize=True)
    Image.fromarray(np.clip(top, 0, 255).astype(np.uint8), "RGBA").save(out / "terrain_pieces_top.png", optimize=True)
    print("wrote", out, (W, H))

if __name__ == "__main__":
    main()
