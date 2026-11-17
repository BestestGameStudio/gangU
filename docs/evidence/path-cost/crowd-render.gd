extends SceneTree
var results: Array=[]
var section := "gate"
var count:=100
func _initialize():
 if OS.get_cmdline_user_args().size()>0: section=OS.get_cmdline_user_args()[0]
 if OS.get_cmdline_user_args().size()>1:count=int(OS.get_cmdline_user_args()[1])
 run.call_deferred()
func frames(n:int):
 for i in n: await process_frame
func sample(label:String):
 await frames(3)
 var wall:Array=[];var cpu:Array=[];var physics:Array=[];var calls:Array=[]
 var previous:=Time.get_ticks_usec()
 for i in 18:
  await process_frame
  var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
  cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
  physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
  calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
 wall.sort();cpu.sort();physics.sort();calls.sort()
 var row={"section":section,"label":label,"wall_median_ms":(wall[8]+wall[9])/2,"wall_min_ms":wall[0],"wall_max_ms":wall[-1],"process_median_ms":(cpu[8]+cpu[9])/2,"physics_median_ms":(physics[8]+physics[9])/2,"draw_calls":calls[9]}
 results.append(row);print(JSON.stringify(row))
 var f=FileAccess.open('/downloads/crowd-'+str(count)+'-'+section+'.json',FileAccess.WRITE);f.store_string(JSON.stringify(results,'  '))
func run():
 root.size=Vector2i(1152,648)
 var main=load('res://game/core/main.tscn').instantiate();root.add_child(main);current_scene=main
 await frames(3);main.area_loader.enter_overworld();await frames(4)
 var player=main.get_node('Player');player.set_physics_process(false);player.position=Vector2(-8000,-8000)
 var area=main.area_loader.current_area;var arena=area.get_node('DesertStatueArena')
 var camera=main.get_node('FollowCamera');var focus:=Node2D.new();main.add_child(focus);camera.target=focus;camera.zoom=Vector2.ONE
 focus.position=Vector2(576,480) if section=='gate' else arena.global_position+Vector2(0,500);camera.position=focus.position
 load("res://docs/evidence/path-cost/crowd-setup.gd").add_crowd(area,player,count)
 var enemies:Array=[];var sprites:Array=[];var statues:Array=[]
 for n in get_nodes_in_group('enemies'):
  if n is DesertStatue:statues.append(n)
  elif n is Enemy:
   enemies.append(n)
   if n.sprite!=null:sprites.append(n.sprite)
 print('COUNTS ',JSON.stringify({'enemies':enemies.size(),'sprites':sprites.size(),'statues':statues.size(),'section':section,'arena_state':arena.state,'player':player.position}))
 await frames(4)
 root.get_texture().get_image().save_png('/downloads/crowd-'+str(count)+'-'+section+'.png')
 for repeat in 2:
  await sample(str(repeat)+':baseline')
  for n in enemies:n.set_physics_process(false)
  await sample(str(repeat)+':enemy_physics_off')
  for n in enemies:n.set_physics_process(true)
  await sample(str(repeat)+':restored_physics')
  for n in sprites:n.set_process(false)
  await sample(str(repeat)+':sprite_process_off')
  for n in sprites:n.set_process(true)
  await sample(str(repeat)+':restored_sprite')
  for n in sprites:n.hide()
  await sample(str(repeat)+':sprites_hidden')
  for n in sprites:n.show()
  await sample(str(repeat)+':restored_visible')
  var masks:Array=[]
  for n in enemies:
   masks.append([n.collision_layer,n.collision_mask]);n.collision_layer=0;n.collision_mask=0
  await sample(str(repeat)+':collision_masks_zero')
  for i in enemies.size():enemies[i].collision_layer=masks[i][0];enemies[i].collision_mask=masks[i][1]
  await sample(str(repeat)+':restored_collisions')
 print('FINAL ',JSON.stringify({'enemies':enemies.size(),'statues':statues.size(),'arena_state':arena.state,'player_hp':player.hp}))
 quit()
