"""Rebuild the approved128px scorpion SpriteU quadrants from original rig art.
Run from any directory. Requires Pillow. Does not change game tuning.
"""
from pathlib import Path
import json
import export_transitions as ex
ROOT=Path(__file__).resolve().parents[3]
source={'name':'large-scorpion-animated-study','w':64,'h':64,'palette':dict(ex.P),'animations':{}}
reverse={tuple(bytes.fromhex(v.lstrip('#'))):k for k,v in ex.P.items()}
for action,times in ex.SETS.items():
    for di,direction in enumerate(ex.DIRS):
        images=[ex.transition(di,k,action=='bury') if action in ('emerge','bury') else ex.draw(di,action,k,len(times)) for k in range(len(times))]
        for qy in range(2):
            for qx in range(2):
                frames=[]
                for k,image in enumerate(images):
                    rows=[''.join(reverse[image.getpixel((qx*64+x,qy*64+y))[:3]] if image.getpixel((qx*64+x,qy*64+y))[3] else '.' for x in range(64)) for y in range(64)]
                    frames.append({'ms':times[k],'rows':rows})
                source['animations'][f'{action}_{direction}_q{qx}{qy}']={'frames':frames,'loop':action in ('idle','walk')}
path=ROOT/'tools/sprites/specs/scorpion.spriteu.json'
path.write_text(json.dumps(source,separators=(',',':'))+'\n')
print('Rebuilt approved native128px source as SpriteU64px quadrants')
