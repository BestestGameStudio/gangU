"""Original static village prop atlas, #484. No external source art.
4 columns x 128px: three ruined-house variants, one dry well.
Objects are drawn at native pixel resolution and displayed 1:1, nearest.
Run from repo root: python3 tools/sprites/draw_village.py
"""
from PIL import Image, ImageDraw
from pathlib import Path
import random
im=Image.new('RGBA',(512,128));d=ImageDraw.Draw(im)
stone=['#4b4d42','#646452','#797660','#969078'];wood=['#342b27','#59402d','#796044']
for col in range(3):
 x=col*128;r=random.Random(484+col)
 d.ellipse((x+5,90,x+125,119),fill=(15,22,17,90))
 d.rectangle((x+16,37,x+108,101),fill='#282e29')
 # Dark floor planks remain inside the hollow ruin.
 for y in range(43,100,7):
  d.line((x+21,y,x+104,y), fill='#3d3d31',width=2)
 for side in [0,1]:
  for row in range(5):
   yy=48+row*10
   xx=x+(13 if side==0 else 100)
   if col==1 and side==1 and row<2:continue
   d.rectangle((xx,yy,xx+13,yy+9),fill=stone[(row+side+col)%4],outline=stone[0])
 for row in range(2):
  for k in range(6):
   if k in [2,3] and row==1:continue
   xx=x+15+k*15+(row%2)*3
   d.rectangle((xx,91+row*8,xx+14,98+row*8),fill=stone[(k+row)%4],outline=stone[0])
 # Jagged collapsed roof, with overlapping rows of weathered shingles.
 roof=[(x+7,50),(x+57,13),(x+105,39),(x+88,45),(x+83,58),(x+69,48),(x+61,63),(x+45,53),(x+29,64)]
 d.polygon(roof,fill=wood[0])
 mask=Image.new('L',im.size);md=ImageDraw.Draw(mask);md.polygon(roof,fill=255)
 shingles=Image.new('RGBA',im.size);sd=ImageDraw.Draw(shingles)
 for row in range(6):
  for k in range(9):
   xx=x+5+k*13-(row%2)*6;yy=14+row*9
   sd.rectangle((xx,yy,xx+12,yy+8),fill=['#544535','#69523b','#795f40','#8b7050'][(k+row+col)%4],outline='#3a332a')
 im.paste(shingles,(0,0),mask);d=ImageDraw.Draw(im)
 for a,b in [((30,85),(76,52)),((70,96),(101,68))]:
  d.line((x+a[0],a[1],x+b[0],b[1]),fill=wood[0],width=7)
  d.line((x+a[0],a[1]-2,x+b[0],b[1]-2),fill=wood[2],width=2)
 for k in range(14):
  xx=x+r.randrange(8,118);yy=r.randrange(106,120)
  d.rectangle((xx,yy,xx+5,yy+3),fill=stone[k%4])
 for k in range(7):
  xx=x+r.randrange(10,115);yy=r.randrange(100,119)
  d.line((xx,yy,xx+2,yy-5),fill='#596442',width=2)
# Dry stone well, including chipped masonry, timber posts and broken beam.
x=384
d.ellipse((x+24,91,x+106,117),fill=(15,22,17,100))
d.rectangle((x+31,65,x+97,93),fill='#535749')
d.ellipse((x+29,76,x+99,107),fill='#676954',outline='#353f35',width=3)
for k in range(7):
 d.line((x+33+k*10,86,x+33+k*10,103),fill='#3f493e',width=2)
d.ellipse((x+27,56,x+101,89),fill='#939077',outline='#464e42',width=3)
d.ellipse((x+38,63,x+91,80),fill='#101c1c',outline='#5c6657',width=3)
d.rectangle((x+29,26,x+35,74),fill='#5c4732');d.rectangle((x+93,28,x+99,75),fill='#5c4732')
d.polygon([(x+22,22),(x+65,22),(x+59,29),(x+72,32),(x+21,32)],fill='#806245')
d.line((x+48,30,x+48,61),fill='#a18c65',width=2)
d.rectangle((x+44,56,x+53,64),fill='#493d2e')
Path('assets/sprites').mkdir(exist_ok=True)
im.save('assets/sprites/village_props.png')
# Checker preview is local evidence only.
bg=Image.new('RGBA',im.size,'#a0a0a0');bd=ImageDraw.Draw(bg)
for yy in range(0,128,8):
 for xx in range(0,512,8):
  if (xx//8+yy//8)%2:bd.rectangle((xx,yy,xx+7,yy+7),fill='#707070')
bg.alpha_composite(im);bg.resize((1024,256),Image.Resampling.NEAREST).save('/downloads/village/atlas-preview.png')
