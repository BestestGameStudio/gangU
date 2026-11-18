"""Export only the existing rig's last-drawn stinger barb pixels as a tint mask.
No new character art or color inference. Two attack load-up poses x8 directions.
The rig draws these visible semantic parts last, so no hidden-body pixels leak.
"""
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[2]
s=(root/'tools/sprites/large_scorpion/large_scorpion_rig.py').read_text()
s=s.replace(' x,f,z=tail[-1];q=', " im=Image.new('RGBA',(128,128));d=ImageDraw.Draw(im)\n x,f,z=tail[-1];q=")
ns={};exec(s,ns)
atlas=Image.new('RGBA',(1024,256))
for di in range(8):
 for frame in range(2):
  mask=ns['draw'](di,'attack',frame,5)
  alpha=mask.getchannel('A');white=Image.new('RGBA',mask.size,'white');white.putalpha(alpha)
  atlas.paste(white,(di*128,frame*128))
atlas.save(root/'assets/sprites/scorpion_tail_mask.png')
