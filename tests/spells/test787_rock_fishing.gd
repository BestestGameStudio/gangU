extends SceneTree
var failures:=0
func check(ok:bool,text:String):
 print("[787] ",text,": ",ok)
 if not ok:failures+=1
func _initialize():run.call_deferred()
func run():
 var area:=Node2D.new();root.add_child(area);current_scene=area
 var player:=load("res://game/player/player.tscn").instantiate() as Player;area.add_child(player)
 var s:=load("res://data/spells/hook_shot_rock.tres") as Spell
 check(s.trigger_payload(Spell.TriggerMode.ALTERNATE,true).hook_anchor_mode,"alternate places pair")
 var alt:=s.alternate_spell
 var pairs:Array[HookAnchorPair]=[]
 for i in 4:
  var pair:=HookAnchorPair.place(area,player,alt,Vector2(100+i*10,100),Vector2(300+i*10,100));pair.set_physics_process(false);pairs.append(pair)
 check(pairs[0].is_queued_for_deletion(),"fourth pair replaces oldest")
 await process_frame
 check(get_nodes_in_group("hook_anchor_pairs").size()==3,"cap three pairs")
 var pair:=pairs[3]
 player.global_position=Vector2(999,999)
 check(pair.anchor.global_position==Vector2(130,100) and pair.lure.global_position==Vector2(330,100),"cast snapshots do not follow player")
 var enemy:=load("res://game/enemies/enemy.tscn").instantiate() as Enemy;area.add_child(enemy);enemy.set_physics_process(false);enemy.global_position=Vector2(390,100)
 pair._physics_process(0.01)
 check(enemy.hook_taunt_target==pair.lure and pair.taunt_left==5.0,"lure taunts nearby immediately")
 pair._physics_process(1.0);check(pair.taunt_left==4.0,"five second interval")
 enemy.global_position=pair.lure.global_position;pair._physics_process(0.01)
 var reel:=enemy.displacement_owner as HookReel
 check(reel!=null and reel.target==pair.anchor,"touch reels to fixed anchor")
 check(enemy.hook_taunt_target==null,"hook clears taunt")
 check(pair.consumed and pair.active_reel==reel,"catch consumes pair")
 enemy.global_position=Vector2(220,100);pair._physics_process(0.01)
 check(pair.lure.global_position==enemy.global_position,"caught lure follows reeled enemy")
 reel.set_physics_process(false);enemy.global_position=pair.anchor.global_position;reel._physics_process(0.001)
 pair._physics_process(0.001)
 check(not pair.is_queued_for_deletion() and pair.returning and pair.recasts_used==1,"successful arrival starts first automatic lure return")
 # The oldest consumed pair remains the elected emitter while another lure waits.
 var oldest:=pairs[1]
 var waiting:=pairs[2]
 var caught:=load("res://game/enemies/enemy.tscn").instantiate() as Enemy
 area.add_child(caught);caught.set_physics_process(false);caught.global_position=oldest.lure.global_position
 oldest._physics_process(0.01)
 check(oldest.consumed and not waiting.consumed,"oldest pair caught while second lure waits")
 oldest.active_reel.set_physics_process(false)
 oldest.whistle_left=0.5;oldest.note_age=0.0
 oldest._physics_process(0.25)
 check(is_equal_approx(oldest.whistle_left,0.25) and is_equal_approx(oldest.note_age,0.25),"consumed elected emitter keeps whistle and note clocks moving while reel is held")
 oldest._physics_process(0.30)
 check(oldest.whistle_left>=5.0 and is_equal_approx(oldest.note_age,0.55),"consumed emitter repeats whistle on cadence")
 var other_age:=waiting.note_age
 waiting._physics_process(0.1)
 check(waiting.note_age==other_age,"waiting pair does not duplicate owner emitter")
 var quest:=load("res://data/upgrades/hook_shot_rock.tres") as SpellUpgrade
 check(quest.quest.kind==SpellUpgradeQuest.Kind.CASTS and quest.quest.goal==5,"mastery placeholder five casts")
 area.queue_free();await process_frame;quit(1 if failures else 0)
