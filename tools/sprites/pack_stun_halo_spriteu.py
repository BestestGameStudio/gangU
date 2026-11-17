"""Pack approved generic stun SpriteU JSON into transparent atlas and SpriteFrames.
Run from gangU root: python tools/sprites/pack_stun_halo_spriteu.py
Requires Pillow. Art-only; no runtime integration.
"""
import json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
src=json.loads((ROOT/'tools/sprites/specs/stun_halo.spriteu.json').read_text())
pal={k:tuple(bytes.fromhex(v.lstrip('#')))+(255,) for k,v in src['palette'].items()}
frames=src['animations']['stun']['frames']
atlas=Image.new('RGBA',(len(frames)*64,64))
textures=[];refs=[]
for i,f in enumerate(frames):
 im=Image.new('RGBA',(64,64));im.putdata([pal.get(c,(0,0,0,0)) for r in f['rows'] for c in r])
 atlas.paste(im,(i*64,0))
 key=f'Atlas_{i}'
 textures.append(f'[sub_resource type="AtlasTexture" id="{key}"]\natlas = ExtResource("1_sheet")\nregion = Rect2({i*64}, 0, 64, 64)\n')
 refs.append('{"duration": '+str(f['ms']/100.0)+', "texture": SubResource("'+key+'")}')
atlas.save(ROOT/'assets/sprites/stun_halo.png')
(ROOT/'data/sprites/stun_halo_frames.tres').write_text('[gd_resource type="SpriteFrames" load_steps='+str(len(frames)+2)+' format=3]\n\n[ext_resource type="Texture2D" path="res://assets/sprites/stun_halo.png" id="1_sheet"]\n\n'+'\n'.join(textures)+'\n[resource]\nanimations = [{"frames": ['+', '.join(refs)+'], "loop": true, "name": &"stun", "speed": 10.0}]\n')
print('stun_halo.png 512x64; animation stun, 8x75ms, loop=true.')
