class_name HookGroupReel
extends Node2D
## A single group center and rope, not one independent reel per enemy.
var enemies: Array[Enemy] = []
var target: Node2D
var spell: Spell
var reel_velocity := Vector2.ZERO
var age := 0.0
var _axis := Vector2.RIGHT

static func begin(parent: Node, candidates: Array[Enemy], destination: Node2D, definition: Spell) -> HookGroupReel:
 var group := HookGroupReel.new();group.target=destination;group.spell=definition
 var center := Vector2.ZERO
 for enemy in candidates:
  if not is_instance_valid(enemy) or enemy.hp<=0 or is_instance_valid(enemy.displacement_owner):continue
  group.enemies.append(enemy);center+=enemy.global_position;enemy.displacement_owner=group
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
 for enemy in enemies.duplicate():
  if not is_instance_valid(enemy) or enemy.hp<=0 or enemy.displacement_owner!=self:enemies.erase(enemy)
 if enemies.is_empty():queue_free();return
 # One frozen member pauses the whole connected bunch, preserving formation.
 for enemy in enemies:
  if enemy.freeze.is_frozen():return
 age+=delta
 if age>=spell.hook_timeout:queue_free();return
 var offset:=target.global_position-global_position
 if offset.length()>0.1:_axis=offset.normalized()
 var speed:=HookReel.speed_for(spell,heaviest_weight())
 reel_velocity=reel_velocity.move_toward(offset.normalized()*speed,spell.hook_reel_acceleration*delta).limit_length(speed)
 var motion:=reel_velocity*delta
 if motion.length()>offset.length():motion=offset
 global_position+=motion
 var arrived:=true
 var spacing:=minf(12.0,24.0/maxf(enemies.size()-1,1))
 for i in enemies.size():
  var enemy:=enemies[i]
  var slot:=global_position+_axis*(i-(enemies.size()-1)*0.5)*spacing
  var wanted:=reel_velocity+(slot-enemy.global_position)*8.0
  var before:=enemy.global_position
  enemy.move_and_collide(wanted.limit_length(spell.hook_max_reel_speed)*delta)
  if enemy.terrain!=null:enemy.global_position=TerrainMotion.clamp_displacement(enemy.terrain,before,enemy.global_position,enemy.can_swim)
  enemy.global_position=enemy.constrain_movement(enemy.global_position)
  if enemy.global_position.distance_to(target.global_position)>18.0:arrived=false
 if arrived: _arrive()
 queue_redraw()

func _arrive() -> void:
 queue_free()

func _draw() -> void:
 if is_instance_valid(target):draw_line(to_local(target.global_position),Vector2.ZERO,Color(0.7,0.8,0.8),1.0)

func _exit_tree() -> void:
 for enemy in enemies:
  if is_instance_valid(enemy) and enemy.displacement_owner==self:enemy.displacement_owner=null
