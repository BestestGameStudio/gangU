extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String):
 checks+=1;print('[809] ',label,': ',ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 var area:=Node2D.new();root.add_child(area);current_scene=area
 var player=load('res://game/player/player.tscn').instantiate() as Player
 area.add_child(player);player.set_physics_process(false);player.position=Vector2(-1000,-1000)
 var primary=load('res://data/spells/hook_shot_rock.tres') as Spell
 var spell=primary.alternate_spell
 check(spell.hook_lure_recasts==4 and primary.hook_lure_recasts==0,'four recasts only on alternate payload')
 var pair:=HookAnchorPair.place(area,player,spell,Vector2.ZERO,Vector2(300,0));pair.set_physics_process(false)
 var other:=HookAnchorPair.place(area,player,spell,Vector2(0,500),Vector2(300,500));other.set_physics_process(false)
 var enemy=load('res://game/enemies/enemy.tscn').instantiate() as Enemy
 area.add_child(enemy);enemy.set_physics_process(false)
 for cycle in 5:
  enemy.position=pair.lure_cast_position
  pair._physics_process(0.001)
  check(pair.consumed and is_instance_valid(pair.active_reel),'capture cycle '+str(cycle+1))
  var reel:=pair.active_reel;reel.set_physics_process(false)
  enemy.position=Vector2(90,0);pair._physics_process(0.001)
  check(pair.lure.position==enemy.position,'lure follows enemy cycle '+str(cycle+1))
  enemy.position=pair.anchor.global_position
  reel._physics_process(0.001)
  if cycle<4:
   check(pair.returning and not pair.consumed and pair.recasts_used==cycle+1,'arrival starts budgeted return '+str(cycle+1))
   check(not HookPullStack.contains(enemy,reel) and reel.arrived,'arrival releases ownership before return')
   player.position+=Vector2(25,50)
   enemy.position=Vector2(75,0)
   pair._physics_process(0.1)
   check(pair.returning and not pair.consumed and pair.lure.position==Vector2(75,0),'return travels without capturing crossed enemy')
   pair._physics_process(1)
   check(not pair.returning and pair.lure.global_position==Vector2(300,0) and pair.anchor.global_position==Vector2.ZERO,'returns to original lure position, fixed anchor')
   check(other.recasts_used==0,'budget is per pair')
  else:
   check(pair.is_queued_for_deletion() and pair.recasts_used==4,'fifth successful catch exhausts four recasts and removes pair')
  await process_frame
 # A failed reel never grants a return.
 enemy.position=other.lure.global_position;other._physics_process(0.001)
 var timed_out:=other.active_reel;timed_out.set_physics_process(false);timed_out.age=spell.hook_timeout
 timed_out._physics_process(0.001);other._physics_process(0.001)
 check(other.is_queued_for_deletion() and other.recasts_used==0,'timeout removes pair without recast')
 await process_frame
 var dead:=HookAnchorPair.place(area,player,spell,Vector2.ZERO,Vector2(300,0));dead.set_physics_process(false)
 enemy.position=dead.lure.global_position;dead._physics_process(0.001);dead.active_reel.set_physics_process(false)
 enemy.hp=0;dead.active_reel._physics_process(0.001);dead._physics_process(0.001)
 check(dead.is_queued_for_deletion() and dead.recasts_used==0,'enemy death removes pair without recast')
 await process_frame
 enemy.hp=100;enemy.position=Vector2(300,0)
 var replaced:=HookAnchorPair.place(area,player,spell,Vector2.ZERO,enemy.position);replaced.set_physics_process(false);replaced._physics_process(0.001)
 var held:=replaced.active_reel;held.set_physics_process(false)
 for i in 3:
  var extra:=HookAnchorPair.place(area,player,spell,Vector2(0,1000+i*50),Vector2(300,1000+i*50));extra.set_physics_process(false)
 check(replaced.is_queued_for_deletion(),'cap replaces oldest consumed pair')
 await process_frame
 check(not is_instance_valid(enemy.displacement_owner),'cap replacement releases active reel ownership')
 area.queue_free();await process_frame
 print('[809] ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
