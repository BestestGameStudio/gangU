extends SceneTree
var failures:=0
var checks:=0
class Charger extends EnemyBehavior:
 func physics_step(enemy: Enemy, _player: Player, _delta: float) -> void:
  enemy.velocity=Vector2(600,0)
  enemy.terrain_move_and_slide()
func check(ok:bool,label:String):
 checks+=1
 print('[805] ',label,': ',ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 var drive:=Vector2(600,0)
 check(Enemy.force_step(drive,Vector2.ZERO,Vector2.ZERO,4,0.1,2400)==drive,'no force preserves600 propulsion')
 var opposing:=Vector2(-2400,0)
 check(Enemy.force_step(drive,Vector2.ZERO,opposing,4,0.1,2400)==Vector2(540,0),'opposing force divided by weight')
 check(Enemy.force_step(drive,Vector2.ZERO,opposing*2,4,0.1,2400)==Vector2(480,0),'stacked force doubles deceleration')
 check(Enemy.force_step(drive,Vector2.ZERO,opposing,1,0.1,2400)==Vector2(360,0),'light enemy slows more than weight4')
 check(Enemy.force_step(drive,Vector2.ZERO,Vector2(0,2400),4,0.1,2400)==Vector2(600,60),'perpendicular force deflects without flat slow')
 var area:=Node2D.new();root.add_child(area);current_scene=area
 var player=load('res://game/player/player.tscn').instantiate() as Player;player.name='Player';area.add_child(player);player.set_physics_process(false);player.position=Vector2(-500,0)
 var enemy=load('res://game/enemies/enemy.tscn').instantiate() as Enemy;area.add_child(enemy);enemy.set_physics_process(false);enemy.position=Vector2.ZERO;enemy.weight=4;enemy._behavior=Charger.new()
 var spell=load('res://data/spells/hook_shot.tres')
 var reel=HookReel.begin(area,enemy,player,spell);reel.set_physics_process(false)
 enemy._physics_process(0.1)
 check(enemy.position==Vector2.ZERO and enemy.reel_propulsion==drive,'ordinary charger submits drive without a second move')
 reel._physics_process(0.1)
 check(is_equal_approx(enemy.position.x,54),'general reel force slows actual charger600 to540')
 reel.queue_free();enemy.queue_free();await process_frame
 # Exercise production behavior paths that previously called native movement.
 for behavior_path in ['enemy_behavior_chase_contact','enemy_behavior_idle_chase','enemy_behavior_wolf','enemy_behavior_bird','enemy_behavior_fishy']:
  var real_enemy=load('res://game/enemies/enemy.tscn').instantiate() as Enemy
  area.add_child(real_enemy);real_enemy.set_physics_process(false);real_enemy.position=Vector2(100,100);real_enemy._behavior=load('res://game/enemies/behaviors/'+behavior_path+'.gd').new()
  real_enemy._sampling_reel_propulsion=true
  var before=real_enemy.position
  real_enemy._behavior.physics_step(real_enemy,player,0.1)
  real_enemy._sampling_reel_propulsion=false
  check(real_enemy.position==before,'real behavior cannot move during sampling: '+behavior_path)
  if behavior_path=='enemy_behavior_chase_contact':check(not real_enemy.reel_propulsion.is_zero_approx(),'real chase records nonzero propulsion')
  real_enemy.queue_free()
 await process_frame
 # A hooked bird reaching a later DIVE landing cannot teleport through pulls.
 var bird=load('res://game/enemies/enemy_bird.tscn').instantiate() as Enemy
 area.add_child(bird);bird.set_physics_process(false);bird.position=Vector2(200,100)
 var behavior:=bird._behavior as EnemyBehaviorBird
 behavior.state=EnemyBehaviorBird.DIVE;behavior._timer=0.001;behavior._locked=Vector2(500,100)
 var bird_reel=HookReel.begin(area,bird,player,spell);bird_reel.set_physics_process(false)
 var bird_before=bird.position
 bird._physics_process(0.016)
 check(behavior.state==EnemyBehaviorBird.STUNNED,'held bird completes real dive state transition')
 check(bird.position==bird_before,'held dive landing does not teleport during sampling')
 check(not bird.reel_propulsion.is_zero_approx() and bird.reel_propulsion.x>0,'landing preserves desired dive motion instead of overwriting zero')
 bird_reel._physics_process(0.016)
 check(bird.position.distance_to(bird_before)<=2400*0.016+0.01,'held landing moves only through capped force resolver')
 check(HookPullStack.contains(bird,bird_reel),'bird landing does not steal or release reel ownership')
 bird.queue_free();bird_reel.queue_free();await process_frame
 var region:=Node2D.new();area.add_child(region)
 var arena:=DesertStatueArena.new();region.add_child(arena);arena.set_physics_process(false);arena.start_encounter();arena._enter_phase_two()
 var boss=arena.possessed;boss.set_physics_process(false)
 check(boss.weight==6 and arena.statues.all(func(statue):return statue.weight==6),'Sand General generated mass6')
 check(Enemy.force_step(drive,Vector2.ZERO,opposing,boss.weight,0.1,2400)==Vector2(560,0),'Sand mass6 resists same force more than mass4')
 var rock=load('res://data/spells/hook_shot_rock.tres')
 var pair=HookAnchorPair.place(region,player,rock.alternate_spell,boss.global_position+Vector2(-250,0),boss.global_position);pair.set_physics_process(false);pair._physics_process(0.016);pair.active_reel.set_physics_process(false)
 var other=HookReel.begin(region,boss,player,spell);other.set_physics_process(false)
 var stack=boss.displacement_owner as HookPullStack;stack.set_physics_process(false)
 var actual=boss.global_position+Vector2(75,0);boss.global_position=actual
 arena._phase_two_attack_time=-1;arena._phase_two_step(0.016)
 check(boss.global_position.is_equal_approx(actual),'arena does not overwrite existing reel displacement during idle')
 arena._phase_two_attack_index=3;arena._phase_two_attack_time=0.3;arena._phase_two_locked=true
 arena._phase_two_step(0.016)
 check(arena.general_height>0 and pair.is_queued_for_deletion(),'boss jump removes attached anchor/lure pair')
 check(HookPullStack.contains(boss,other),'jump preserves independent regular reel')
 stack._physics_process(0.016)
 check(not stack.reels.has(pair.active_reel),'jump detach removes only anchor contribution')
 # Off-path actual position becomes next attack origin and spear launch frame.
 boss.position=Vector2(123,45);arena._phase_two_boss_position=Vector2.ZERO
 arena._phase_two_attack_index=0;arena._phase_two_attack_time=0;arena._phase_two_locked=false
 arena._phase_two_step(0.001)
 check(arena._phase_two_origin.is_equal_approx(boss.position),'next attack origin rebased to actual pulled actor')
 var spear=arena._general_spear(arena._phase_two_origin+arena._phase_two_direction*45.0,arena._phase_two_direction,1,100,4)
 check(spear.position.distance_to(boss.position)<=45.01,'next spear launches from actual actor frame')
 arena._phase_two_attack_index=3;arena._phase_two_attack_time=arena.MOVE_WINDUP[3]+arena.MOVE_CUE[3]
 arena._phase_two_locked=true;arena._phase_two_attack_done=true;arena._phase_two_release_done=false
 arena._phase_two_aim=Vector2(-120,80)
 arena._phase_two_step(0.001)
 check(boss.position.is_equal_approx(arena._phase_two_aim),'off-path slam lands exactly at impact and damage center')
 area.queue_free();await process_frame
 print('[805] ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
