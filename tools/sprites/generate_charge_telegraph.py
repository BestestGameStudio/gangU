"""Original SpriteU open-near-end charge telegraph stencil generator.
Palette IDs encode alpha stages. SpriteU RGB preview is diagnostic only;
use pack_charge_telegraph_spriteu.py for true constant-red RGBA.
"""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
P={'a':'#ED454A','b':'#C0383C','c':'#972C30','d':'#6E2023','e':'#481517','f':'#230A0B'}
rows=[''.join('abcdef'[min(y,31-y,63-x)] if min(y,31-y,63-x)<6 else '.' for x in range(64)) for y in range(32)]
s={'name':'open-charge-gradient','w':64,'h':32,'palette':P,'animations':{'telegraph':{'frames':[{'ms':100,'rows':rows}]}}}
(ROOT/'tools/sprites/specs/charge_telegraph.spriteu.json').write_text(json.dumps(s,separators=(',',':'))+'\n')
print('Generated 64x32 three-edge SpriteU stencil, open at x=0.')
