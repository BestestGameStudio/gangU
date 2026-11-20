"""Pack the SpriteU Sand General into gangU's PNG, manifest, and SpriteFrames.

Run from gangU: python3 tools/sprites/pack_roman_general_spriteu.py SPRITEU.json
Requires Pillow.
"""
import argparse
import json
from math import ceil, sqrt
from pathlib import Path

from PIL import Image, ImageColor

ASSETS = Path(__file__).resolve().parents[2] / "assets" / "sprites"
TEXTURE = "roman_general_v5.png"
LOOPS = {"idle", "walk", "run"}


def pack(sprite, output):
    width, height = sprite["w"], sprite["h"]
    palette = {key: (*ImageColor.getrgb(color), 255) for key, color in sprite["palette"].items()}
    palette["."] = (0, 0, 0, 0)
    clips = sprite["animations"]
    frame_count = sum(len(clip["frames"]) for clip in clips.values())
    columns = ceil(sqrt(frame_count * height / width))
    sheet = Image.new("RGBA", (columns * width, ceil(frame_count / columns) * height))
    manifest = {"frame_size": [width, height], "columns": columns, "animations": []}
    resource = [
        f'[gd_resource type="SpriteFrames" load_steps={frame_count + 2} format=3]',
        f'[ext_resource type="Texture2D" path="res://assets/sprites/{TEXTURE}" id="1"]',
    ]
    animations = []
    cell = 0
    for name, clip in clips.items():
        animation = name.replace("-", "_")
        record = {"name": name, "first_cell": cell, "frame_count": len(clip["frames"]),
                  "durations_ms": [frame["ms"] for frame in clip["frames"]], "tags": clip["tags"]}
        manifest["animations"].append(record)
        frame_refs = []
        for index, frame in enumerate(clip["frames"]):
            x, y = (cell % columns) * width, (cell // columns) * height
            rows = frame["rows"]
            if len(rows) != height or any(len(row) != width for row in rows):
                raise ValueError(f"{name} frame {index} has incorrect dimensions")
            pixels = bytes(channel for row in rows for key in row for channel in palette[key])
            sheet.paste(Image.frombytes("RGBA", (width, height), pixels), (x, y))
            texture = f"{animation}_{index}"
            resource.append(f'[sub_resource type="AtlasTexture" id="{texture}"]\n'
                            'atlas = ExtResource("1")\n'
                            f'region = Rect2({x}, {y}, {width}, {height})\n'
                            'filter_clip = true')
            frame_refs.append(
                f'{{"duration": {frame["ms"] / 1000:.3f}, "texture": SubResource("{texture}")}}'
            )
            cell += 1
        loop = str(name.rsplit("-", 1)[0] in LOOPS).lower()
        animations.append(f'{{"frames": [{", ".join(frame_refs)}], "loop": {loop}, '
                          f'"name": &"{animation}", "speed": 1.0}}')
    resource.append('[resource]\nanimations = [\n' + ',\n'.join(animations) + '\n]')
    sheet.save(output / TEXTURE)
    (output / "roman_general_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "roman_general_frames.tres").write_text("\n\n".join(resource) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    pack(json.loads(args.source.read_text()), ASSETS)


if __name__ == "__main__":
    main()
