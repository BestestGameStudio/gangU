extends SceneTree
## #836: exact query reuse must preserve paths and every steering decision.
class ReferencePath extends TerrainPath:
 func _find_path(map: TerrainMap, from: Vector2, to: Vector2, swim: bool = false) -> Array[Vector2i]:
  return _find_path_uncached(map,from,to,swim)
 func _passable(map: TerrainMap, cell: Vector2i, swim: bool) -> bool:
  return not map.trunk_nav_blocked(cell) and map.can_enter_cell(cell,swim)
 func _hard_obstacle(map: TerrainMap, cell: Vector2i) -> bool:
  return map.trunk_nav_blocked(cell) or map.is_hard_obstacle_cell(cell)
var failed:=0
var checks:=0
func _initialize():run.call_deferred()
func check(value:bool,label:String):
 checks+=1
 if not value:failed+=1;push_error(label)
func new_map()->TerrainMap:
 var map:=TerrainMap.new();map.art_enabled=false;map.hide();root.add_child(map);return map
func run():
 var rng:=RandomNumberGenerator.new();rng.seed=836
 var map:=new_map();var other:=new_map()
 var candidate:=TerrainPath.new();var reference:=ReferencePath.new()
 var types:Array[StringName]=[TerrainTypes.OBSTACLE,TerrainTypes.WATER,TerrainTypes.TREE,TerrainTypes.MUD,TerrainTypes.TALL_GRASS]
 for world in 5:
  var cells:Dictionary={}
  for x in range(-10,18):
   for y in range(-10,18):
    if rng.randf()<0.22:cells[Vector2i(x,y)]=types[rng.randi()%types.size()]
  map.set_cells(cells)
  for sample in 30:
   var a:=Vector2(rng.randf_range(-8,16),rng.randf_range(-8,16))*map.cell_size
   var b:=Vector2(rng.randf_range(-8,16),rng.randf_range(-8,16))*map.cell_size
   for swim in [false,true]:
    var want:=reference._find_path(map,a,b,swim)
    var got:=candidate._find_path(map,a,b,swim)
    check(got==want,'path parity')
    var before:=candidate._search_cache_hits
    check(candidate._find_path(map,a,b,swim)==want,'repeat parity')
    check(candidate._search_cache_hits==before+1,'repeat hits exact-search cache')
    got.clear()
    check(candidate._find_path(map,a,b,swim)==want,'returned array cannot poison cache')
  var ca:=TerrainPath.new();var re:=ReferencePath.new()
  var cp:=Vector2(-400,-300);var rp:=cp;var cv:=Vector2.ZERO;var rv:=cv
  for step in 240:
   if step%40==0:map.set_cell(Vector2i(step/40,2),types[(step/40)%types.size()])
   if step==80:map.set_trunk_blockers([Rect2(-100,-100,80,240)])
   if step==160:map.set_trunk_blockers([])
   var target:=Vector2(650+sin(step*0.01)*200,550)
   var want:=(target-rp).normalized()*110.0
   cv=ca.steer(map,cp,cv,(target-cp).normalized()*110.0,target,110,1.0/60,world%2==0,world%2!=0)
   rv=re.steer(map,rp,rv,want,target,110,1.0/60,world%2==0,world%2!=0)
   check(cv==rv,'exact per-step velocity')
   check(ca.plans==re.plans and ca._replan_timer==re._replan_timer,'replan cadence unchanged')
   cp+=cv/60;rp+=rv/60
   check(cp==rp,'exact integrated position')
 # Equal revisions, opposite nav answers at the SAME coordinates.
 var open_map:=new_map();var blocked_map:=new_map()
 open_map.set_cell(Vector2i(1,0),TerrainTypes.GRASS)
 blocked_map.set_cell(Vector2i(1,0),TerrainTypes.OBSTACLE)
 check(open_map.revision==blocked_map.revision,'identity fixture has equal revisions')
 var open_path:=reference._find_path(open_map,Vector2.ZERO,Vector2(160,0))
 var blocked_path:=reference._find_path(blocked_map,Vector2.ZERO,Vector2(160,0))
 check(open_path!=blocked_path,'identity fixture has opposing routes')
 for used in [open_map,blocked_map,open_map,blocked_map]:
  check(candidate._find_path(used,Vector2.ZERO,Vector2(160,0))==reference._find_path(used,Vector2.ZERO,Vector2(160,0)),'map identity at equal revision')
  check(candidate._passable(used,Vector2i(1,0),false)==reference._passable(used,Vector2i(1,0),false),'map identity flags')
 open_map.free();blocked_map.free()
 # Populated palette overrides must change cached movement, then restore it.
 var palette_map:=new_map();palette_map.set_cell(Vector2i(1,0),TerrainTypes.GRASS)
 for movement in [TerrainTypes.Movement.WALKABLE,TerrainTypes.Movement.BLOCKING,TerrainTypes.Movement.FALLING,TerrainTypes.Movement.WALKABLE]:
  var tile:=TerrainTile.new();tile.id=TerrainTypes.GRASS;tile.movement=movement
  var palette:=TerrainPalette.new();palette.tiles=[tile];palette_map.palette=palette
  var walk:bool=movement==TerrainTypes.Movement.WALKABLE
  check(candidate._passable(palette_map,Vector2i(1,0),false)==walk,'populated palette movement flags')
  check(candidate._hard_obstacle(palette_map,Vector2i(1,0))==not walk,'populated palette hard flags')
  check(candidate._find_path(palette_map,Vector2.ZERO,Vector2(160,0))==reference._find_path(palette_map,Vector2.ZERO,Vector2(160,0)),'populated palette path parity')
 palette_map.free()
 # Both navigation-query bits and full paths invalidate on cell/trunk/palette writes.
 for mutation in 4:
  candidate._find_path(other,Vector2.ZERO,Vector2(300,0))
  if mutation==0:other.set_cell(Vector2i(1,0),TerrainTypes.WATER)
  elif mutation==1:other.set_trunk_blockers([Rect2(0,0,128,128)])
  elif mutation==2:other.set_trunk_blockers([])
  else:other.palette=TerrainPalette.new()
  var hits:=candidate._search_cache_hits
  check(candidate._find_path(other,Vector2.ZERO,Vector2(300,0))==reference._find_path(other,Vector2.ZERO,Vector2(300,0)),'mutation parity')
  check(candidate._search_cache_hits==hits,'mutation invalidates search')
 # Bound shared memory even for a stream of never-repeated cell queries.
 for x in TerrainPath._NAV_CACHE_LIMIT+20:candidate._passable(other,Vector2i(x,1000),false)
 check(TerrainPath._nav_cells.size()<=TerrainPath._NAV_CACHE_LIMIT,'bounded navigation cache')
 check(candidate._passable(other,Vector2i(0,0),false)==reference._passable(other,Vector2i(0,0),false),'eviction preserves answers')
 # Weak map references must not extend area lifetime.
 var ephemeral:=TerrainMap.new();candidate._find_path(ephemeral,Vector2.ZERO,Vector2(200,0));ephemeral.free()
 check(candidate._search_map.get_ref()==null,'search cache does not retain map')
 check(TerrainPath._nav_map.get_ref()==null,'navigation cache does not retain map')
 map.free();other.free()
 print('[836] ',checks,' checks; ',failed,' failures')
 quit(0 if failed==0 else 1)
