"""Animated water texture functions shared by the SpriteU water tile sprite
(sprites/water-tile.json) and the gangU dual-grid sheet generator.

Technique sources (studied references, not copied):
- slynyrd Pixelblog #43 (top-down tiles): water = a 1 px interconnected
  blob-line network over a flat base, plus sparse sparkle highlights;
  animate by swapping/shifting the line pattern between frames.
- wolthera.info "Animating Water Tiles part 1: Edges": shoreline foam uses
  expand/contract with a fading underwave line; ocean rhythm = the wave
  reaches further up, then retreats.

Everything is deterministic (hash noise, no RNG state).
"""

FRAMES = 5
# Per-frame cadence in ms (slynyrd's uneven 0.5/0.3 rhythm, scaled down).
FRAME_MS = [220, 160, 220, 160, 140]

# Palette (muted teal to sit next to gangU's olive grass and warm sand).
DEEP = (24, 52, 84)
BASE = (38, 88, 124)
MID = (54, 116, 150)
LIGHT = (86, 152, 182)
LINE = (96, 158, 186)       # blob-network lines (kept dim)
SPARKLE = (196, 230, 236)
FOAM = (232, 242, 240)
FOAM_DIM = (168, 206, 208)  # fading underwave


def _hash2(x: int, y: int, salt: int) -> float:
    h = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
    h &= 0xFFFFFFFFFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFFFFFFFFFF
    h = h ^ (h >> 16)
    return float(h & 0xFFFF) / 65535.0


def _vnoise(x: float, y: float, salt: int) -> float:
    """Bilinear value noise over the integer hash grid."""
    xi, yi = int(x // 1), int(y // 1)
    xf, yf = x - xi, y - yi
    a = _hash2(xi, yi, salt)
    b = _hash2(xi + 1, yi, salt)
    c = _hash2(xi, yi + 1, salt)
    d = _hash2(xi + 1, yi + 1, salt)
    u = xf * xf * (3 - 2 * xf)
    v = yf * yf * (3 - 2 * yf)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


# Frame offsets make the blob network drift in a small loop (5 steps).
_DRIFT = [(0, 0), (3, 1), (5, 4), (2, 6), (-2, 3)]


def wave_line(x: float, y: float, frame: int) -> bool:
    """True when (x, y) sits on the 1 px blob-network line this frame.

    A narrow band around the 0.5 contour of smooth noise gives wavy,
    interconnected lines; the sample point drifts per frame so the
    network appears to flow and loops after FRAMES frames.
    """
    dx, dy = _DRIFT[frame % FRAMES]
    # Patch gate: the network shows in slow-drifting patches instead of
    # covering the whole tile (full coverage read as scribble at 64 px).
    gate = _vnoise((x + dx) / 29.0 + 5.0, (y + dy) / 29.0 + 3.0, 79)
    if gate < 0.56:
        return False
    n = _vnoise((x + dx) / 13.0, (y + dy) / 13.0, 71)
    if abs(n - 0.52) < 0.026:
        return True
    # Second, finer octave, kept sparse so the network stays delicate.
    n2 = _vnoise((x - dy) / 6.0 + 31.0, (y + dx) / 6.0 + 17.0, 73)
    if abs(n2 - 0.5) < 0.022 and _vnoise(x / 21.0 + 9.0, y / 21.0, 77) > 0.62:
        return True
    return False


def sparkle(x: int, y: int, frame: int) -> bool:
    """Sparse 1 px highlights that twinkle on and off over the loop."""
    h = _hash2(x, y, 97)
    if h > 0.028:
        return False
    return int(h * 10000) % FRAMES == frame % FRAMES


def depth_color(depth: float) -> tuple:
    """Base water colour by distance from the shore (px); hard bands keep
    the palette small, like the other gangU sheets."""
    if depth < 10.0:
        return MID
    if depth > 30.0:
        return DEEP
    return BASE


def banded(x: int, y: int, depth: float) -> tuple:
    """depth_color with a 2 px checkerboard dither at the band edges."""
    for edge, lo, hi in ((10.0, MID, BASE), (30.0, BASE, DEEP)):
        if abs(depth - edge) < 2.0:
            if (x + y) % 2 == 0:
                return lo if depth < edge else hi
            return hi if depth < edge else lo
    return depth_color(depth)


def foam_band(frame: int) -> float:
    """How far (px) the foam reaches up the shore this frame."""
    return [2.0, 4.0, 6.0, 4.5, 2.5][frame % FRAMES]


def foam_color(dist_to_land: float, x: int, y: int, frame: int):
    """Foam colour for a water pixel `dist_to_land` px from the shoreline,
    or None. Main band expands/contracts; a dimmer underwave line trails
    inside it (wolthera ocean-wave technique)."""
    band = foam_band(frame)
    if dist_to_land <= band:
        return FOAM
    # Underwave: the previous frame's reach, breaking up as it fades.
    prev = foam_band((frame - 1) % FRAMES)
    if band < dist_to_land <= prev + 1.5 and _hash2(x, y, 131 + frame) < 0.55:
        return FOAM_DIM
    # Stray foam flecks a little further out.
    if dist_to_land <= band + 4.0 and _hash2(x, y, 137 + frame) < 0.10:
        return FOAM_DIM
    return None
