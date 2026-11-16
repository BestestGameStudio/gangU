extends SceneTree
var failures:=0
func check(ok:bool,text:String):
 print("[785] ",text,": ",ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 var area:=Node2D.new();root.add_child(area);current_scene=area
 var player:=load("res://game/player/player.tscn").instantiate() as Player;area.add_child(player)
 var enemy:=load("res://game/enemies/enemy.tscn").instantiate() as Enemy;area.add_child(enemy)
 enemy.set_physics_process(false);enemy.global_position=player.global_position+Vector2(10,0)
 var s:=load("res://data/spells/hook_shot_catch.tres") as Spell
 check(s.hook_magnet_radius==120 and s.hook_arrival_stun==1.5,"larger120px radius/stun1.5s")
 var reel:=HookReel.begin(area,enemy,player,s);reel.set_physics_process(false);reel._physics_process(0.016)
 check(reel.arrived and enemy.stun_left==1.5,"arrival stuns enemy")
 await process_frame
 check(not is_instance_valid(enemy.displacement_owner),"arrival releases reel control")
 var position:=enemy.global_position;enemy._physics_process(0.5)
 check(enemy.stun_left==1.0 and enemy.global_position==position,"stun suspends locomotion and advances")
 enemy._physics_process(1.01);check(enemy.stun_left==0,"stun expires")
 enemy.stun_left=0.0
 var group:=HookGroupReel.begin(area,[enemy],player,s)
 group.set_physics_process(false);group._physics_process(0.001)
 check(enemy.stun_left==1.5,"group arrival stuns too")
 var row:=load("res://data/upgrades/hook_shot_catch.tres") as SpellUpgrade
 check(row.quest.kind==SpellUpgradeQuest.Kind.HOOK_GROUP and row.quest.projectiles==3,"quest three at once")
 area.queue_free();await process_frame;quit(1 if failures else 0)
