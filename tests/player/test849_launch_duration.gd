extends SceneTree
## #849: final launch tick contributes only its remaining duration.
var failures := 0
func check(value: bool, label: String) -> void:
 print('[849] ', 'PASS ' if value else 'FAIL ',label)
 if not value:failures+=1
func player() -> Player:
 var p=load('res://game/player/player.tscn').instantiate() as Player
 p.collision_layer=0;p.collision_mask=0;root.add_child(p);p.set_physics_process(false)
 return p
func _initialize() -> void:run.call_deferred()
func run() -> void:
 for dt in [1.0/30.0,1.0/60.0,1.0/120.0]:
  for duration in [0.003,0.12,0.1,dt*2.0]:
   var p:=player();var ends: Array[Vector2]=[]
   p.launch_ended.connect(func():ends.append(p.global_position))
   check(p.launch(Vector2.RIGHT,700.0,duration),'launch accepted')
   var integrated:=Vector2.ZERO;var ticks:=0
   while p.is_launching() and ticks<100:
    p._physics_process(dt);integrated+=p.velocity*dt;ticks+=1
   check(absf(integrated.x-700.0*duration)<0.001 and absf(integrated.y)<0.001,'velocity integral speed*duration dt=%s duration=%s got=%s'%[dt,duration,integrated])
   check(ends.size()==1,'one end signal after completed motion')
   if dt==1.0/60.0:
    check(absf(p.position.x-700.0*duration)<0.001,'actual60Hz Player displacement matches duration')
    check(ends[0].is_equal_approx(p.global_position),'end emitted at settled position')
   p.free()
 var p:=player()
 p.launch(Vector2.RIGHT,700.0,0.12);p._physics_process(0.0)
 check(p.velocity==Vector2(700,0) and p.is_launching(),'zero delta remains finite and does not consume duration')
 p.hp=0;p._physics_process(1.0/60.0)
 check(not p.is_launching() and p.velocity==Vector2.ZERO,'death cancels launch')
 p.free()
 print('[849] DONE failures=',failures)
 quit(1 if failures else 0)
