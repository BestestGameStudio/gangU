from pathlib import Path
from PIL import Image,ImageDraw
import math,json
import large_scorpion_rig as rig
P=rig.P
P.update({'u':'#947548','v':'#ba9e6f','w':'#d9bd83','t':'#eed79f'})
draw=rig.draw
DIRS=['s','se','e','ne','n','nw','w','sw']
SETS={'idle':[200]*4,'walk':[85]*5,'attack':[180,180,60,180,180],'hurt':[90]*3,'death':[130]*5,'pincer':[100,420,60,160,160],'emerge':[50]*6,'bury':[50]*6}
def transition(di,k,bury=False):
 phase=5-k if bury else k
 if phase==5:return draw(di,'idle',0,4)
 im=Image.new('RGBA',(128,128));d=ImageDraw.Draw(im)
 def ell(cx,cy,rx,ry,c):d.ellipse((cx-rx,cy-ry,cx+rx,cy+ry),fill=P[c])
 if phase==0:
  ell(64,98,39,9,'u');ell(64,95,36,8,'v');ell(62,92,30,5,'w');ell(59,90,19,2,'t');return im
 body=draw(di,'burrow',phase,6);drop=[0,24,13,4,0][phase];cut=[0,90,97,109,124][phase]
 if phase<4:ell(64,100,39-phase,8,'u');ell(64,97,37-phase,6,'v')
 im.alpha_composite(body,(0,drop));d=ImageDraw.Draw(im);d.rectangle((0,cut+1,127,127),fill=(0,0,0,0))
 if phase<3:ell(64,cut+3,37,5,'v');ell(64,cut,34,3,'w')
 if bury:
  for j,x in enumerate([43,55,72,84]):
   y=70+k*5+j%2;d.rectangle((x,y,x+1,y+2),fill=P['t']);d.point((x+2,y+4),fill=P['v'])
 else:
  for j,x in enumerate([53,60,69,76]):
   y=70+drop
   if phase<3:
    for dx in range(-2,3):
     for dy in range(2):
      if im.getpixel((x+dx,y+dy))[3]:d.point((x+dx,y+dy),fill=P['t' if dy==0 else 'w'])
   else:
    x+=(-1 if j<2 else 1)*(phase-2)*5;y+=5+(phase-3)*12
    d.rectangle((x,y,x+1,y+3),fill=P['w']);d.point((x+2,y+5),fill=P['v'])
 # More sand sheds from several shell points and falls vertically.
 a=math.radians(di*45);co=math.cos(a);si=math.sin(a)
 for j in range(18):
  ax=((j*7)%17)-8;af=((j*11)%19)-9
  px=64+(ax*co+af*si)*1.8
  py=84+(-ax*si+af*co)*.66*1.8+drop-9
  shed=k-1 if bury else phase-1
  drift=shed*(1.2 if j%2 else -1.2)
  fall=shed**2*2.4+(j%4)*2
  x=round(px+drift);y=round(py+fall)
  if 3<x<124 and 5<y<cut and phase<5:
   d.rectangle((x,y,x+(j%3==0),y+1+(phase>2)),fill=P['t' if j%4==0 else 'w'])
   if phase>2 and j%2==0:d.point((x,y-3),fill=P['v'])
 return im

if __name__=='__main__':
 out=Path(__file__).resolve().parent/'transition-frames';out.mkdir(exist_ok=True)
 for action in ['emerge','bury']:
  for di,d in enumerate(DIRS):
   for k in range(6):transition(di,k,action=='bury').save(out/f'{action}_{d}_{k}.png')
 print(out)
