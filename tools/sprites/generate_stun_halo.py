"""Original generator for a SpriteU generic dizzy/stun halo candidate.
Procedural pixel geometry, not editor-drawn or image-model-generated.
"""
import json, math
from pathlib import Path
P={'o':'#3A3440','d':'#9B753F','s':'#C99C52','m':'#E7C47A','h':'#FFF0B0'}

def draw(k):
 g=[['.']*64 for _ in range(64)]
 def px(x,y,c):
  if 0<=x<64 and 0<=y<64:g[y][x]=c
 # Broken ellipse makes the orbit clear without becoming a solid crown.
 for i in range(48):
  if i%12>6:continue
  t=i/48*2*math.pi
  x=round(32+15*math.cos(t));y=round(14+4*math.sin(t))
  px(x,y,'s' if math.sin(t)>0 else 'd')
 # Three small stars, drawn back-to-front so overlap remains consistent.
 stars=[]
 for j in range(3):
  t=2*math.pi*(k/8+j/3)
  stars.append((math.sin(t),round(32+15*math.cos(t)),round(14+4*math.sin(t))))
 for depth,x,y in sorted(stars):
  # Four-point star with restrained dark outline and pale lit core.
  shape=[(0,-3),(1,-1),(3,0),(1,1),(0,3),(-1,1),(-3,0),(-1,-1)]
  pts=set(shape+[(dx,dy) for dy in range(-1,2) for dx in range(-1,2)])
  for dx,dy in pts:
   for ox,oy in ((-1,0),(1,0),(0,-1),(0,1)):
    if (dx+ox,dy+oy) not in pts:px(x+dx+ox,y+dy+oy,'o')
  for dx,dy in pts:px(x+dx,y+dy,'s' if dy>0 else 'm')
  px(x,y,'h');px(x,y-1,'h')
 return [''.join(r) for r in g]

src={'name':'generic-stun-halo','w':64,'h':64,'palette':P,'animations':{'stun':{'loop':True,'frames':[{'ms':75,'rows':draw(k)} for k in range(8)]}}}
Path(__file__).resolve().parents[2].joinpath('tools/sprites/specs/stun_halo.spriteu.json').write_text(json.dumps(src,separators=(',',':'))+'\n')
print('8 frames x 75ms, 600ms loop, local ring center (32,14).')
