extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print('[799] ',label,': ',ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 var area:=Node2D.new();root.add_child(area);current_scene=area
 var player:=load('res://game/player/player.tscn').instantiate() as Player
 area.add_child(player);player.set_physics_process(false);player.global_position=Vector2(300,300)
 var enemy_scene=load('res://game/enemies/enemy.tscn')
 var tiers=['hook_shot','hook_shot_magnet','hook_shot_catch']
 if ResourceLoader.exists('res://data/spells/hook_shot_rock.tres'):tiers.append('hook_shot_rock')
 for id in tiers:
  var spell=load('res://data/spells/%s.tres'%id) as Spell
  var enemy=enemy_scene.instantiate() as Enemy;area.add_child(enemy);enemy.set_physics_process(false)
  enemy.global_position=player.global_position+Vector2(100,0);enemy.velocity=Vector2(0,900)
  var reel=HookReel.begin(area,enemy,player,spell);reel.set_physics_process(false);reel.reel_velocity=Vector2(0,1500)
  for tick in 30:
   reel._physics_process(1.0/30.0)
   check(absf(enemy.global_position.y-300)<0.01,'no lateral swing '+id)
   if reel.arrived:break
  check(reel.arrived and is_equal_approx(enemy.global_position.distance_to(player.global_position),32.0),'stops at 32px '+id)
  check(enemy.velocity==Vector2.ZERO and reel.reel_velocity==Vector2.ZERO,'arrival kills both momenta '+id)
  enemy.queue_free();await process_frame
 for id in tiers.slice(1):
  var spell=load('res://data/spells/%s.tres'%id) as Spell
  var enemies:Array[Enemy]=[]
  for index in 3:
   var enemy=enemy_scene.instantiate() as Enemy;area.add_child(enemy);enemy.set_physics_process(false)
   enemy.global_position=player.global_position+Vector2(120+index*12,index*8-8);enemy.velocity=Vector2(0,900);enemies.append(enemy)
  var group=HookGroupReel.begin(area,enemies,player,spell);group.set_physics_process(false);group.reel_velocity=Vector2(0,1500)
  for tick in 60:
   group._physics_process(1.0/30.0)
   if group.is_queued_for_deletion():break
  check(group.is_queued_for_deletion(),'group completes without orbit '+id)
  check(group.reel_velocity==Vector2.ZERO and enemies.all(func(e):return e.velocity==Vector2.ZERO),'group cancels momentum '+id)
  check(enemies.all(func(e):return e.global_position.distance_to(player.global_position)<=32.01 and e.global_position.x>=player.global_position.x),'whole group stops near side of player '+id)
  for enemy in enemies:enemy.queue_free()
  await process_frame
 check(HookReel.stop_at_contact(Vector2(100,0),Vector2(-200,0),Vector2.ZERO,24).is_equal_approx(Vector2(-76,0)),'swept contact prevents long-step crossing')
 area.queue_free();await process_frame;quit(1 if failures else 0)
