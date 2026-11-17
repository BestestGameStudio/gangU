extends SceneTree
const TimedPath=preload("res://docs/evidence/path-cost/paired-terrain-path.gd")
var count:=100
func _init():
 if OS.get_cmdline_user_args().size()>0:count=int(OS.get_cmdline_user_args()[0])
func _initialize():run.call_deferred()
func frames(n:int):
 for i in n:await process_frame
func stats(a:Array)->Dictionary:
 a.sort();return {'median_us':(a[499]+a[500])/2.0,'p95_us':a[949],'max_us':a[-1]}
func run():
 Engine.max_fps=120
 var main=load('res://game/core/main.tscn').instantiate();root.add_child(main);current_scene=main
 await frames(3);main.area_loader.enter_overworld();await frames(4)
 var player=main.get_node('Player');player.set_physics_process(false);player.position=Vector2(-8000,-8000)
 load("res://docs/evidence/path-cost/crowd-setup.gd").add_crowd(main.area_loader.current_area,player,count)
 var enemies:Array=[];var sprites:Array=[];var statues:Array=[]
 for n in get_nodes_in_group('enemies'):
  if n is DesertStatue:statues.append(n);n.set_process(false)
  elif n is Enemy:
   enemies.append(n);n.set_physics_process(false)
   for prop in ["_terrain_path","_walk_path","_path"]:
    if prop in n._behavior and n._behavior.get(prop) is TerrainPath:n._behavior.set(prop,TimedPath.new())
   if n.sprite!=null:sprites.append(n.sprite);n.sprite.set_process(false)
 var ref_times:Array=[];var path_times:Array=[];var path_calls:Array=[]
 var body:Array=[];var sprite:Array=[];var statue:Array=[];var empty:Array=[]
 for i in 1040:
  await process_frame
  TimedPath.reference_us=0;TimedPath.elapsed_us=0;TimedPath.calls=0
  var start:=Time.get_ticks_usec()
  for n in enemies:pass
  var a:=Time.get_ticks_usec()
  for n in enemies:n._physics_process(1.0/60.0)
  var b:=Time.get_ticks_usec()
  for n in sprites:n._process(1.0/60.0)
  var c:=Time.get_ticks_usec()
  for n in statues:n._process(1.0/60.0)
  var d:=Time.get_ticks_usec()
  if i>=40:
   ref_times.append(TimedPath.reference_us);path_times.append(TimedPath.elapsed_us);path_calls.append(TimedPath.calls)
   empty.append(a-start);body.append(b-a);sprite.append(c-b);statue.append(d-c)
 var out={'mismatches':TimedPath.mismatches,'reference_steer_us':stats(ref_times),'path_steer_us':stats(path_times),'path_calls':stats(path_calls),'ordinary_enemy_count':enemies.size(),'sprite_count':sprites.size(),'statue_count':statues.size(),'samples':1000,'empty_loop':stats(empty),'all9_physics_callbacks':stats(body),'all9_sprite_callbacks':stats(sprite),'all12_statue_process_callbacks':stats(statue),'arena_state':main.area_loader.current_area.get_node('DesertStatueArena').state,'player_hp':player.hp,'method':'headless manual callback dispatch delta1/60, callbacks auto-disabled,120Hz pacing,40 warmup samples, no render/redraw service time'}
 print(JSON.stringify(out));var f=FileAccess.open('/downloads/path-paired-'+str(count)+'.json',FileAccess.WRITE);f.store_string(JSON.stringify(out,'  '));quit()
