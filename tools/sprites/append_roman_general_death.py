"""Append the SpriteU general death animations to gangU's roman general atlas.

SpriteU source: BestestGameStudio/SpriteU branch instinct/roman-general-v4,
sprites/14-sandstone-roman-general.json (death-front/back/right, 13 frames,
2780 ms, tags recoil/point/fall/fallen). gangU mirrors left from right, so
three rows are appended to roman_general_v4.png (rows 30-32); every existing
row stays pixel-identical. roman_general_manifest.json gains the three row
records and roman_general_frames.tres gains AtlasTexture sub-resources plus
non-looping death_* animations (durations in seconds, speed 1.0).

Usage (needs Pillow; run with python3 -I from a venv):
  python3 -I tools/sprites/append_roman_general_death.py SPRITEU.json \
      assets/sprites/roman_general_v4.png assets/sprites/roman_general_manifest.json \
      --tres assets/sprites/roman_general_frames.tres
"""
import json
import re
import sys

from PIL import Image

CELL = 64
COLS = 20
DEATH = [("death-front", 30), ("death-back", 31), ("death-right", 32)]


def render_frame(palette, rows):
    img = Image.new("RGBA", (CELL, CELL))
    px = img.load()
    for y, row in enumerate(rows):
        assert len(row) == CELL, "frame row width mismatch"
        for x, key in enumerate(row):
            if key != ".":
                px[x, y] = palette[key]
    return img


def main():
    src_path, sheet_path, manifest_path = sys.argv[1:4]
    tres_path = sys.argv[sys.argv.index("--tres") + 1]
    sprite = json.load(open(src_path))
    palette = {k: tuple(bytes.fromhex(v.lstrip("#"))) + (255,)
               for k, v in sprite["palette"].items()}
    anims = sprite["animations"]

    sheet = Image.open(sheet_path).convert("RGBA")
    w, h = sheet.size
    assert w == CELL * COLS, "unexpected atlas width"
    need_h = CELL * (DEATH[-1][1] + 1)
    assert h == CELL * DEATH[0][1], "expected exactly %d existing rows" % DEATH[0][1]
    grown = Image.new("RGBA", (w, need_h))
    grown.paste(sheet, (0, 0))

    manifest = json.load(open(manifest_path))
    assert len(manifest["rows"]) == DEATH[0][1], "manifest/atlas row mismatch"

    for name, row_i in DEATH:
        a = anims[name]
        frames = a["frames"]
        assert len(frames) <= COLS, "animation wider than the atlas"
        for col_i, f in enumerate(frames):
            grown.paste(render_frame(palette, f["rows"]), (col_i * CELL, row_i * CELL))
        manifest["rows"].append({
            "row": row_i,
            "name": name,
            "frame_count": len(frames),
            "durations_ms": [f["ms"] for f in frames],
            "tags": a["tags"],
        })
    grown.save(sheet_path)
    json.dump(manifest, open(manifest_path, "w"), indent=2)
    open(manifest_path, "a").write("\n")

    tres = open(tres_path).read()
    subs = ""
    dicts = []
    for name, row_i in DEATH:
        gd = name.replace("-", "_")
        a = anims[name]
        for col_i, f in enumerate(a["frames"]):
            subs += ('[sub_resource type="AtlasTexture" id="%s_%d"]\n'
                     "atlas = ExtResource(\"1\")\n"
                     "region = Rect2(%d, %d, 64, 64)\n\n") % (
                         gd, col_i, col_i * CELL, row_i * CELL)
        frames_s = ", ".join(
            '{"duration": %.3f, "texture": SubResource("%s_%d")}' % (
                f["ms"] / 1000.0, gd, col_i)
            for col_i, f in enumerate(a["frames"]))
        dicts.append('{"frames": [%s], "loop": false, "name": &"%s", "speed": 1.0}' % (
            frames_s, gd))
    old_steps = int(re.search(r"load_steps=(\d+)", tres).group(1))
    added = sum(len(anims[n]["frames"]) for n, _ in DEATH)
    tres = tres.replace("load_steps=%d" % old_steps,
                        "load_steps=%d" % (old_steps + added), 1)
    # Sub-resources must precede the [resource] section.
    anchor = "[resource]"
    i = tres.index(anchor)
    tres = tres[:i] + subs + tres[i:]
    assert tres.rstrip().endswith("}]"), "unexpected animations array tail"
    tail = tres.rstrip()[:-2]
    tres = tail + "}, " + ", ".join(dicts) + "]\n"
    open(tres_path, "w").write(tres)
    print("appended %d death frames over rows %d-%d" % (added, DEATH[0][1], DEATH[-1][1]))


if __name__ == "__main__":
    main()
