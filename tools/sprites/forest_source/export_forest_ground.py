"""Unpack the normal SpriteU PNG sheet and preserve its shade as opacity.
Usage: python tools/export_forest_ground.py VIEWER_SHEET OUTPUT_PNG
SpriteU RGB encodes blend weight against preview sand. Convert that exact
weight to dark translucent pixels so the live terrain texture is preserved.
"""
import sys
from PIL import Image
src=Image.open(sys.argv[1]).convert('RGBA');out=Image.new('RGBA',(448,192))
for row in range(3):out.alpha_composite(src.crop((row*448,0,(row+1)*448,64)),(0,row*64))
p=out.load()
for y in range(128):
 for x in range(448):
  r,g,b,a=p[x,y]
  if a:p[x,y]=(8,16,12,round(255*max(0,min(1,(183-r)/175))))
out.save(sys.argv[2])
