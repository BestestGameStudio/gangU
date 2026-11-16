extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String):
 checks+=1
 print('[803] ',label,': ',ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 var vectors:Array[Vector2]=[Vector2(1500,0),Vector2(-1500,0)]
 check(HookPullStack.combined(vectors,2400)==Vector2.ZERO,'equal opposite pulls cancel')
 vectors=[Vector2(1500,0),Vector2(0,1500)]
 check(HookPullStack.combined(vectors,2400).is_equal_approx(Vector2(1500,1500)),'perpendicular pull preserves vector components')
 vectors=[Vector2(1500,0),Vector2(1500,0)]
 check(HookPullStack.combined(vectors,2400)==Vector2(2400,0),'same direction sums then caps2400')
 var area:=Node2D.new();root.add_child(area);current_scene=area
 var scene=load('res://game/enemies/enemy.tscn')
 var s=load('res://data/spells/hook_shot.tres')
 var left:=Node2D.new();area.add_child(left);left.position=Vector2(-500,0)
 var right:=Node2D.new();area.add_child(right);right.position=Vector2(500,0)
 var enemy=scene.instantiate() as Enemy;area.add_child(enemy);enemy.set_physics_process(false);enemy.position=Vector2.ZERO
 var a=HookReel.begin(area,enemy,left,s);a.set_physics_process(false)
 var b=HookReel.begin(area,enemy,right,s);b.set_physics_process(false)
 var stack=enemy.displacement_owner as HookPullStack;stack.set_physics_process(false)
 check(stack.reels.size()==2 and HookPullStack.contains(enemy,a) and HookPullStack.contains(enemy,b),'both contributors retain ownership')
 for tick in 20:
  a._physics_process(1.0/60);b._physics_process(1.0/60);stack._physics_process(1.0/60)
 check(enemy.position.is_equal_approx(Vector2.ZERO),'opposite actual reel motion cancels without sequential drift')
 a.queue_free();await process_frame
 b._physics_process(0.05);stack._physics_process(0.05)
 check(enemy.position.x>0 and HookPullStack.contains(enemy,b),'one ending leaves other pulling')
 right.queue_free();await process_frame
 b._physics_process(0.01);stack._physics_process(0.01);await process_frame
 check(not is_instance_valid(enemy.displacement_owner),'target exit releases final contributor')
 enemy.queue_free();await process_frame
 # Real signature acquisition uses HookShot endpoint group, then stacks a base reel.
 var player=load('res://game/player/player.tscn').instantiate() as Player;area.add_child(player);player.set_physics_process(false);player.position=Vector2(600,400)
 for id in ['hook_shot_magnet','hook_shot_catch','hook_shot_rock']:
  var spell=load('res://data/spells/'+id+'.tres')
  var victim=scene.instantiate() as Enemy;area.add_child(victim);victim.set_physics_process(false);victim.position=Vector2(300,400)
  var shot:=HookShot.new();shot.spell=spell;shot.source=player;shot.destination=victim.position;shot.prepare_shape();area.add_child(shot);shot.set_physics_process(false)
  shot._at_destination()
  var group=victim.displacement_owner as HookGroupReel
  check(group!=null,'endpoint magnet acquisition '+id)
  group.set_physics_process(false)
  var extra=HookReel.begin(area,victim,player,s);extra.set_physics_process(false)
  var combined=victim.displacement_owner as HookPullStack;combined.set_physics_process(false)
  for tick in 90:
   if not extra.is_queued_for_deletion():extra._physics_process(1.0/60)
   if not group.is_queued_for_deletion():group._physics_process(1.0/60)
   combined._physics_process(1.0/60)
   if combined.is_queued_for_deletion():break
  check(victim.position.distance_to(player.position)<=32.02 and victim.position.x<=player.position.x,'stacked group stops on approach side '+id)
  check(victim.velocity==Vector2.ZERO,'arrival momentum zero '+id)
  check(not is_instance_valid(victim.displacement_owner) or combined.reels.is_empty(),'all arrivals release ownership '+id)
  victim.queue_free();await process_frame
 # A caught lure follows an enemy also acquired by a signature Magnet group.
 var rock=load('res://data/spells/hook_shot_rock.tres')
 var caught=scene.instantiate() as Enemy;area.add_child(caught);caught.set_physics_process(false);caught.position=Vector2(300,200)
 var pair=HookAnchorPair.place(area,player,rock.alternate_spell,Vector2(100,200),caught.position);pair.set_physics_process(false)
 pair._physics_process(0.016);pair.active_reel.set_physics_process(false)
 var anchor_at=pair.anchor.global_position
 var candidates:Array[Enemy]=[caught]
 var mixed=HookGroupReel.begin(area,candidates,player,rock);mixed.set_physics_process(false)
 var mix=caught.displacement_owner as HookPullStack;mix.set_physics_process(false)
 pair.active_reel._physics_process(0.016);mixed._physics_process(0.016);mix._physics_process(0.016);pair._physics_process(0.016)
 check(pair.consumed and pair.lure.global_position==caught.global_position and pair.anchor.global_position==anchor_at,'stacked lure follows enemy; anchor remains fixed')
 pair.active_reel.queue_free();await process_frame
 pair._physics_process(0.016)
 check(pair.is_queued_for_deletion() and HookPullStack.contains(caught,mixed),'anchor reel ends: pair removed while Magnet retains enemy')
 caught.free();mixed._physics_process(0.016)
 check(mixed.is_queued_for_deletion(),'stacked killed enemy prunes without freeze errors')
 await process_frame
 # Heaviest living member remains group speed source even with stack controller.
 var heavy=scene.instantiate() as Enemy;area.add_child(heavy);heavy.set_physics_process(false);heavy.weight=5;heavy.position=Vector2(100,100)
 var light=scene.instantiate() as Enemy;area.add_child(light);light.set_physics_process(false);light.weight=1;light.position=Vector2(120,100)
 var members:Array[Enemy]=[heavy,light]
 var group=HookGroupReel.begin(area,members,player,load('res://data/spells/hook_shot_rock.tres'));group.set_physics_process(false)
 var extra=HookReel.begin(area,light,left,s);extra.set_physics_process(false)
 check(group.heaviest_weight()==5 and HookReel.speed_for(group.spell,group.heaviest_weight())==300,'signature group retains heaviest weight speed rule')
 heavy.free();group._physics_process(0.016)
 check(group.heaviest_weight()==1,'freed heavy member prunes without freeze errors')
 light.free();group._physics_process(0.016);await process_frame
 area.queue_free();await process_frame
 print('[803] ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
