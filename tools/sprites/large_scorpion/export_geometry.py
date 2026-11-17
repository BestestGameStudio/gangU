from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,math
import export_transitions as ex
root=Path(__file__).resolve().parent
s=(root/'large_scorpion_rig.py').read_text()
s=s.replace(' # Seven anatomical links', ' feet=[]\n # Seven anatomical links')
s=s.replace('   radii=[','   feet.append({\'side\':side,\'index_front_to_rear\':j,\'anatomy_xyz\':list(nodes[-1]),\'pixel_xy\':list(pt(*nodes[-1])),\'planted\':lift==0 and dead==0})\n   radii=[')
s=s.replace(' d.polygon(q,fill=P[\'o\'])',' TRACE.update({\'tip_xy\':list(q[2]),\'tip_triangle_xy\':[list(v) for v in q],\'feet\':feet,\'ground_origin_xy\':list(pt(0,0,0))})\n d.polygon(q,fill=(255,0,255,255) if MARK else P[\'o\'])')
ns={'TRACE':{},'MARK':False};exec(s,ns);ns['P'].update(ex.P)
orig=ns['draw']; records=[]
for action,times in ex.SETS.items():
 for di,d in enumerate(ex.DIRS):
  for k,ms in enumerate(times):
   ns['TRACE'].clear();ns['MARK']=True;ex.draw=orig
   im=ex.transition(di,k,action=='bury') if action in ['emerge','bury'] else orig(di,action,k,len(times))
   t=dict(ns['TRACE']);phase=5-k if action=='bury' else k
   transition=action in ['emerge','bury'];hidden=transition and phase==0
   drop=([0,24,13,4,0][phase] if transition and 0<phase<5 else 0)
   if hidden:
    t={'tip_xy':None,'tip_triangle_xy':None,'feet':[],'ground_origin_xy':None}
   else:
    for key in ['tip_xy','ground_origin_xy']:t[key][1]+=drop
    for v in t['tip_triangle_xy']:v[1]+=drop
    for foot in t['feet']:foot['pixel_xy'][1]+=drop
   xy=t['tip_xy'];visible=bool(xy and 0<=xy[0]<128 and 0<=xy[1]<128 and im.getpixel(tuple(xy))==(255,0,255,255))
   count=sum(c==(255,0,255,255) for c in im.getdata())
   t.update({'action':action,'direction':d,'frame_zero_based':k,'ms':ms,'tip_vertex_visible':visible,'visible_stinger_polygon_pixels':count,'occlusion':('body_not_drawn_sand_mound_only' if hidden else 'tip_vertex_visible' if visible else 'tip_vertex_hidden_by_transition_mask_or_sand'),'transition_drop_y':drop})
   t['foot_endpoint_y_range']=([min(f['pixel_xy'][1] for f in t['feet']),max(f['pixel_xy'][1] for f in t['feet'])] if t['feet'] else None)
   records.append(t)
(root/'pose-geometry.json').write_text(json.dumps({'canvas':[128,128],'static_ground_anchor':[64,84],'coordinate_system':'top-left origin; +x right,+y down; integer native pixels; semantic endpoints not collision geometry','poses':records},indent=2)+'\n')
# Directional grounded-sting overlay proof, anchor green, tip magenta and planted foot endpoints cyan.
board=Image.new('RGB',(1024,300),'#202633');bd=ImageDraw.Draw(board);font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',14)
for di,d in enumerate(ex.DIRS):
 ns['MARK']=False;im=orig(di,'attack',2,5);rec=next(r for r in records if r['action']=='attack' and r['direction']==d and r['frame_zero_based']==2)
 ox=di%4*256;oy=30+di//4*135
 board.paste(im,(ox,oy),im)
 for f in rec['feet']:
  x,y=f['pixel_xy'];bd.rectangle((ox+x-1,oy+y-1,ox+x+1,oy+y+1),fill='#00ffff')
 x,y=rec['tip_xy'];bd.ellipse((ox+x-2,oy+y-2,ox+x+2,oy+y+2),outline='#ff00ff')
 bd.line((ox+61,oy+84,ox+67,oy+84),fill='#00ff00');bd.text((ox+135,oy+35),d.upper()+str(rec['tip_xy']),font=font,fill='white')
board.save(root/'sting-geometry-check.png')
print('Exported',len(records),'pose geometries')
