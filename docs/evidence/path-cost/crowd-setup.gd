extends RefCounted
static func add_crowd(area:Node,player:Player,count:int):
 if count<=9:return
 var scenes=['res://game/enemies/enemy.tscn','res://game/enemies/enemy_red_mustache.tscn','res://game/enemies/enemy_fishy.tscn']
 var defs=['res://data/enemies/overworld_migrant.tres','res://data/enemies/red_mustache.tres','res://data/enemies/overworld_fishy.tres']
 var centers=[Vector2(100,0),Vector2(650,2450),Vector2(350,2600)]
 var nums=[40,30,21]
 var terrain:TerrainMap=area.get_node('Terrain')
 for kind in 3:
  for i in nums[kind]:
   var e=load(scenes[kind]).instantiate()
   e.definition=load(defs[kind]);e.terrain=terrain;e.player_path=NodePath('../../Player')
   var at:Vector2=centers[kind]+Vector2((i%8-3.5)*80,(i/8-2)*80)
   var found:=false
   for j in 50:
    var p=at+Vector2(cos(j*2.4),sin(j*2.4))*j*14
    if TerrainMotion.can_enter(terrain,p,e.can_swim):at=p;found=true;break
   assert(found)
   e.position=at;area.add_child(e)
   if kind==0:e._behavior.configure_route(PackedVector2Array([at,at+Vector2(500,0),at+Vector2(500,-450)]))
