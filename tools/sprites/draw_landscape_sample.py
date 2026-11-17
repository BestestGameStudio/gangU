"""Bake the overworld landscape sample (layered, painted terrain).

Paints one landscape (raised meadow behind a cliff with stairs, a winding
path through a ruined slab court, a pond, mixed forest, basalt pillars) as
layers instead of grid tiles:

  1 base ground  - grass tone from clumped multi-scale noise, quantised to the
                   game's dual-grid grass palette
  2 regions      - plateau, path, ruined court, pond; noise-shaped, never on a grid
  3 transitions  - ragged path edge, wet shore + foam, cliff lip, hanging grass
  4 scatter      - tufts, flowers, pebbles, weeds; density follows noise so it clumps
  5 objects      - trees, pines, bushes, pillars, boulders; y-sorted, overlap edges
  6 shading      - ambient occlusion under cliffs and objects, shade on the water

Outputs (1 art px = LandscapeSample.ART_SCALE world px in game):
  landscape_sample_ground.png  everything under characters; alpha feathers into
                               the surrounding overworld grass
  landscape_sample_over.png    crowns, bushes and pillars, drawn above characters
  landscape_sample_mask.png    collision: R=255 obstacle, B=255 water,
                               G=255 one marker pixel at each tree trunk base

Usage: uv run --with pillow --with numpy python tools/sprites/draw_landscape_sample.py [SEED] [OUT_DIR]
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

W, H = 768, 512
MARGIN = 48           # features stay inside this; the ring outside is grass that feathers out

def hexes(*hs):
    return np.array([[int(h[i:i + 2], 16) for i in (1, 3, 5)] for h in hs], dtype=np.float32)

# Grass is built around the dual-grid grass tile colours (#2c5838 / #42763a / #62963e)
# so the feathered edge meets the surrounding overworld without a seam.
GRASS = hexes("#234830", "#2c5838", "#356634", "#42763a", "#4f8539", "#62963e")
GRASS_HI = hexes("#2f5a34", "#3a6a37", "#467a3a", "#53883c", "#65983f", "#7cab48")
DIRT = hexes("#3e3127", "#4f3f30", "#625039", "#776246", "#8c7655")
STONE = hexes("#262a35", "#3b4152", "#4d5568", "#5f687e", "#7a8399", "#959db0")
WATER = hexes("#163d57", "#1b4f6d", "#216585", "#2a7f9f", "#3698b4", "#5cbccc", "#a6e6ea", "#e2fbff")
CLIFF = hexes("#251c1b", "#352826", "#4a3732", "#5e4740", "#755a4e", "#8e705f")
LEAF = hexes("#132016", "#1b3320", "#24472a", "#2f5c32", "#3f733a", "#548c42", "#70a84d", "#8cc057")
PINE = hexes("#0f1c17", "#16291f", "#1d3a28", "#264c31", "#31603a", "#437a45", "#5c9450")
BASALT = hexes("#1c2a24", "#273a30", "#33493b", "#405a44")
MOSS = hexes("#46603a", "#5a7745", "#71904f", "#8aa85e", "#a7c071", "#c3d68a")
FLOWERS = hexes("#f1e7d6", "#efc35a", "#d9686a", "#b993d6")

YY, XX = np.mgrid[0:H, 0:W]
EDGE = np.minimum(np.minimum(XX, W - 1 - XX), np.minimum(YY, H - 1 - YY)).astype(np.float32)

# ---------------------------------------------------------------- noise and masks

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

def shift(m, dy, dx, fill=False):
    """Content moves by (dy, dx): out[y, x] = m[y - dy, x - dx]."""
    o = np.full_like(m, fill)
    ys = slice(max(dy, 0), H + min(dy, 0)); yd = slice(max(-dy, 0), H + min(-dy, 0))
    xs = slice(max(dx, 0), W + min(dx, 0)); xd = slice(max(-dx, 0), W + min(-dx, 0))
    o[ys, xs] = m[yd, xd]
    return o

def dilate(m, n):
    for _ in range(n):
        m = m | shift(m, 1, 0) | shift(m, -1, 0) | shift(m, 0, 1) | shift(m, 0, -1)
    return m

def erode_depth(mask, n):
    depth = np.zeros(mask.shape, int); cur = mask.copy()
    for _ in range(n):
        depth += cur
        cur = cur & shift(cur, 1, 0) & shift(cur, -1, 0) & shift(cur, 0, 1) & shift(cur, 0, -1)
    return depth

def outline_of(mask):
    return dilate(mask, 1) & ~mask

def ellipse(cx, cy, rx, ry):
    return ((XX - cx) / rx) ** 2 + ((YY - cy) / ry) ** 2 <= 1.0

def poisson(rng, n_try, min_d, accept):
    pts = []
    for _ in range(n_try):
        x, y = rng.random() * W, rng.random() * H
        if not accept(x, y):
            continue
        if all((x - px) ** 2 + (y - py) ** 2 >= min_d * min_d for px, py in pts):
            pts.append((x, y))
    return pts

# ---------------------------------------------------------------- canvas

class Canvas:
    def __init__(self):
        self.c = np.zeros((H, W, 3), np.float32)
        self.ao = np.zeros((H, W), np.float32)      # 0 lit .. 1 fully occluded
        self.objects = np.zeros((H, W), bool)       # pixels owned by an object (no outline over them)
        self.over = np.zeros((H, W), bool)          # pixels that go on the above-characters layer
        self.ground_ao = None                       # AO snapshot that includes object shadows
        self.block = np.zeros((H, W), bool)         # collision: obstacle
        self.trunks = []                            # (x, y) trunk bases

    def put(self, mask, col):
        self.c[mask] = col

    def px(self, x, y, col):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < W and 0 <= y < H:
            self.c[y, x] = col

    def shade(self, mask, amount):
        self.ao[mask] = np.maximum(self.ao[mask], amount)
        if self.ground_ao is not None:
            self.ground_ao[mask] = np.maximum(self.ground_ao[mask], amount)

    def own(self, mask, over):
        """An object now covers `mask` (+ outline): earlier shadows don't darken it."""
        full = mask | outline_of(mask)
        self.ao[full] = 0
        self.objects |= mask
        if over:
            self.over |= full

# ---------------------------------------------------------------- scene

def build(seed):
    rng = np.random.default_rng(seed)
    cv = Canvas()
    clump = fbm(H, W, 64, 4, rng)       # big soft patches: grass tone AND scatter density
    fine = fbm(H, W, 6, 2, rng)
    jitter = rng.random((H, W))
    inside = EDGE > MARGIN
    side = 1 if rng.random() < 0.5 else -1

    # ---- plateau: a raised meadow island with a cliff face on its south side
    warp = fbm(H, W, 40, 3, rng)
    qcx, qcy = W * (0.5 + side * 0.12), H * 0.32
    plat_d = np.sqrt(((XX - qcx) / (W * 0.27)) ** 2 + ((YY - qcy) / (H * 0.14)) ** 2) + (warp - 0.5) * 0.55
    plateau = (plat_d < 1.0) & inside
    cliff_h = 22
    face_depth = np.full((H, W), 99)
    for k in range(cliff_h, 0, -1):
        face_depth = np.where(shift(plateau, k, 0) & ~plateau, k - 1, face_depth)
    face = face_depth < cliff_h
    lip_y = np.full(W, -1)                                          # south lip row per column
    for x in range(W):
        ys = np.flatnonzero(plateau[:, x])
        if ys.size:
            lip_y[x] = ys.max() + 1
    cols = np.flatnonzero(lip_y >= 0)
    mid = cols[len(cols) // 2] if side < 0 else cols[len(cols) * 2 // 5]
    stair_w = 26
    stair_x = int(mid - stair_w // 2)
    stair_cols = (XX >= stair_x) & (XX < stair_x + stair_w)
    lip_lo = int(lip_y[stair_x:stair_x + stair_w].min()); lip_hi = int(lip_y[stair_x:stair_x + stair_w].max())
    stair_top = lip_lo - 10
    stairs = stair_cols & (YY >= stair_top) & (YY < lip_hi + cliff_h)
    stairs &= plateau | face | (YY < lip_hi + cliff_h)

    # ---- pond on the other side of the low ground
    pcx, pcy = W * (0.5 - side * 0.27), H * 0.7
    warp2 = fbm(H, W, 30, 3, rng)
    pond_d = np.sqrt(((XX - pcx) / (W * 0.15)) ** 2 + ((YY - pcy) / (H * 0.12)) ** 2) + (warp2 - 0.5) * 0.7
    pond = (pond_d < 1.0) & ~plateau & ~face & inside

    # ---- path: bottom edge -> foot of the stairs, wobbling
    bx = W * (0.5 + side * 0.05) + (rng.random() - 0.5) * 40
    tx, ty = stair_x + stair_w / 2, lip_hi + cliff_h
    ts = np.linspace(0, 1, 50)
    sway = side * (40 + rng.random() * 50)
    pxs = bx + (tx - bx) * ts + np.sin(ts * np.pi) * sway
    pys = H + 6 + (ty - H - 6) * ts
    dist = np.full((H, W), 1e9)
    for i in range(len(ts) - 1):
        ax, ay, bx2, by2 = pxs[i], pys[i], pxs[i + 1], pys[i + 1]
        vx, vy = bx2 - ax, by2 - ay
        t = np.clip(((XX - ax) * vx + (YY - ay) * vy) / (vx * vx + vy * vy), 0, 1)
        dist = np.minimum(dist, np.hypot(XX - ax - t * vx, YY - ay - t * vy))
    width = 10 + (fine - 0.5) * 6 + (clump - 0.5) * 6
    path = (dist < width) & ~plateau & ~face & ~pond
    path_edge = (dist < width + 3) & ~path & ~plateau & ~face & ~pond

    # ---- ruined court: voronoi slabs around a point on the path
    k = int(len(ts) * (0.35 + rng.random() * 0.15))
    rcx, rcy = pxs[k], pys[k]
    court = (np.sqrt(((XX - rcx) / 80) ** 2 + ((YY - rcy) / 38) ** 2) + (fbm(H, W, 14, 3, rng) - 0.5) * 0.8 < 1.0)
    court &= ~plateau & ~face & ~pond & ~dilate(face, 4) & inside

    # ---- 1 base grass
    tone = clump * 0.65 + fine * 0.35 + (jitter - 0.5) * 0.16
    idx = np.clip((tone * (len(GRASS) - 0.01)).astype(int), 0, len(GRASS) - 1)
    cv.c[:] = GRASS[idx]
    cv.c[plateau] = GRASS_HI[idx][plateau]

    # ---- 2/3 path with a ragged grass edge
    d_idx = np.clip(((fine * 0.7 + jitter * 0.3) * (len(DIRT) - 1) + 1).astype(int), 0, len(DIRT) - 1)
    cv.put(path, DIRT[d_idx][path])
    ragged = path_edge & (jitter < 0.45 + (fine - 0.5))
    cv.put(ragged, DIRT[np.clip(d_idx - 1, 0, 4)][ragged])
    cv.put(path & outline_of(~path) & (jitter < 0.5), DIRT[0])

    # ruined slabs
    n_seeds = 48
    sx = rcx + (rng.random(n_seeds) - 0.5) * 180; sy = rcy + (rng.random(n_seeds) - 0.5) * 90
    d1 = np.full((H, W), 1e9); d2 = np.full((H, W), 1e9); sid = np.zeros((H, W), int)
    for i in range(n_seeds):
        d = np.hypot(XX - sx[i], (YY - sy[i]) * 1.5)              # slabs wider than tall
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        sid = np.where(closer, i, sid)
        d1 = np.where(closer, d, d1)
    kept = rng.random(n_seeds) < 0.84
    slab = court & ((d2 - d1) > 1.6) & kept[sid]
    gap = court & ~slab
    cv.put(gap & ~path, DIRT[1]); cv.put(gap & path, DIRT[0])
    slab_tone = rng.integers(2, 4, n_seeds)
    cv.put(slab, STONE[slab_tone[sid]][slab])
    cv.put(slab & (jitter < 0.08), STONE[1])
    top_edge = slab & ~shift(slab, 1, 0)
    cv.put(top_edge, STONE[5]); cv.put(slab & ~shift(slab, 0, 1) & ~top_edge, STONE[4])
    cv.put(slab & ~shift(slab, -1, 0), STONE[0])
    for i in np.flatnonzero(kept & (rng.random(n_seeds) < 0.5)):   # cracks
        x, y = sx[i], sy[i]; ang = rng.random() * np.pi
        for _ in range(int(4 + rng.random() * 6)):
            ang += (rng.random() - 0.5) * 1.2
            x += np.cos(ang); y += np.sin(ang) * 0.6
            if 0 <= int(y) < H and 0 <= int(x) < W and slab[int(y), int(x)]:
                cv.px(x, y, STONE[1])
    moss_on_slab = slab & (fbm(H, W, 10, 2, rng) > 0.68)
    cv.put(moss_on_slab, MOSS[np.clip((jitter * 3).astype(int), 0, 2)][moss_on_slab])
    cv.shade(shift(slab, 1, 0) & ~slab & court, 0.35)

    # ---- pond: depth bands, wet shore, foam, ripples, sparkles, lily pads
    depth = erode_depth(pond, 18)
    shore = outline_of(pond)
    wet = dilate(pond, 2) & ~pond & ~shore
    cv.put(wet, DIRT[0] * 0.8)
    cv.put(shore, DIRT[1] * 0.7)
    df = depth + (jitter - 0.5) * 2.4 + (fine - 0.5) * 5.0
    wlev = np.select([df >= 14, df >= 9, df >= 5, df >= 3, df >= 1.5], [0, 1, 2, 3, 4], 4)
    cv.put(pond, WATER[wlev][pond])
    cv.c[pond & shift(~pond, 6, 0) & (depth > 1)] *= 0.78          # the north bank shades the water
    cv.put(pond & (depth == 1) & (jitter < 0.75), WATER[5])
    ripple = pond & (depth > 3) & (np.sin(XX * 0.35 + YY * 1.7 + warp2 * 14) > 0.97) & (fine > 0.62) & (jitter < 0.7)
    cv.put(ripple, WATER[5])
    for _ in range(30):
        x, y = rng.random() * W, rng.random() * H
        if pond[int(y), int(x)] and depth[int(y), int(x)] > 3:
            cv.px(x, y, WATER[7])
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                cv.px(x + dx, y + dy, WATER[6])
    for _ in range(40):
        x, y = rng.random() * W, rng.random() * H
        if pond[int(y), int(x)] and 2 < depth[int(y), int(x)] < 8:
            pad = ellipse(x, y, 4.5, 3) & pond
            cv.put(pad, LEAF[5]); cv.put(pad & ~shift(pad, 1, 0), LEAF[7])
            cv.put(pad & (np.abs(XX - x - 1) < 1) & (YY < y), WATER[3])
            if rng.random() < 0.6:
                cv.px(x - 1, y - 1, FLOWERS[0]); cv.px(x, y - 1, FLOWERS[0]); cv.px(x - 1, y - 2, FLOWERS[2])

    # ---- cliff face: rock columns of random width, rounded tops, strata
    x = 0
    while x < W:
        cw = int(5 + rng.random() * 9)
        base = 2 + int(rng.random() * 2.5)
        cuts = set(int(c) for c in rng.integers(4, cliff_h - 2, int(1 + rng.random() * 2)))
        drop = int(rng.random() * 3)
        for xx in range(x, min(W, x + cw)):
            u = (xx - x + 0.5) / cw
            round_top = int(round((1 - np.sin(u * np.pi)) * 2.2)) + drop
            for y in np.flatnonzero(face[:, xx]):
                yy = face_depth[y, xx]
                if yy < round_top:
                    continue                                        # plateau grass shows over rounded tops
                c = base + (1 if u < 0.3 else 0) - (1 if u > 0.78 else 0)
                if yy in cuts:
                    c = 1
                elif yy - 1 in cuts:
                    c = min(c + 1, 5)
                if yy - round_top < 2:
                    c = 5 if yy == round_top else 4
                if yy > cliff_h - 6:
                    c = max(c - (1 if yy < cliff_h - 3 else 2), 0)
                if xx == x or xx == x + cw - 1:
                    c = max(c - 2, 0)
                cv.c[y, xx] = CLIFF[c]
        x += cw
    south_lip = plateau & shift(face, -1, 0)
    cv.put(south_lip & (jitter < 0.6), MOSS[4])
    for x in cols:                                                  # grass drips over the lip
        if rng.random() < 0.35:
            for k2 in range(int(1 + rng.random() * 4)):
                cv.px(x, lip_y[x] + k2, MOSS[3 - min(k2, 2)])
    # the north/east/west rim: a thin dark edge with a lit grass lip inside it
    rim = plateau & outline_of(~plateau) & ~south_lip
    cv.put(rim, CLIFF[1]); cv.put(plateau & outline_of(~plateau | rim) & ~rim & ~south_lip, GRASS_HI[5])
    below = np.zeros((H, W)); run = np.full(W, 99.0)
    for y in range(H):                                              # distance below the face, for the AO ramp
        run = np.where(face[y], 0, run + 1)
        below[y] = run
    ramp = (below < 8) & ~face & ~plateau & (below > 0)
    cv.ao[ramp] = np.maximum(cv.ao[ramp], (1 - below[ramp] / 8) * 0.45)

    # stairs cut into the cliff
    cv.put(stairs, STONE[2])
    for y in range(stair_top, lip_hi + cliff_h):
        step = (y - stair_top) % 4
        if step == 0:
            cv.c[y, stairs[y]] = STONE[4]
        elif step == 3:
            cv.c[y, stairs[y]] = STONE[1]
    cv.put(stairs & (~shift(stairs, 0, 1) | ~shift(stairs, 0, -1)), STONE[0])
    cv.put(outline_of(stairs) & ~plateau, STONE[1])

    # collision from the terrain layout: water is its own type in the mask
    cv.block |= face & ~stairs
    cv.block |= plateau & dilate(~plateau, 5) & ~(stair_cols & (YY >= stair_top - 8))  # rim, open at the stair top

    # ---- 4 scatter (density follows `clump`, so it gathers in patches)
    open_ground = ~(pond | wet | shore | face | stairs | court | path)
    def ok(x, y, thresh):
        xi, yi = int(x), int(y)
        return open_ground[yi, xi] and clump[yi, xi] > thresh

    for (x, y) in poisson(rng, 9000, 4.0, lambda x, y: ok(x, y, 0.42)):   # grass tufts
        pal = GRASS_HI if plateau[int(y), int(x)] else GRASS
        tip = pal[5] if rng.random() < 0.5 else pal[4]
        cv.px(x, y, pal[1]); cv.px(x - 1, y, pal[1]); cv.px(x + 1, y, pal[1])
        cv.px(x - 1, y - 1, pal[3]); cv.px(x + 1, y - 2, tip); cv.px(x, y - 1, pal[4])
        if rng.random() < 0.5:
            cv.px(x - 2, y - 2, tip)
    for (x, y) in poisson(rng, 3000, 7.0, lambda x, y: ok(x, y, 0.6) and fine[int(y), int(x)] > 0.5):
        c = FLOWERS[rng.integers(0, 4)]
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            cv.px(x + dx, y + dy, c)
        cv.px(x, y, FLOWERS[1] if c is not FLOWERS[1] else DIRT[4])
        cv.px(x, y + 2, LEAF[3])
    pebble_zone = path | path_edge | gap | wet
    for (x, y) in poisson(rng, 3000, 5.0, lambda x, y: pebble_zone[int(y), int(x)]):
        cv.px(x, y, STONE[3]); cv.px(x + 1, y, STONE[2]); cv.px(x, y - 1, STONE[5])
        cv.ao[min(int(y) + 1, H - 1), int(x)] = 0.3
    for (x, y) in poisson(rng, 1200, 6.0, lambda x, y: gap[int(y), int(x)] or path_edge[int(y), int(x)]):
        cv.px(x, y, GRASS[3]); cv.px(x, y - 1, GRASS[5]); cv.px(x + 1, y - 1, GRASS[4])

    # ---- 5 objects
    blocked = pond | face | stairs | court | (dist < width + 9)
    near_stairs = np.abs(XX - stair_x - stair_w / 2) < 30
    # crowns must not cross the canvas edge (the over layer is not feathered)
    room = (XX > 24) & (XX < W - 24) & (YY > 48) & (YY < H - 8)
    pillar_zone = np.hypot(XX - qcx - side * W * 0.13, (YY - qcy + 10) * 1.4) < 52
    blocked = blocked | pillar_zone | (plateau & dilate(~plateau, 8))

    boulders = []
    for (x, y) in poisson(rng, 2000, 9.0, lambda x, y: (pond[int(y), int(x)] and depth[int(y), int(x)] < 4)
                          or (path_edge[int(y), int(x)] and rng.random() < 0.2)):
        boulders.append((x, y, 3 + rng.random() * 3))

    tall = []
    forest = fbm(H, W, 90, 2, rng)
    forest_bias = np.where(side * (XX - W / 2) > 0, 0.16, -0.04)     # denser on the plateau side
    for (x, y) in poisson(rng, 12000, 15.0, lambda x, y: room[int(y), int(x)]
                          and (forest[int(y), int(x)] + forest_bias[int(y), int(x)] > 0.68)
                          and not blocked[int(y), int(x)] and not near_stairs[int(y), int(x)]
                          and not (pond_d[int(y), int(x)] < 1.3 and rng.random() < 0.7)):
        if (forest[int(y), int(x)] > 0.74 or plateau[int(y), int(x)]) and rng.random() < 0.7:
            tall.append(("pine", x, y, 8 + rng.random() * 6))
        else:
            tall.append(("tree", x, y, 9 + rng.random() * 9))
    edge_zone = (outline_of(dilate(pond, 2)) | path_edge | ramp) & ~blocked & ~near_stairs & room
    for (x, y) in poisson(rng, 5000, 11.0, lambda x, y: edge_zone[int(y), int(x)] and rng.random() < 0.35):
        tall.append(("bush", x, y, 5 + rng.random() * 3))
    for _ in range(22):
        x = qcx + side * W * 0.13 + (rng.random() - 0.5) * 80; y = qcy - 10 + (rng.random() - 0.5) * 50
        if plateau[int(y), int(x)] and not (plateau & dilate(~plateau, 6))[int(y), int(x)]:
            tall.append(("pillar", x, y, 6 + rng.random() * 4))

    # boulders sit on the ground layer; everything tall goes to the over layer
    for x, y, r in sorted(boulders, key=lambda b: b[1]):
        draw_boulder(cv, x, y, r, pond)
    ground_c = cv.c.copy()
    cv.ground_ao = cv.ao.copy()
    tall.sort(key=lambda o: o[2])
    for kind, x, y, r in tall:
        {"tree": draw_tree, "pine": draw_pine, "bush": draw_bush, "pillar": draw_pillar}[kind](cv, rng, x, y, r)

    # ---- 6 shading + layers
    feather = np.clip((EDGE - 6 - fbm(H, W, 24, 3, rng) * 30) / 18, 0, 1)
    ground = ground_c * (1 - cv.ground_ao[..., None] * 0.75)
    ground = np.dstack([np.clip(ground, 0, 255), feather * 255]).astype(np.uint8)
    over = cv.c * (1 - cv.ao[..., None] * 0.75)
    over = np.dstack([np.clip(over, 0, 255), cv.over * 255.0]).astype(np.uint8)
    mask = np.zeros((H, W, 3), np.uint8)
    mask[..., 0] = cv.block * 255
    mask[..., 2] = pond * 255
    for x, y in cv.trunks:
        xi, yi = int(round(x)), int(round(y))
        if 0 <= xi < W and 0 <= yi < H:
            mask[yi, xi, 1] = 255
    return Image.fromarray(ground, "RGBA"), Image.fromarray(over, "RGBA"), Image.fromarray(mask, "RGB")

# ---------------------------------------------------------------- object painters

def shade_blob(cv, m, cx, cy, r, pal, tex, light_bias=0.0):
    nx = (XX - cx) / r; ny = (YY - cy) / r
    light = -(nx * 0.55 + ny * 0.85) + light_bias
    t = np.clip((light + 1) / 2 * (len(pal) - 2) + (tex - 0.5) * 2.4, 0, len(pal) - 2).astype(int) + 1
    cv.c[m] = pal[t][m]

def draw_tree(cv, rng, x, y, r):
    """Broadleaf: 5-9 leaf clumps, each lit around its own centre (cauliflower crown)."""
    cv.shade(ellipse(x + 3, y + 2, r * 0.95, r * 0.45), 0.55)
    trunk = (np.abs(XX - x) <= 1.5) & (YY > y - 5) & (YY <= y + 1)
    cv.put(trunk, CLIFF[2]); cv.put(trunk & (XX < x), CLIFF[3])
    cv.trunks.append((x, y))
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
        shade_blob(cv, m, ux, uy, cr, pal, TEX, 0.15 + (cy - uy) / r * 0.25)
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
    cv.trunks.append((x, y))
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
    shade_blob(cv, m, x, y - r * 0.5, r, LEAF, TEX)
    cv.put(outline_of(m) & ~cv.objects, LEAF[0])
    cv.own(m, True)

def draw_pillar(cv, rng, x, y, r):
    """Basalt column with a mossy cap (reference 1)."""
    h = int(6 + rng.random() * 10)
    body = (np.abs(XX - x) <= r) & (YY >= y) & (YY <= y + h)
    t = np.clip(((-(XX - x) / r + 1) / 2 * 3 + (TEX - 0.5)).astype(int), 0, 3)
    cv.c[body] = BASALT[t][body]
    cv.put(body & (np.abs(XX - x - r * 0.33) < 0.5), BASALT[0])
    cv.put(ellipse(x, y + h, r, r * 0.5) & ~body & (YY > y + h), BASALT[0])
    cv.shade(ellipse(x + 3, y + h + 2, r * 1.1, r * 0.4), 0.5)
    cap = ellipse(x, y, r, r * 0.55)
    shade_blob(cv, cap, x, y, r, MOSS, TEX)
    cv.put(cap & ~shift(cap, 1, 0) & (XX < x + r * 0.3), MOSS[5])
    cv.put(outline_of(body | cap) & ~cv.objects, BASALT[0])
    for _ in range(2):
        gx, gy = x + (rng.random() - 0.5) * r, y + (rng.random() - 0.6) * r * 0.4
        cv.px(gx, gy, GRASS[5]); cv.px(gx + 1, gy - 1, MOSS[5]); cv.px(gx - 1, gy, GRASS[3])
    cv.own(body | cap, True)
    cv.block |= ellipse(x, y + h - 1, r * 0.9, r * 0.5)             # the footprint, not the cap

def draw_boulder(cv, x, y, r, pond):
    m = ellipse(x, y - r * 0.4, r, r * 0.8)
    if pond[int(y) % H, int(x) % W]:
        ring = ellipse(x, y, r + 2, r * 0.6) & ~m & pond
        cv.put(ring & (TEX > 0.35), WATER[5])
    else:
        cv.block |= m
    shade_blob(cv, m, x, y - r * 0.4, r, CLIFF, TEX)
    cv.put(outline_of(m) & ~cv.objects, CLIFF[0])
    cv.put(m & ~shift(m, 1, 0), CLIFF[5])
    cv.own(m, False)

TEX = None

def main():
    global TEX
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "assets/sprites/terrain")
    TEX = fbm(H, W, 3, 2, np.random.default_rng(seed + 991))
    ground, over, mask = build(seed)
    ground.save(out / "landscape_sample_ground.png", optimize=True)
    over.save(out / "landscape_sample_over.png", optimize=True)
    mask.save(out / "landscape_sample_mask.png", optimize=True)
    print("wrote", out)

if __name__ == "__main__":
    main()
