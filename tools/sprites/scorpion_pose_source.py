from PIL import Image,ImageDraw
import math
P={'o': '#171a24', 'd': '#282d3d', 's': '#3d4659', 'm': '#566378', 'l': '#7c8a9b', 'h': '#aab2bc', 'b': '#372212', 'e': '#e0ac71'}
ANGLES=[0,45,90,135,180,225,270,315]
def draw(di,anim,k,n,burrow=None):
 im=Image.new('RGBA',(64,64));d=ImageDraw.Draw(im);a=math.radians(ANGLES[di]);si=math.sin(a);co=math.cos(a)
 phase=k/n*2*math.pi;walk=anim in ('walk','emerge');dead=(k/(n-1) if anim=='death' else 0);hurt=anim=='hurt'
 strike=([0,.18,1,.32,0][k] if anim=='attack' else 0)
 snap=([0,.1,1,.5,0][k] if anim=='pincer' else 0)
 bob=(1 if k in [1,2] else 0) if anim=='idle' else 0
 def pt(x,f,z=0):
  f+=strike*2-(1 if hurt and k==0 else 0)
  return (round(32+x*co+f*si+(0 if burrow is None else [0,-1,1,-1,1,0][burrow])),round(41+(-x*si+f*co)*.66-z*(1-.76*dead)+bob+dead*2))
 def line(points,c,w):d.line([pt(*v) for v in points],fill=P[c],width=w)
 def tube(points,w=3):
  line(points,'o',w+2);line(points,'s',w)
  pix=[(x-1,y-1) for x,y in [pt(*v) for v in points]];d.line(pix,fill=P['l'],width=1)
 def shell(x,f,z,rx,rf,rz):
  cx,cy=pt(x,f,z);rx2=math.sqrt((rx*co)**2+(rf*si)**2);ry2=math.sqrt((rx*si*.66)**2+(rf*co*.66)**2+rz**2)
  rx2=max(1,rx2);ry2=max(1,ry2)
  for yy in range(math.floor(cy-ry2),math.ceil(cy+ry2)+1):
   for xx in range(math.floor(cx-rx2),math.ceil(cx+rx2)+1):
    q=((xx-cx)/rx2)**2+((yy-cy)/ry2)**2
    if q<=1:
     shade='o' if q>.79 else ('d' if (xx-cx)/rx2+(yy-cy)/ry2>.48 else 's' if q>.5 else 'm')
     if q<.55 and xx<cx and yy<cy:shade='l'
     if q<.19 and xx<cx-1 and yy<cy-1:shade='h'
     d.point((xx,yy),fill=P[shade])
 # Four articulated walking legs each side, alternating gait.
 for side in [-1,1]:
  for j in range(4):
   f=5-j*4;g=math.sin(phase+j*math.pi/1.5+side*math.pi/2)*1.9 if walk else 0
   fold=dead*4
   tube([(side*4,f,2),(side*(10-fold*.3),f+4-j*2+g,2),(side*(16-fold),f+7-j*4+g,0)],2)
 # Abdomen, then overlapping dorsal plates.
 shell(0,-3,3,7.5,10,3)
 for f in [-9,-6,-3,0]:shell(0,f,5,6.4-abs(f+2)*.12,2.4,2)
 shell(0,5,4,6.4,4.3,3)
 # Pedipalps: bent arms, heavy palms and two visibly separate pointed fingers.
 for side in [-1,1]:
  spread=(1.2 if anim=='idle' and k==2 else 0)-strike*2-snap*3
  x=side*(12+spread-dead*3);f=13+strike*4+snap*3
  if anim=='pincer' and k in [0,1]:
   f-=4
   x-=side*2
  tube([(side*4,6,3),(side*9,8,3),(x,f,3)],3)
  shell(x,f+1,3,4,4.5,2.6)
  # Fingers converge during sting strike, remain open at rest.
  op=2.4*(1-strike*.6)*(1-dead*.7)
  if anim=='pincer':op=([3.2,4.3,-.5,.1,2.4][k])
  tube([(x-side*2,f+2,3),(x-side*(2+op),f+6,3),(x-side*.8,f+8,3)],2)
  tube([(x+side*2,f+2,3),(x+side*(1+op),f+6,3),(x+side*.8,f+8,3)],2)
 # Eyes remain on the head surface; rear view has subdued eyes.
 if di not in [3,4,5]:
  for side in [-1,1]:
   q=pt(side*2.3,7.7,6);d.point(q,fill=P['o']);d.point((q[0],q[1]-1),fill=P['e'])
 # Raised tail, with separately shaded armored segments, bending into a sting.
 sway=(math.sin(phase)*.6 if anim=='idle' else math.sin(phase)*.8 if walk else 0)
 tail=[(0,-11,4),(1,-15,7),(2,-17,12),(4,-16,18),(7,-12,23),(8+sway,-7+strike*6,25-strike*7),(7+sway,-3+strike*12,23-strike*11)]
 if burrow is not None:
  sway=[0,-1.8,1.8,-1.2,.5,0][burrow]
  tail=[(x+sway*j/6,f,z) for j,(x,f,z) in enumerate(tail)]
 if strike:
  # Extended overhead whip: stinger ends at local forward27, ground height0.
  target=[(0,-11,4),(0,-12,9),(0,-8,17),(0,1,21),(0,11,18),(0,20,11),(0,22,5)]
  tail=[tuple(u+(v-u)*strike for u,v in zip(p,q)) for p,q in zip(tail,target)]
 if dead:tail=[(x+dead*7*j/6,f-dead*3*j/6,z) for j,(x,f,z) in enumerate(tail)]
 for j in range(len(tail)-1):
  tube([tail[j],tail[j+1]],4)
  x,f,z=tail[j+1];shell(x,f,z,3.1-j*.12,3.1-j*.13,2.7-j*.1)
 x,f,z=tail[-1];q=[pt(x-1.8,f,z),pt(x+2,f+1,z),pt(x,f+5,z-5)]
 d.polygon(q,fill=P['o']);d.line(q[:2],fill=P['h'],width=1)
 if anim=='attack' and k==2:
  # Ground contact mark sits at exactly the stinger endpoint (f+5,z-5).
  tube([(-3,27,0),(0,27,0),(3,27,0)],1)
  for xx,ff in [(-4,25),(4,25),(-4,27),(4,27)]:
   px,py=pt(xx,ff,0);d.rectangle((px,py-1,px+1,py),fill=P['e'])
 if hurt and k==0:
  # Only shell highlights flash, no detached hit-spark fragments.
  pix=im.load()
  for yy in range(64):
   for xx in range(64):
    if pix[xx,yy][:3] in [tuple(bytes.fromhex(P[t][1:])) for t in ['m','l','h']]:pix[xx,yy]=(*bytes.fromhex(P['h'][1:]),255)
 return im
