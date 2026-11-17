class_name HookPullStack
extends Node
## One movement pass per enemy. Reel contributions sum before a single speed cap.
var enemy: Enemy
var reels: Array[Node] = []

static func attach(victim: Enemy, reel: Node) -> bool:
 var owner := victim.displacement_owner
 if is_instance_valid(owner):
  if owner is HookPullStack:
   owner.reels.append(reel)
   return true
  if not (owner is HookReel or owner is HookGroupReel): return false
  var stack := HookPullStack.new()
  stack.enemy = victim
  stack.reels = [owner, reel]
  victim.add_child(stack)
  victim.displacement_owner = stack
 else:
  victim.displacement_owner = reel
 return true

static func contains(victim: Enemy, reel: Node) -> bool:
 if victim.displacement_owner == reel: return true
 var stack := victim.displacement_owner as HookPullStack
 return stack != null and stack.reels.has(reel)

static func detach(victim: Enemy, reel: Node) -> void:
 if victim.displacement_owner == reel:
  victim.displacement_owner = null
 elif victim.displacement_owner is HookPullStack:
  victim.displacement_owner.reels.erase(reel)

static func combined(vectors: Array[Vector2], cap: float) -> Vector2:
 var sum := Vector2.ZERO
 for vector in vectors: sum += vector
 return sum.limit_length(cap)

func _ready() -> void:
 process_physics_priority = 100

func _physics_process(delta: float) -> void:
 if not is_instance_valid(enemy) or enemy.hp <= 0: queue_free(); return
 for i in range(reels.size()-1, -1, -1):
  if not is_instance_valid(reels[i]) or reels[i].is_queued_for_deletion(): reels.remove_at(i)
 if reels.is_empty():
  if enemy.displacement_owner == self: enemy.displacement_owner = null
  enemy.velocity = Vector2.ZERO
  queue_free(); return
 if enemy.freeze.is_frozen(): return
 # Release an arrived contributor before summing: it must not pin another pull.
 for reel in reels.duplicate():
  if not is_instance_valid(reel.target): continue
  var radius := HookReel.PLAYER_STOP_DISTANCE if reel.target is Player else HookReel.ANCHOR_STOP_DISTANCE
  if enemy.global_position.distance_to(reel.target.global_position) <= radius + 0.01:
   reel.member_arrived(enemy)
 if reels.is_empty():
  if enemy.displacement_owner == self: enemy.displacement_owner = null
  enemy.velocity = Vector2.ZERO
  queue_free(); return
 var vectors: Array[Vector2] = []
 var cap := 0.0
 for reel in reels:
  # Group freeze pauses its contribution, not an unrelated reel's clock.
  vectors.append(reel.pull_velocity(enemy, delta))
  cap = maxf(cap, reel.spell.hook_max_reel_speed)
 var motion := combined(vectors, cap) * delta
 for reel in reels:
  if is_instance_valid(reel.target):
   var radius := HookReel.PLAYER_STOP_DISTANCE if reel.target is Player else HookReel.ANCHOR_STOP_DISTANCE
   motion = HookReel.stop_at_contact(enemy.global_position, motion, reel.target.global_position, radius)
 var before := enemy.global_position
 enemy.move_and_collide(motion)
 if enemy.terrain != null:
  enemy.global_position = TerrainMotion.clamp_displacement(enemy.terrain, before, enemy.global_position, enemy.can_swim)
 enemy.global_position = enemy.constrain_movement(enemy.global_position)
 for reel in reels.duplicate():
  if not is_instance_valid(reel) or reel.is_queued_for_deletion(): continue
  var radius := HookReel.PLAYER_STOP_DISTANCE if reel.target is Player else HookReel.ANCHOR_STOP_DISTANCE
  if enemy.global_position.distance_to(reel.target.global_position) <= radius + 0.01:
   reel.member_arrived(enemy)

func _exit_tree() -> void:
 if is_instance_valid(enemy) and enemy.displacement_owner == self: enemy.displacement_owner = null
