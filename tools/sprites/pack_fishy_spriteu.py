"""Pack the SpriteU Fishy (BestestGameStudio/SpriteU sprites/fishy.json) into
gangU's fishy.png atlas + fishy_frames.tres.

usage: python3 -I tools/sprites/pack_fishy_spriteu.py SPRITEU_FISHY.json OLD_FISHY.png \
           assets/sprites/fishy.png --tres data/sprites/fishy_frames.tres

The SpriteU sheet is 64x64, front view, with idle, walk, attack, death,
hit, cast and cast-up/down/left animations. gangU's behavior (game/enemies/behaviors/enemy_behavior_fishy.gd)
needs idle/walk/attack/hurt/death plus cast/cast_hold/reel/retract per cast
direction, and the fishing line reads the `hook` cell.

Mapping (SpriteU -> gangU):
- idle            <- idle (2026-11-14 package: 2-frame subtle breath loop,
                     850ms per frame, replacing the single still)
- hurt            <- hit[0..4]
- cast            <- cast[1,2,3]        (wind-up -> impact, matches the 0.6s
                                         behavior windup at the durations below)
- cast_hold       <- cast[3]
- reel            <- cast[3,4,5,4] loop (rod pumps while cranking)
- retract         <- cast[5,4,1]
- cast_up/_down/_left and their cast_hold/reel/retract companions: same frames
  from the matching directional cast. The plain names are the right cast.
- walk/attack/death <- the SpriteU package's walk/attack/death when present
                     (walk + death added 2026-11-14; slowed walk + attack in the
                     same-day v3 package), else the PREVIOUS sheet's cells,
                     bottom-aligned into 64x64
- hook            <- the previous sheet's hook cell (the flying hook graphic
                     the FishingLine draws at the line end; unchanged art)

Cells are 64x64, 8 columns. data/sprites/fishy_frames.tres is regenerated
whole by this script.
"""
import json
import sys

from PIL import Image

CELL = 64
COLS = 8

# (animation name, loop, speed, [(cell-frame, duration)], source description)
def build_layout(sprite):
    anims = sprite["animations"]

    def rows(anim, i):
        f = anims[anim]["frames"][i]
        return f["rows"] if isinstance(f, dict) else f

    cells = []  # list of (key, rows)

    def add(key, grid):
        cells.append((key, grid))
        return len(cells) - 1

    idle = [add("idle", rows("idle", i)) for i in range(len(anims["idle"]["frames"]))]
    idle_ms = [f.get("ms", 850) if isinstance(f, dict) else 850 for f in anims["idle"]["frames"]]
    # Old-sheet fallbacks (64x52 cells, bottom-aligned at pack time) for any
    # state the package does not ship: walk = old cells 3,4,5,4; death = old
    # 4,5; attack = old cells 18,19.
    if "walk" in anims:
        walk = [add("walk", rows("walk", i)) for i in range(len(anims["walk"]["frames"]))]
    else:
        walk = [add("walk", ("old", i)) for i in (3, 4, 5, 4)]
    if "attack" in anims:
        attack = [add("attack", rows("attack", i)) for i in range(len(anims["attack"]["frames"]))]
        attack_ms = [f.get("ms", 100) if isinstance(f, dict) else 100 for f in anims["attack"]["frames"]]
    else:
        attack = [add("attack", ("old", i)) for i in (18, 19)]
        attack_ms = None
    hurt = [add("hurt", rows("hit", i)) for i in range(5)]
    if "death" in anims:
        death = [add("death", rows("death", i)) for i in range(len(anims["death"]["frames"]))]
        death_ms = [f.get("ms", 100) if isinstance(f, dict) else 100 for f in anims["death"]["frames"]]
    else:
        death = [add("death", ("old", i)) for i in (4, 5)]
        death_ms = None

    dir_anims = {"": "cast", "_up": "cast-up", "_down": "cast-down", "_left": "cast-left"}
    casts, holds, reels, retracts = {}, {}, {}, {}
    for suffix, anim in dir_anims.items():
        casts[suffix] = [add("cast" + suffix, rows(anim, i)) for i in (1, 2, 3)]
        holds[suffix] = [add("cast_hold" + suffix, rows(anim, 3))]
        reels[suffix] = [add("reel" + suffix, rows(anim, i)) for i in (3, 4, 5, 4)]
        retracts[suffix] = [add("retract" + suffix, rows(anim, i)) for i in (5, 4, 1)]

    hook_index = len(cells)  # filled from the old sheet by the caller
    cells.append(("hook", ("old_hook", 20)))  # old sheet row 2, col 4

    anims_out = [
        # idle: 200ms base unit; package frames carry their own ms (850+850).
        {"name": "idle", "speed": 5.0, "loop": True,
         "frames": [[c, ms / 200.0] for c, ms in zip(idle, idle_ms)]},
        # walk: 8fps = the package's 125ms per frame.
        {"name": "walk", "speed": 8.0, "loop": True, "frames": [[i, 1.0] for i in walk]},
        # attack: old fallback keeps [1.0, 1.5] @12; a package attack keeps
        # its own per-frame ms at a 100ms base unit (like death).
        {"name": "attack", "speed": 10.0 if attack_ms else 12.0, "loop": False,
         "frames": ([[c, ms / 100.0] for c, ms in zip(attack, attack_ms)] if attack_ms
                    else [[attack[0], 1.0], [attack[1], 1.5]])},
        {"name": "hurt", "speed": 12.0, "loop": False, "frames": [[i, 1.0] for i in hurt]},
        # death: one-shot; 100ms base unit, package per-frame ms preserved
        # (old fallback: 1.0 + 3.0 at speed 6, inside the same 1-3s window).
        {"name": "death", "speed": 10.0 if death_ms else 6.0, "loop": False,
         "frames": ([[c, ms / 100.0] for c, ms in zip(death, death_ms)] if death_ms
                    else [[death[0], 1.0], [death[1], 3.0]])},
    ]
    for suffix in dir_anims:
        # wind-up 340ms, impact 90+140ms: land the release at the behavior's
        # 0.6s windup (3.4 + 0.9 + 1.4 units at speed 10 = 0.57s).
        anims_out.append({"name": "cast" + suffix, "speed": 10.0, "loop": False,
                          "frames": [[casts[suffix][0], 3.4], [casts[suffix][1], 0.9], [casts[suffix][2], 1.4]]})
        anims_out.append({"name": "cast_hold" + suffix, "speed": 1.0, "loop": True,
                          "frames": [[holds[suffix][0], 1.0]]})
        anims_out.append({"name": "reel" + suffix, "speed": 6.0, "loop": True,
                          "frames": [[i, 1.0] for i in reels[suffix]]})
        anims_out.append({"name": "retract" + suffix, "speed": 10.0, "loop": False,
                          "frames": [[i, 1.0] for i in retracts[suffix]]})
    anims_out.append({"name": "hook", "speed": 1.0, "loop": True, "frames": [[hook_index, 1.0]]})
    return cells, anims_out


def render_cell(grid, palette, w, h):
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    px = img.load()
    for y in range(min(h, CELL)):
        row = grid[y]
        for x in range(min(w, CELL, len(row))):
            c = row[x]
            if c == ".":
                continue
            rgb = palette[c]
            px[x, y] = (rgb[0], rgb[1], rgb[2], 255)
    return img


def rgb_of(v):
    v = v.lstrip("#")
    if len(v) == 3:
        v = "".join(c * 2 for c in v)
    return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))


def main():
    src, old_png, out_png = sys.argv[1], sys.argv[2], sys.argv[3]
    opt = dict(zip(sys.argv[4::2], sys.argv[5::2]))
    out_tres = opt["--tres"]

    sprite = json.load(open(src))
    palette = {k: rgb_of(v) for k, v in sprite["palette"].items()}
    w, h = sprite.get("w", 64), sprite.get("h", 64)

    cells, anims = build_layout(sprite)
    rows_n = (len(cells) + COLS - 1) // COLS
    sheet = Image.new("RGBA", (COLS * CELL, rows_n * CELL), (0, 0, 0, 0))
    for i, (key, grid) in enumerate(cells):
        ox, oy = (i % COLS) * CELL, (i // COLS) * CELL
        if isinstance(grid, tuple):
            # Previous sheet cell (64x52), bottom-aligned in the 64x64 cell so
            # the feet keep their old offset (old sprite offset (0,-11) ->
            # new (0,-16); feet row ~51 -> 63). The hook cell pastes at the
            # top instead, keeping FishingLine.HOOK_CELL_CENTER = (37, 26).
            kind, idx = grid
            col, row = idx % 8, idx // 8
            old = Image.open(old_png).convert("RGBA").crop((64 * col, 52 * row, 64 * col + 64, 52 * row + 52))
            # No mask: paste onto the blank atlas copies RGBA verbatim (a
            # self-mask would premultiply and alter semi-transparent pixels).
            sheet.paste(old, (ox, oy + (0 if kind == "old_hook" else CELL - 52)))
            continue
        sheet.paste(render_cell(grid, palette, w, h), (ox, oy))
    sheet.save(out_png)
    print("wrote", out_png, sheet.size, len(cells), "cells")

    lines = []
    n_ext = 1
    n_subs = len(cells)
    lines.append('[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (n_ext + n_subs + 1))
    lines.append("")
    lines.append('[ext_resource type="Texture2D" path="res://assets/sprites/fishy.png" id="1_sheet"]')
    lines.append("")
    for i in range(n_subs):
        ox, oy = (i % COLS) * CELL, (i // COLS) * CELL
        lines.append('[sub_resource type="AtlasTexture" id="AtlasTexture_c%d"]' % i)
        lines.append('atlas = ExtResource("1_sheet")')
        lines.append("region = Rect2(%d, %d, %d, %d)" % (ox, oy, CELL, CELL))
        lines.append("")
    anim_chunks = []
    for a in anims:
        frames = ", ".join('{\n"duration": %s,\n"texture": SubResource("AtlasTexture_c%d")\n}' % (
            ("%g" % d), i) for i, d in a["frames"])
        anim_chunks.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}' % (
            frames, "true" if a["loop"] else "false", a["name"], "%g" % a["speed"]))
    lines.append("[resource]")
    lines.append("animations = [%s]" % ", ".join(anim_chunks))
    open(out_tres, "w").write("\n".join(lines) + "\n")
    print("wrote", out_tres, "with", len(anims), "animations")


if __name__ == "__main__":
    main()
