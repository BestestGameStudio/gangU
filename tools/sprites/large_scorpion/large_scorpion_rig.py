from PIL import Image,ImageDraw
import math
P={'o': '#171a24', 'd': '#282d3d', 's': '#3d4659', 'm': '#566378', 'l': '#7c8a9b', 'h': '#aab2bc', 'b': '#372212', 'e': '#e0ac71'}
ANGLES=[0,45,90,135,180,225,270,315]
def draw(di,anim,k,n):
 im=Image.new('RGBA',(128,128));d=ImageDraw.Draw(im);a=math.radians(ANGLES[di]);si=math.sin(a);co=math.cos(a)
 phase=k/n*2*math.pi;walk=anim=='walk';dead=(k/(n-1) if anim=='death' else 0);hurt=anim=='hurt'
 strike=([0,.18,1,.32,0][k] if anim=='attack' else 0)
 snap=([0,.1,1,.5,0][k] if anim=='pincer' else 0)
 bob=(1 if k in [1,2] else 0) if anim=='idle' else 0
 def pt(x,f,z=0):
  f+=strike*2-(1 if hurt and k==0 else 0)+([-0.4,-2,0.5,0.2,0][k] if anim=='pincer' else 0)
  return (round(64+(x*co+f*si)*1.8+(math.sin(phase*3)*1.5 if anim=='burrow' else 0)),round(84+((-x*si+f*co)*.66-z*(1-.76*dead)+bob+dead*2)*1.8))
 def line(points,c,w):d.line([pt(*v) for v in points],fill=P[c],width=round(w*1.8))
 def tube(points,w=3):
  line(points,'o',w+2);line(points,'s',w)
  pix=[(x-1,y-1) for x,y in [pt(*v) for v in points]];d.line(pix,fill=P['l'],width=1)
 def curve(points,r0,r1):
  # Quadratic curve in anatomy space, tapering to a fine tip.
  samples=[]
  for i in range(33):
   t=i/32
   q=tuple((1-t)**2*points[0][j]+2*(1-t)*t*points[1][j]+t*t*points[2][j] for j in range(3))
   samples.append((pt(*q),r0+(r1-r0)*t))
  for (cx,cy),r in samples:
   rr=max(.5,r+1)
   d.ellipse((round(cx-rr),round(cy-rr),round(cx+rr),round(cy+rr)),fill=P['o'])
  for (cx,cy),r in samples:
   r=max(.35,r)
   d.ellipse((round(cx-r),round(cy-r),round(cx+r),round(cy+r)),fill=P['d'])
  # Narrow upper-left light catches, no fat angular banding.
  for (cx,cy),r in samples[::2]:
   d.point((round(cx-r*.4),round(cy-r*.5)),fill=P['s'])
 def shell(x,f,z,rx,rf,rz):
  cx,cy=pt(x,f,z);rx2=math.sqrt((rx*co)**2+(rf*si)**2);ry2=math.sqrt((rx*si*.66)**2+(rf*co*.66)**2+rz**2)
  rx2=max(1,rx2*1.8);ry2=max(1,ry2*1.8)
  for yy in range(math.floor(cy-ry2),math.ceil(cy+ry2)+1):
   for xx in range(math.floor(cx-rx2),math.ceil(cx+rx2)+1):
    q=((xx-cx)/rx2)**2+((yy-cy)/ry2)**2
    if q<=1:
     shade='o' if q>.79 else ('d' if (xx-cx)/rx2+(yy-cy)/ry2>.48 else 's' if q>.5 else 'm')
     if q<.55 and xx<cx and yy<cy:shade='l'
     if q<.19 and xx<cx-1 and yy<cy-1:shade='h'
     d.point((xx,yy),fill=P[shade])
 # Seven anatomical links per walking leg. Proximal two tuck under shell.
 for side in [-1,1]:
  for j in range(4):
   f=5-j*4;g=math.sin(phase+j*math.pi/1.5+side*math.pi/2)*1.9 if walk else math.sin(phase+j+side)*1.6 if anim=='burrow' else 0
   sweep=5-j*3.4
   lift=max(0,math.sin(phase+j*math.pi/1.5+side*math.pi/2))*1.6 if walk else 0
   nodes=[(side*4,f,2.4),(side*5.4,f+.3,2.6),
          (side*7.1,f+.7,2.8),(side*11.2,f+sweep*.45,5.4),
          (side*13,f+sweep*.7,5.2),(side*(16.3-dead*3),f+sweep+g,1.9+lift),
          (side*(18-dead*5),f+sweep*1.15+g,.6+lift),(side*(19.5-dead*6),f+sweep*1.2+g,lift)]
   radii=[2.3,2.1,1.9,1.65,1.45,.95,.55,.15]
   # Individual tapered links create a bent silhouette, not a smooth hose.
   for h in range(7):
    p,q=nodes[h:h+2];mid=tuple((v+w)/2 for v,w in zip(p,q))
    curve([p,mid,q],radii[h],radii[h+1])
   # Dark articulated pivots plus one restrained rim pixel, away from shell.
   for h in range(3,7):
    x,y=pt(*nodes[h]);r=1.15 if h<5 else .65
    d.ellipse((round(x-r),round(y-r),round(x+r),round(y+r)),fill=P['o'])
    d.point((x,y-1),fill=P['s'])
 def draw_pincers():
  # Pedipalps: bent arms, heavy palms and two visibly separate pointed fingers.
  for side in [-1,1]:
   spread=(1.2 if anim=='idle' and k==2 else 0)-strike*2-snap*3
   x=side*((12 if di==0 else 10.5)+spread-dead*3);f=(13 if di==0 else 18)+strike*1+snap*3
   if anim=='pincer' and k in [0,1]:
    f-=[3,8][k]
    x+=side*[0.5,1.5][k]
   if di==0:
    curve([(side*4,6,3),(side*11,7,4),(x,f,3)],3.3,2.4)
   else:
    # Root at head end, short outward upper arm, bent elbow, forward forearm.
    curve([(side*3,7.2,2.4),(side*6,9,2.7),(side*9,11,3)],2.4,2.0)
    curve([(side*9,11,3),(side*12,14,3),(x,f,3)],2.0,2.4)
   shell(x,f+1,3,3.2,4.8,2.3)
   # Fingers converge during sting strike, remain open at rest.
   op=2.4*(1-strike*.6)*(1-dead*.7)
   if anim=='pincer':op=([3.4,5.6,-.65,-.3,2.4][k])
   curve([(x-side*2,f+2,3),(x-side*(4+op),f+8,3),(x-side*.6,f+12,3)],2.4,.15)
   curve([(x+side*2,f+2,3),(x+side*(3+op),f+9,3),(x+side*1.2,f+11.5,3)],2.1,.15)
  # Palm decoration only stays on unchanged S pose.
  if di==0:
   for side in (-1,1):
    x=side*12
    line([(x-side*2,12,5),(x,15,5),(x+side*2,14,4)],'d',.6)
 
 if di!=0:draw_pincers()
 sway=(math.sin(phase)*.6 if anim=='idle' else math.sin(phase)*.8 if walk else math.sin(phase)*1.8 if anim=='burrow' else 0)
 tail=[(0,-11,4),(1,-15,7),(2,-17,12),(4,-16,18),(7,-12,23),(8+sway,-7+strike*6,25-strike*7),(7+sway,-3+strike*12,23-strike*11)]
 if strike:
  # Extended overhead whip: stinger ends at local forward27, ground height0.
  target=[(0,-11,4),(0,-12,9),(0,-8,17),(0,1,21),(0,11,18),(0,20,11),(0,22,5)]
  tail=[tuple(u+(v-u)*strike for u,v in zip(p,q)) for p,q in zip(tail,target)]
 if dead:tail=[(x+dead*7*j/6,f-dead*3*j/6,z) for j,(x,f,z) in enumerate(tail)]
 # Rear underbody attachment is drawn first, beneath the shell rim.
 tube(([(0,-8,1.4),(0,-12,2.2),(1,-15,5.5),(2,-17,12)] if not strike else [(0,-8,1.4),tail[0],tail[1],tail[2]]),3.2)
 shell(1,-15,5.5,2.5,2.9,2.1)
 # Unified carapace silhouette covers all crowded limb roots.
 # Dark outer silhouette and lit upper shell separate it from recessed legs.
 shell(0,-3,4.5,7.4,10.3,2.6)
 # Three broad plates, not a thicket of narrow ribs or floating rivets.
 for f in [-7,-1,4]:
  shell(0,f,6,6.4 if f<4 else 5.9,3.7 if f<4 else 4.0,1.9)
 # Short inset seams stay well inside the carapace outline.
 for f in [-4,2]:
  line([(-4,f,8),(0,f+.6,8.3),(4,f,8)],'d',.6)
 if di==0:draw_pincers()
 # Eyes remain on the head surface; rear view has subdued eyes.

 if di not in [3,4,5]:
  for side in [-1,1]:
   q=pt(side*2.3,7.7,6);d.point(q,fill=P['o']);d.point((q[0],q[1]-1),fill=P['e'])
 # Raised tail, with separately shaded armored segments, bending into a sting.
 for j in range(2,len(tail)-1):
  tube([tail[j],tail[j+1]],4)
  x,f,z=tail[j+1];shell(x,f,z,3.1-j*.12,3.1-j*.13,2.7-j*.1)
 x,f,z=tail[-1];q=[pt(x-1.8,f,z),pt(x+2,f+1,z),pt(x,f+5,z-5)]
 d.polygon(q,fill=P['o']);d.line(q[:2],fill=P['h'],width=1)
 if hurt and k==0:
  # Only shell highlights flash, no detached hit-spark fragments.
  pix=im.load()
  for yy in range(128):
   for xx in range(128):
    if pix[xx,yy][:3] in [tuple(bytes.fromhex(P[t][1:])) for t in ['m','l','h']]:pix[xx,yy]=(*bytes.fromhex(P['h'][1:]),255)
 return im
