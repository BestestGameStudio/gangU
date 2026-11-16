class_name HookReel
extends Node2D
## Owns one enemy until arrival, obstruction timeout, death or scene exit.
var enemy: Enemy
var target: Node2D
var spell: Spell
var reel_velocity := Vector2.ZERO
var age := 0.0
var arrived := false

static func speed_for(s: Spell, weight: float) -> float:
 return minf(maxf(s.hook_max_reel_speed, 0.0), maxf(s.hook_reel_speed * s.displacement_force, 0.0) / maxf(weight, 0.1))

static func begin(parent: Node, victim: Enemy, destination: Node2D, definition: Spell) -> HookReel:
 if not is_instance_valid(victim) or victim.hp <= 0 or is_instance_valid(victim.displacement_owner): return null
 var reel := HookReel.new()
 reel.enemy = victim; reel.target = destination; reel.spell = definition
 victim.displacement_owner = reel
 victim.hook_taunt_target = null; victim.hook_taunt_left = 0.0
 parent.add_child(reel)
 return reel

func _physics_process(delta: float) -> void:
 if not is_instance_valid(enemy) or enemy.hp <= 0 or not is_instance_valid(target) or not target.is_inside_tree() or (target is Player and target.hp <= 0):
  queue_free(); return
 if enemy.displacement_owner != self: queue_free(); return
 if enemy.freeze.is_frozen(): return
 age += delta
 if age >= spell.hook_timeout: queue_free(); return
 var offset := target.global_position - enemy.global_position
 if offset.length() <= 18.0:
  arrived = true
  if spell.hook_arrival_stun > 0.0: enemy.stun(spell.hook_arrival_stun)
  queue_free(); return
 var speed := speed_for(spell, enemy.weight)
 # Acceleration limits preserve lateral velocity as a moving player changes aim.
 reel_velocity = reel_velocity.move_toward(offset.normalized() * speed, spell.hook_reel_acceleration * delta).limit_length(speed)
 var motion := reel_velocity * delta
 if motion.length() > offset.length(): motion = motion.normalized() * offset.length()
 var before := enemy.global_position
 enemy.move_and_collide(motion)
 if enemy.terrain != null:
  enemy.global_position = TerrainMotion.clamp_displacement(enemy.terrain, before, enemy.global_position, enemy.can_swim)
 enemy.global_position = enemy.constrain_movement(enemy.global_position)
 queue_redraw()

func _draw() -> void:
 if is_instance_valid(enemy) and is_instance_valid(target):
  draw_line(to_local(target.global_position), to_local(enemy.global_position), Color(0.7, 0.8, 0.8), 1.0)

func _exit_tree() -> void:
 if is_instance_valid(enemy) and enemy.displacement_owner == self:
  enemy.displacement_owner = null
