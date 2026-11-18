"""Compose existing gangU tree pixels into packed SpriteU spatial panels.
Own-game art only: terrain_pieces base/top; supplied other-game reference is
layout inspiration, never a pixel source. No new green-circle canopy geometry.
"""
import json,random,math
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
SRC=ROOT.parents[2]/'assets/sprites/terrain'
b=Image.open(SRC/'terrain_pieces_base.png').convert('RGBA');t=Image.open(SRC/'terrain_pieces_top.png').convert('RGBA')
# Remove inherited solid ground-shadow blobs, retaining trunk pixels only.
# The unified ground layer supplies all soft shade instead.
for y in range(b.height):
 for x in range(b.width):
  if not (21<=x%48<=27 and 38<=y%64<=57):b.putpixel((x,y),(0,0,0,0))
b.alpha_composite(t)
wall=Image.new('RGBA',(448,64));r=random.Random(891)
# Back row and front row share overlapping crowns. The gap stays open to sky.
for foot in (48,63):
 for x in list(range(26,181,21))+list(range(270,430,21)):
  v=r.choice((3,5,6,7));tree=b.crop((48*v,0,48*v+48,64))
  # Longer visible trunks make packed trees readable rather than a hedge.
  draw=ImageDraw.Draw(wall)
  wall.alpha_composite(tree,(x-24,foot-68))
  draw.rectangle((x-3,foot-12,x+2,foot-2),fill='#4f3f30')
  draw.line((x-2,foot-11,x-2,foot-3),fill='#776246',width=2)
colors=sorted(set(wall.get_flattened_data())-{(0,0,0,0)})
palette=['#%02x%02x%02x'%c[:3] for c in colors];idx={c:i for i,c in enumerate(colors)}
frames=[]
for i in range(7):
 frame=wall.crop((i*64,0,(i+1)*64,64));vals=list(frame.get_flattened_data());frames.append({'ms':1000,'rows':[[idx.get(c,-1) if c[3] else -1 for c in vals[y*64:(y+1)*64]] for y in range(64)]})
obj={'name':'forest-wall-panels','w':64,'h':64,'palette':palette,'frames':frames,'notes':'Seven spatial panels, not animation. Existing gangU tree pixels arranged into connected wall in SpriteU source. Gap is open, no dark arch.'}
(ROOT/'forest-wall-panels.json').write_text(json.dumps(obj,separators=(',',':'))+'\n')
# Recessed back row closes the far side of the entrance nook.
back=Image.new('RGBA',(448,128));r=random.Random(892)
# Add dense rows behind the entire wall, not a single tower over the entry.
for foot in (52,68,84,100,116):
 for x in range(26,430,17):
  if foot>84 and 177<x<274:continue
  v=r.choice((3,5,6,7));tree=b.crop((48*v,0,48*v+48,64))
  back.alpha_composite(tree,(x-24,foot-56))
  draw=ImageDraw.Draw(back);draw.rectangle((x-2,foot-8,x+1,foot-1),fill='#4f3f30')
for x,foot in [(20,121),(29,109),(44,100),(64,97),(84,100),(99,109),(108,121)]:
 v=r.choice((3,5,6,7));tree=b.crop((48*v,0,48*v+48,64));tree=tree.crop(tree.getbbox());tree=tree.resize((round(tree.width*.8),round(tree.height*.8)),Image.Resampling.NEAREST)
 back.alpha_composite(tree,(160+x-tree.width//2,foot-tree.height))
 draw=ImageDraw.Draw(back);draw.rectangle((160+x-2,foot-8,160+x+1,foot-1),fill='#4f3f30')
# Fill small interior pinholes under overlapping foliage, not the nook.
from PIL import ImageFilter
mask=back.getchannel('A');closed=mask.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.MinFilter(7))
for yy in range(128):
 for xx in range(448):
  if closed.getpixel((xx,yy)) and not mask.getpixel((xx,yy)):
   back.putpixel((xx,yy),(36,71,42,255))
# The left arc joint must not expose a beige square of ground.
for yy in range(79,103):
 for xx in range(167,185):
  if not back.getpixel((xx,yy))[3]:back.putpixel((xx,yy),(36,71,42,255))
cs=sorted(set(back.get_flattened_data())-{(0,0,0,0)});ix={c:i for i,c in enumerate(cs)};frames=[]
for i in range(14):
 vals=list(back.crop(((i%7)*64,(i//7)*64,(i%7+1)*64,(i//7+1)*64)).get_flattened_data());frames.append({'ms':1000,'rows':[[ix.get(c,-1) if c[3] else -1 for c in vals[y*64:(y+1)*64]] for y in range(64)]})
(ROOT/'forest-back-row.json').write_text(json.dumps({'name':'forest-back-row','w':64,'h':64,'palette':['#%02x%02x%02x'%c[:3] for c in cs],'frames':frames,'notes':'Fourteen spatial panels in 7x2 grid. Dense deeper forest behind full wall and recessed tree arc.'},separators=(',',':'))+'\n')
# Unified ground shadow, two rows of seven 64px spatial panels. No hard seam
# between the entrance and shade beneath the surrounding canopy.
shade=Image.new('RGBA',(448,192));d=shade.load()
sand=(183,165,109);dark=(8,16,12)
cs=[tuple(round(sand[i]*(1-n/47)+dark[i]*(n/47)) for i in range(3))+(255,) for n in range(48)]
for y in range(192):
 for x in range(448):
  central=max(0,min(1,(49-abs(x-224))/19));central=central*central*(3-2*central)
  entrance=max(0,min(1,(178-y)/152))*max(0,min(1,(y-40)/12))
  wave=3*math.sin(x/15)+2*math.sin(x/7)
  tip=max(0,min(1,(x-14)/12,(434-x)/12))
  under=max(0,1-abs(y-152+wave)/23)*.72*tip
  a=central*entrance*.97+(1-central)*under
  if a<.015:continue
  n=a*47;lo=int(n)
  threshold=((0,8,2,10),(12,4,14,6),(3,11,1,9),(15,7,13,5))[y%4][x%4]/16
  level=min(47,lo+(1 if threshold<n-lo else 0))
  d[x,y]=cs[level]
ix={c:i for i,c in enumerate(cs)};frames=[]
for row in range(3):
 for col in range(7):
  vals=list(shade.crop((col*64,row*64,(col+1)*64,(row+1)*64)).get_flattened_data());frames.append({'ms':1000,'rows':[[ix.get(c,-1) if c[3] else -1 for c in vals[y*64:(y+1)*64]] for y in range(64)]})
(ROOT/'forest-unified-shadow.json').write_text(json.dumps({'name':'forest-unified-shadow','w':64,'h':64,'palette':['#%02x%02x%02x'%c[:3] for c in cs],'frames':frames,'notes':'Three rows of seven spatial panels, blends entrance gradient and canopy shade.'},separators=(',',':'))+'\n')
