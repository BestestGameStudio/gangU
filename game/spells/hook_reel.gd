class_name HookReel
extends Node2D
signal reached_target
## Owns one enemy until arrival, obstruction timeout, death or scene exit.
var enemy: Enemy
var target: Node2D
var spell: Spell
var reel_velocity := Vector2.ZERO
var age := 0.0
var arrived := false
const PLAYER_STOP_DISTANCE := 32.0
const ANCHOR_STOP_DISTANCE := 18.0
const ROPE_ART := preload("res://assets/spells/hook_shot/rope.png")

static func speed_for(s: Spell, weight: float) -> float:
 return minf(maxf(s.hook_max_reel_speed, 0.0), maxf(s.hook_reel_speed * s.displacement_force, 0.0) / maxf(weight, 0.1))

static func stop_at_contact(from: Vector2, motion: Vector2, destination: Vector2, radius: float) -> Vector2:
 var offset := from - destination
 if offset.length_squared() <= radius * radius: return Vector2.ZERO
 var a := motion.length_squared()
 if a <= 0.000001: return motion
 var b := 2.0 * offset.dot(motion)
 var c := offset.length_squared() - radius * radius
 var discriminant := b * b - 4.0 * a * c
 if discriminant < 0.0: return motion
 var hit := (-b - sqrt(discriminant)) / (2.0 * a)
 return motion * hit if hit >= 0.0 and hit <= 1.0 else motion

static func begin(parent: Node, victim: Enemy, destination: Node2D, definition: Spell) -> HookReel:
 if not is_instance_valid(victim) or victim.hp <= 0: return null
 var reel := HookReel.new()
 reel.enemy = victim; reel.target = destination; reel.spell = definition
 if not HookPullStack.attach(victim, reel): reel.free(); return null
 victim.hook_taunt_target = null; victim.hook_taunt_left = 0.0
 parent.add_child(reel)
 return reel

func _physics_process(delta: float) -> void:
 if not is_instance_valid(enemy) or enemy.hp <= 0 or not is_instance_valid(target) or not target.is_inside_tree() or (target is Player and target.hp <= 0):
  queue_free(); return
 if not HookPullStack.contains(enemy, self): queue_free(); return
 if enemy.freeze.is_frozen(): return
 age += delta
 if age >= spell.hook_timeout: queue_free(); return
 var offset := target.global_position - enemy.global_position
 var stop_distance := PLAYER_STOP_DISTANCE if target is Player else ANCHOR_STOP_DISTANCE
 if offset.length() <= stop_distance:
  _arrive(); return
 var speed := speed_for(spell, enemy.weight)
 # Accelerate inward only. A moving player must not leave tangential momentum.
 var next_speed := move_toward(reel_velocity.length(), speed, spell.hook_reel_acceleration * delta)
 reel_velocity = offset.normalized() * next_speed
 var motion := offset.normalized() * minf(next_speed * delta, maxf(offset.length() - stop_distance, 0.0))
 if enemy.displacement_owner is HookPullStack:
  queue_redraw(); return
 if not enemy.reel_propulsion.is_zero_approx():
  motion = enemy.resolve_reel_force(pull_force(enemy),delta,pull_speed_limit(enemy))*delta
  motion = stop_at_contact(enemy.global_position,motion,target.global_position,stop_distance)
 var before := enemy.global_position
 enemy.move_and_collide(motion)
 if enemy.terrain != null:
  enemy.global_position = TerrainMotion.clamp_displacement(enemy.terrain, before, enemy.global_position, enemy.can_swim)
 enemy.global_position = enemy.constrain_movement(enemy.global_position)
 if enemy.global_position.distance_to(target.global_position) <= stop_distance + 0.01:
  _arrive(); return
 queue_redraw()

func pull_speed_limit(victim: Enemy) -> float:
 return speed_for(spell,victim.weight)

func pull_force(victim: Enemy) -> Vector2:
 return victim.global_position.direction_to(target.global_position)*spell.hook_reel_acceleration*spell.displacement_force

func pull_velocity(_victim: Enemy, _delta: float) -> Vector2:
 return reel_velocity

func member_arrived(_victim: Enemy) -> void:
 _arrive()

func _arrive() -> void:
 HookPullStack.detach(enemy, self)
 arrived = true
 reel_velocity = Vector2.ZERO
 enemy.velocity = Vector2.ZERO
 enemy.reel_force_velocity = Vector2.ZERO
 if spell.hook_arrival_stun > 0.0: enemy.stun(spell.hook_arrival_stun)
 reached_target.emit()
 queue_free()

func _draw() -> void:
 if is_instance_valid(enemy) and is_instance_valid(target):
  var start := to_local(target.global_position)
  var end := to_local(enemy.global_position)
  draw_set_transform(start, (end-start).angle())
  draw_texture_rect(ROPE_ART, Rect2(0,-2,start.distance_to(end),4), true)

func _exit_tree() -> void:
 if is_instance_valid(enemy): HookPullStack.detach(enemy, self)
