"""Pack SpriteU alpha-ID stencil and parameterized gradient to true RGBA.
Original procedural geometry. Run from gangU root, requires Pillow.
Previewed alpha composition is preserved exactly at integer dimensions.
"""
import json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
RED=(237,69,74)
ALPHA=(178,108,62,32,14,4)

def render_lane(width,height,progress=0.0):
    """Near side x=0 is open. Local +x points toward attack destination.
    width/height integer world pixels; progress clamped 0..1.
    Five inward fade bands plus a 1px outer edge, constant across sizes.
    """
    assert width>=12 and height>=12
    progress=max(0.0,min(1.0,progress))
    reach=width*progress
    im=Image.new('RGBA',(width,height));pixels=[]
    for y in range(height):
        for x in range(width):
            inset=min(y,height-1-y,width-1-x)
            outline=ALPHA[inset] if inset<len(ALPHA) else 0
            fill=round(112*(1-x/max(1,reach))**0.8) if reach>0 and x<reach else 0
            alpha=round(outline+fill*(1-outline/255))
            pixels.append((*RED,alpha) if alpha else (0,0,0,0))
    im.putdata(pixels)
    return im

def main():
    source=json.loads((ROOT/'tools/sprites/specs/charge_telegraph.spriteu.json').read_text())
    rows=source['animations']['telegraph']['frames'][0]['rows']
    lut=dict(zip('abcdef',ALPHA))
    im=Image.new('RGBA',(64,32))
    im.putdata([(*RED,lut[c]) if c!='.' else (0,0,0,0) for r in rows for c in r])
    out=ROOT/'assets/sprites'
    out.mkdir(parents=True,exist_ok=True)
    im.save(out/'charge_telegraph_border.png')
    assert im.tobytes()==render_lane(64,32,0).tobytes()
    # Parameterized-size reference, not a texture to stretch.
    render_lane(248,48,0).save(out/'charge_telegraph_reference_empty.png')
    render_lane(248,48,1).save(out/'charge_telegraph_reference_full.png')
    print('Packed constant-red RGBA stencil and 248x48 references.')

if __name__=='__main__':main()
