"""Pack the original SpriteU scorpion source into PNG and Godot SpriteFrames.

Run from repo root: python3 tools/sprites/pack_scorpion_spriteu.py
Requires Pillow. Pure art conversion: no gameplay/behavior changes.
"""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DIRECTIONS = ('s', 'se', 'e', 'ne', 'n', 'nw', 'w', 'sw')
ACTIONS = ('idle', 'walk', 'attack', 'hurt', 'death', 'pincer', 'emerge', 'bury')

def main():
    source = json.loads((ROOT / 'tools/sprites/specs/scorpion.spriteu.json').read_text())
    palette = {k: tuple(bytes.fromhex(v.lstrip('#'))) + (255,) for k, v in source['palette'].items()}
    counts = [len(source['animations'][a + '_s_q00']['frames']) for a in ACTIONS]
    atlas = Image.new('RGBA', (1024, 128 * sum(counts)))
    textures, animations = [], []
    row = 0
    for action, count in zip(ACTIONS, counts):
        for col, direction in enumerate(DIRECTIONS):
            name = action + '_' + direction
            frames = source['animations'][name + '_q00']['frames']
            assert len(frames) == count
            refs = []
            for frame_index, frame in enumerate(frames):
                image = Image.new('RGBA', (128, 128))
                for qy in range(2):
                    for qx in range(2):
                        quad = source['animations'][name + f'_q{qx}{qy}']['frames'][frame_index]
                        assert quad['ms'] == frame['ms']
                        pixels = Image.new('RGBA',(64,64))
                        pixels.putdata([palette.get(c,(0,0,0,0)) for line in quad['rows'] for c in line])
                        image.paste(pixels,(qx*64,qy*64))
                atlas.paste(image, (col * 128, (row + frame_index) * 128))
                key = f'Atlas_{row + frame_index}_{col}'
                textures.append(f'[sub_resource type="AtlasTexture" id="{key}"]\natlas = ExtResource("1_sheet")\nregion = Rect2({col * 128}, {(row + frame_index) * 128}, 128, 128)\n')
                refs.append('{"duration": ' + str(frame['ms'] / 100.0) + ', "texture": SubResource("' + key + '")}')
            animations.append('{"frames": [' + ', '.join(refs) + '], "loop": ' + ('true' if action in ('idle', 'walk') else 'false') + ', "name": &"' + name + '", "speed": 10.0}')
        row += count
    png = ROOT / 'assets/sprites/scorpion.png'
    tres = ROOT / 'data/sprites/scorpion_frames.tres'
    png.parent.mkdir(parents=True, exist_ok=True)
    tres.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(png)
    tres.write_text(f'[gd_resource type="SpriteFrames" load_steps={len(textures) + 2} format=3]\n\n[ext_resource type="Texture2D" path="res://assets/sprites/scorpion.png" id="1_sheet"]\n\n' + '\n'.join(textures) + '\n[resource]\nanimations = [' + ',\n'.join(animations) + ']\n')
    print(f'{png}: {atlas.size}; {tres}: {len(animations)} animations')

if __name__ == '__main__':
    main()
