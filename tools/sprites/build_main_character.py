#!/usr/bin/env python3
"""Build assets/sprites/main_character.png and the WizardSprite SpriteFrames
block in game/core/main.tscn from the SpriteU player-wizard sheet.

The SpriteU JSON (tools/gen_player_wizard.py + tools/player_wizard_rig.py +
tools/player_wizard_anims.py in the SpriteU repo) is the source of truth: it
carries 24 animations - idle, walk, dash, cast-bolt, cast-twohand, cast-raise,
each in down/up/left/right - as 32x48 palette grids with per-frame timings.

Sheet layout (192x1152, 6 cols x 24 rows of 32x48 cells): one row per
animation in ROWS order below; cells beyond an animation's frame count stay
transparent. The generated SpriteFrames use those exact cells, so the PNG and
the .tscn never drift. Frame timing: SpriteFrames speed is 50, so a frame's
duration value is ms/50 (idle-down frame 0: 380 ms -> 7.6).

usage: python tools/sprites/build_main_character.py [--json PATH]
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_JSON = os.path.join(ROOT, "..", "spriteu", "sprites", "player-wizard.json")
PNG_PATH = os.path.join(ROOT, "assets", "sprites", "main_character.png")
TSCN_PATH = os.path.join(ROOT, "game", "core", "main.tscn")

CELL_W, CELL_H, COLS = 32, 48, 6
FACING = ["down", "up", "left", "right"]
GROUPS = ["idle", "walk", "dash", "cast-bolt", "cast-twohand", "cast-raise", "hurt", "death"]
ROWS = [(g, f) for g in GROUPS for f in FACING]
LOOP = {"idle": True, "walk": True, "dash": False,
        "cast-bolt": False, "cast-twohand": False, "cast-raise": False,
        "hurt": False, "death": False}
SPEED = 20.0  # SpriteFrames speed; frame time = duration/speed = (ms/DUR_DIV)/SPEED = ms/1000 s
DUR_DIV = 50.0


def godot_name(group: str, facing: str) -> str:
    return group.replace("-", "_") + "_" + facing


def render_png(anims: dict) -> None:
    img = Image.new("RGBA", (COLS * CELL_W, len(ROWS) * CELL_H), (0, 0, 0, 0))
    for row, (group, facing) in enumerate(ROWS):
        frames = anims[f"{group}-{facing}"]["frames"]
        assert len(frames) <= COLS, (group, facing, len(frames))
        for col, frame in enumerate(frames):
            rows = frame["rows"]
            assert len(rows) == CELL_H and all(len(r) == CELL_W for r in rows)
            for y, line in enumerate(rows):
                for x, ch in enumerate(line):
                    if ch == ".":
                        continue
                    hexcol = d_palette[ch]
                    img.putpixel((col * CELL_W + x, row * CELL_H + y),
                                 (int(hexcol[1:3], 16), int(hexcol[3:5], 16),
                                  int(hexcol[5:7], 16), 255))
    img.save(PNG_PATH)
    print(f"{PNG_PATH}: {img.size}, {len(ROWS)} rows x {COLS} cols")


def tscn_block() -> str:
    out = []
    for row, (group, facing) in enumerate(ROWS):
        nframes = len(anims[f"{group}-{facing}"]["frames"])
        for col in range(nframes):
            aid = f"AtlasTexture_{godot_name(group, facing)}_{col}"
            out.append(f'[sub_resource type="AtlasTexture" id="{aid}"]\n'
                       f'atlas = ExtResource("4_sheet")\n'
                       f'region = Rect2({col * CELL_W}, {row * CELL_H}, {CELL_W}, {CELL_H})\n')
    anims_txt = []
    for group, facing in ROWS:
        frames = anims[f"{group}-{facing}"]["frames"]
        name = godot_name(group, facing)
        ftxt = ", ".join(
            '{\n"duration": %s,\n"texture": SubResource("AtlasTexture_%s_%d")\n}'
            % (("%g" % (f["ms"] / DUR_DIV)), name, col)
            for col, f in enumerate(frames))
        anims_txt.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %g\n}'
                         % (ftxt, "true" if LOOP[group] else "false", name, SPEED))
    out.append('[sub_resource type="SpriteFrames" id="SpriteFrames_wizard"]\n'
               'animations = [%s]\n' % ",\n".join(anims_txt))
    return "\n".join(out)


def splice_tscn() -> None:
    src = open(TSCN_PATH).read()
    start_marker = '[sub_resource type="AtlasTexture" id="AtlasTexture_idle_down_0"]'
    start = src.index(start_marker)
    # the wizard block ends with the SpriteFrames animations array's closing
    # "}]" right before the "[node name="Main" ...]" line
    node_main = src.index('[node name="Main"')
    end = src.rindex("}]", start, node_main) + 2
    src = src[:start] + tscn_block() + "\n" + src[end:]
    open(TSCN_PATH, "w").write(src)
    print(f"{TSCN_PATH}: wizard block regenerated ({len(ROWS)} animations)")


if __name__ == "__main__":
    args = sys.argv[1:]
    json_path = args[args.index("--json") + 1] if "--json" in args else DEFAULT_JSON
    d = json.load(open(json_path))
    d_palette = d["palette"]
    anims = d["animations"]
    missing = [f"{g}-{f}" for g, f in ROWS if f"{g}-{f}" not in anims]
    assert not missing, missing
    render_png(anims)
    splice_tscn()
