class_name HookGroupReel
extends Node2D
## A single group center and rope, not one independent reel per enemy.
var enemies: Array[Enemy] = []
var target: Node2D
var spell: Spell
var reel_velocity := Vector2.ZERO
var age := 0.0
var _axis := Vector2.RIGHT
const ROPE := preload("res://assets/spells/hook_shot/rope.png")

static func begin(parent: Node, candidates: Array[Enemy], destination: Node2D, definition: Spell) -> HookGroupReel:
 var group := HookGroupReel.new();group.target=destination;group.spell=definition
 var center := Vector2.ZERO
 for enemy in candidates:
  if not is_instance_valid(enemy) or enemy.hp<=0:continue
  if not HookPullStack.attach(enemy,group):continue
  group.enemies.append(enemy);center+=enemy.global_position
 if group.enemies.is_empty():group.free();return null
 parent.add_child(group);group.global_position=center/group.enemies.size()
 return group

func heaviest_weight() -> float:
 var weight := 0.1
 for enemy in enemies:
  if is_instance_valid(enemy) and enemy.hp>0:weight=maxf(weight,enemy.weight)
 return weight

func _physics_process(delta: float) -> void:
 if not is_instance_valid(target) or not target.is_inside_tree() or (target is Player and target.hp<=0):queue_free();return
 # Remove by index: Godot's typed Array.erase rejects a freed Enemy,
 # leaving it here to error again on every later physics frame (#801).
 for i in range(enemies.size()-1, -1, -1):
  var enemy = enemies[i]
  if not is_instance_valid(enemy) or enemy.hp<=0 or not HookPullStack.contains(enemy,self):enemies.remove_at(i)
 if enemies.is_empty():queue_free();return
 # One frozen member pauses the whole connected bunch, preserving formation.
 for enemy in enemies:
  if enemy.freeze.is_frozen():return
 age+=delta
 if age>=spell.hook_timeout:queue_free();return
 var offset:=target.global_position-global_position
 if offset.length()>0.1:_axis=offset.normalized()
 var speed:=HookReel.speed_for(spell,heaviest_weight())
 var next_speed:=move_toward(reel_velocity.length(),speed,spell.hook_reel_acceleration*delta)
 reel_velocity=offset.normalized()*next_speed
 var motion:=reel_velocity*delta
 if motion.length()>offset.length():motion=offset
 global_position+=motion
 var arrived:=true
 var stop_distance:=HookReel.PLAYER_STOP_DISTANCE if target is Player else HookReel.ANCHOR_STOP_DISTANCE
 var spacing:=minf(12.0,24.0/maxf(enemies.size()-1,1))
 for i in enemies.size():
  var enemy:=enemies[i]
  var slot:=global_position+_axis*(i-(enemies.size()-1)*0.5)*spacing
  if enemy.global_position.distance_to(target.global_position)<=stop_distance+0.01:
   enemy.velocity=Vector2.ZERO
   continue
  if enemy.displacement_owner is HookPullStack:
   arrived=false
   continue
  var to_slot:=slot-enemy.global_position
  var step:=minf((next_speed+to_slot.length()*8.0)*delta,spell.hook_max_reel_speed*delta)
  var before:=enemy.global_position
  # No inherited sideways velocity and no overshoot of the current bunch slot.
  var enemy_motion:=to_slot.normalized()*minf(step,to_slot.length())
  enemy_motion=HookReel.stop_at_contact(enemy.global_position,enemy_motion,target.global_position,stop_distance)
  enemy.move_and_collide(enemy_motion)
  if enemy.terrain!=null:enemy.global_position=TerrainMotion.clamp_displacement(enemy.terrain,before,enemy.global_position,enemy.can_swim)
  enemy.global_position=enemy.constrain_movement(enemy.global_position)
  if enemy.global_position.distance_to(target.global_position)>stop_distance+0.01:arrived=false
 if arrived: _arrive()
 queue_redraw()

func pull_velocity(victim: Enemy, delta: float) -> Vector2:
 for member in enemies:
  if is_instance_valid(member) and member.freeze.is_frozen(): return Vector2.ZERO
 var index := enemies.find(victim)
 if index < 0: return Vector2.ZERO
 var spacing := minf(12.0,24.0/maxf(enemies.size()-1,1))
 var slot := global_position+_axis*(index-(enemies.size()-1)*0.5)*spacing
 var offset := slot-victim.global_position
 var speed := minf(reel_velocity.length()+offset.length()*8.0,spell.hook_max_reel_speed)
 return offset.normalized()*minf(speed,offset.length()/maxf(delta,0.000001))

func member_arrived(victim: Enemy) -> void:
 HookPullStack.detach(victim,self)
 enemies.erase(victim)
 victim.velocity=Vector2.ZERO
 if spell.hook_arrival_stun>0.0:victim.stun(spell.hook_arrival_stun)
 if enemies.is_empty():queue_free()

func _arrive() -> void:
 reel_velocity=Vector2.ZERO
 for enemy in enemies:
  HookPullStack.detach(enemy,self)
  enemy.velocity=Vector2.ZERO
  if spell.hook_arrival_stun>0.0:enemy.stun(spell.hook_arrival_stun)
 queue_free()

func _draw() -> void:
 if is_instance_valid(target):
  var end := to_local(target.global_position)
  draw_set_transform(Vector2.ZERO,end.angle())
  draw_texture_rect(ROPE,Rect2(0,-2,end.length(),4),true)

func _exit_tree() -> void:
 for enemy in enemies:
  if is_instance_valid(enemy):HookPullStack.detach(enemy,self)
