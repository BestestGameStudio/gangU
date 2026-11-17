"""SpriteU source generator: original slate scorpion rig, new burrow transitions.
Six keyframes x 50ms; original animation content and atlas rows remain unchanged.
"""
import copy,json,math
from pathlib import Path
from scorpion_pose_source import draw
ROOT=Path(__file__).resolve().parents[2]
PATH=ROOT/'tools/sprites/specs/scorpion.spriteu.json'
src=json.loads(PATH.read_text())
src['palette'].update({'u':'#947548','v':'#BA9E6F','w':'#D9BD83','x':'#EED79F'})
rev={tuple(bytes.fromhex(v[1:])):k for k,v in src['palette'].items()}

def ellipse(g,cx,cy,rx,ry,c):
 for y in range(max(1,cy-ry),min(63,cy+ry+1)):
  for x in range(max(1,cx-rx),min(63,cx+rx+1)):
   if ((x-cx)/max(rx,1))**2+((y-cy)/max(ry,1))**2<=1:g[y][x]=c

def pixel(g,x,y,c):
 if 1<=x<63 and 1<=y<63:g[y][x]=c

def frame(di,body,phase,bury=False):
 if phase==5:return copy.deepcopy(body)
 g=[['.']*64 for _ in range(64)]
 if phase==0:
  ellipse(g,32,46,23,6,'u');ellipse(g,32,44,21,6,'v')
  ellipse(g,32,42,18,5,'w');ellipse(g,29,40,12,2,'x')
  for x,y in [(26,40),(27,41),(28,42),(29,43),(35,43),(36,42),(37,41)]:pixel(g,x,y,'v')
  return [''.join(r) for r in g]
 # Original posable anatomy, with alternating legs, body shake and real tail sway.
 im=draw(di,'emerge',phase,6,burrow=phase)
 rows=[['.' if im.getpixel((x,y))[3]==0 else rev[im.getpixel((x,y))[:3]] for x in range(64)] for y in range(64)]
 drop=[0,13,7,2,0][phase]
 cutoff=[0,44,47,52,61][phase]
 if phase<4:
  ellipse(g,32,47,23-phase,5,'u');ellipse(g,32,46,22-phase,4,'v')
 for y,row in enumerate(rows):
  for x,c in enumerate(row):
   yy=y+drop
   if c!='.' and yy<=cutoff and yy<63:g[yy][x]=c
 if phase<3:
  ellipse(g,32,cutoff+2,22,3,'v');ellipse(g,32,cutoff,20,2,'w')
 if bury:
  # New debris falls down while the body descends. Never reverse particle motion.
  progress=5-phase
  for j,x in enumerate((21,27,37,44)):
   y=34+progress*3+j%2
   pixel(g,x,y,'x');pixel(g,x,y+1,'w');pixel(g,x+(-1 if j<2 else 1),y+3,'v')
  return [''.join(r) for r in g]
 # Sand clings to the dorsal plates, then slides down the sides in chunky streaks.
 # World-space back projects near (32,38), independent of direction.
 for j,anchor in enumerate(((-5,35),(-1,36),(4,35),(7,38))):
  x,y=anchor[0]+32,anchor[1]
  if phase<3:
   yy=y+drop
   for dx in range(-2,3):
    for dy in (0,1):
     if 0<=yy+dy<64 and g[yy+dy][x+dx] not in ('.','u','v','w','x'):
      g[yy+dy][x+dx]='x' if dy==0 else 'w'
  elif phase==3:
   # Sliding dorsal clumps still rest on the back at this pose.
   for dx in (-1,0,1):
    for dy in (0,1):
     pixel(g,x+dx,y+dy+1,'x' if dy==0 else 'w')
   side=-1 if j<2 else 1
   x+=side*4;y+=5+j%2
   for dy in range(3):pixel(g,x,y+dy,'w' if dy else 'x')
   pixel(g,x+side,y+3,'v')
  else:
   side=-1 if j<2 else 1
   x+=side*8;y+=13+j%2
   pixel(g,x,y,'x');pixel(g,x,y+1,'w');pixel(g,x+side,y+3,'v')
 for x,y,c in [(11,44,'w'),(15,50,'v'),(52,43,'x'),(49,52,'w')]:
  pixel(g,x,y+(phase-2),'w' if phase==3 else c)
 return [''.join(r) for r in g]

if src.get('name') == 'large-scorpion-animated-study':
 raise SystemExit('Legacy64px generator: use large_scorpion/generate_source.py for the approved128px model.')

for di,d in enumerate(('s','se','e','ne','n','nw','w','sw')):
 body=src['animations']['idle_'+d]['frames'][0]['rows']
 frames=[{'ms':50,'rows':frame(di,body,i)} for i in range(6)]
 src['animations']['emerge_'+d]={'frames':frames,'loop':False}
 src['animations']['bury_'+d]={'frames':[{'ms':50,'rows':frame(di,body,i,bury=True)} for i in range(5,-1,-1)],'loop':False}
PATH.write_text(json.dumps(src,separators=(',',':'))+'\n')
print('Six frames x 50ms = 300ms each, eight directions. Original frames untouched.')
