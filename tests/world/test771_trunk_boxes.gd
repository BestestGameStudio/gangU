extends SceneTree
var failures := 0
func check(ok: bool, text: String):
 print('[771] ',text,' ',ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 var area:=Node2D.new();root.add_child(area)
 var map:=TerrainMap.new();map.name='Terrain';map.cell_size=32;area.add_child(map)
 var ground:=OverworldGround.new()
 ground.decor=[{'kind':'tree','at':Vector2(128,128),'r':32.0}]
 area.add_child(ground)
 ground.decor=[{'kind':'tree','at':Vector2(128,128),'r':32.0}]
 ground._plant_tree_collision(area)
 var rect:Rect2=map.trunk_blockers()[0]
 check(rect.size.x < 12 and rect.size.y < 11,'small trunk box, not canopy')
 check(map.projectile_blockers().is_empty(),'old canopy circles removed')
 check(map.trunk_contains(rect.get_center()),'trunk centre solid')
 check(not map.trunk_contains(Vector2(128,110)),'canopy area clear')
 var from:=rect.get_center()-Vector2(30,0)
 var to:=rect.get_center()+Vector2(30,0)
 check(map.projectile_block_t(from,to-from)>0,'projectiles stop at trunk')
 check(map.projectile_block_t(from-Vector2(0,20),to-from)<0,'projectiles pass beside canopy')
 check(TerrainMotion.clamp_displacement(map,from,to,false).x < rect.position.x,'blink cannot pass through trunk')
 check(TerrainMotion.clamp_displacement(map,from-Vector2(0,20),to-Vector2(0,20),false).is_equal_approx(to-Vector2(0,20)),'blink passes canopy')
 check(TerrainMotion.resolve(map,from,Vector2.ZERO,Vector2(600,0),0.1,false).x==0,'fast movement cannot skip trunk')
 check(map.trunk_nav_blocked(map.world_to_cell(rect.get_center())),'navigation aware')
 check(not map.tile_type_at(rect.get_center())==TerrainTypes.OBSTACLE,'no full-cell collision replacement')
 area.queue_free();await process_frame
 quit(1 if failures else 0)
