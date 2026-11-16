extends SceneTree
var failures := 0
func check(ok: bool, text: String):
 print("[783] ",text,": ",ok)
 if not ok: failures+=1
func _initialize():run.call_deferred()
func run():
 var area:=Node2D.new();root.add_child(area);current_scene=area
 var player:=load("res://game/player/player.tscn").instantiate() as Player;area.add_child(player)
 var s:=load("res://data/spells/hook_shot_magnet.tres") as Spell
 var enemies:Array[Enemy]=[]
 for i in 4:
  var e:=load("res://game/enemies/enemy.tscn").instantiate() as Enemy;area.add_child(e);e.set_physics_process(false)
  e.global_position=Vector2(300+i*20,100) if i<3 else Vector2(500,100)
  enemies.append(e)
 var shot:=HookShot.new();shot.prepare_shape();shot.setup(s,Vector2.RIGHT,player);shot.destination=Vector2(320,100)
 area.add_child(shot);shot.global_position=shot.destination;shot.set_physics_process(false)
 var result:Array[int]=[];shot.resolved.connect(func(n):result.append(n));shot._at_destination()
 check(result==[3],"three enemies hooked together inside72px")
 for i in 4:check(is_instance_valid(enemies[i].displacement_owner)==(i<3),"radius exclusion"+str(i))
 var row:=load("res://data/upgrades/hook_shot_magnet.tres") as SpellUpgrade
 check(row.quest.kind==SpellUpgradeQuest.Kind.HOOK_STREAK and row.quest.goal==3,"base quest unlocks specialization")
 area.queue_free();await process_frame;quit(1 if failures else 0)
