extends EnemyBehavior
class_name EnemyBehaviorDesertMustache
var _path := TerrainPath.new()
var _contact_timer := 0.0
var _shift_left := 0.0
var _shift := Vector2.ZERO
var _pace := 1.0
var _rng := RandomNumberGenerator.new()
var _seeded := false
func physics_step(enemy: Enemy, _target, dt: float) -> void:
 var squad := enemy.get_parent() as DesertMustacheGroup
 if squad == null:
  enemy.velocity = Vector2.ZERO
  enemy.terrain_move_and_slide()
  return
 var player := squad.target()
 var goal := squad.destination(enemy)
 var speed := enemy.speed*(1.85 if squad.state == DesertMustacheGroup.State.CHARGE else 1.0)
 if squad.state == DesertMustacheGroup.State.TRAVEL:
  if not _seeded:
   _rng.seed = 2909+maxi(0,squad.members.find(enemy))*7919
   _seeded = true
  _shift_left -= dt
  if _shift_left <= 0.0:
   _shift_left = _rng.randf_range(0.16,0.52)
   _shift = Vector2.from_angle(_rng.randf_range(-PI,PI))*_rng.randf_range(16.0,58.0)
   _pace = 0.0 if _rng.randf()<0.24 else _rng.randf_range(0.6,1.55)
  goal += _shift
  speed *= _pace
 var desired := enemy.global_position.direction_to(goal)*speed if enemy.global_position.distance_to(goal) > 10.0 else Vector2.ZERO
 if squad.state in [DesertMustacheGroup.State.SPREAD,DesertMustacheGroup.State.THROW,DesertMustacheGroup.State.WAIT_SMOKE] and player != null:
  var away: Vector2 = enemy.global_position-player.global_position
  if away.length() < squad.keep_distance-35.0: desired = away.normalized()*speed
  if enemy == squad.leader and squad.state in [DesertMustacheGroup.State.THROW,DesertMustacheGroup.State.WAIT_SMOKE] and away.length() >= squad.keep_distance-35.0: desired = Vector2.ZERO
 # Separation is a desired velocity, still subject to terrain/force integration.
 for peer in squad.members:
  if not is_instance_valid(peer) or peer == enemy or peer.hp <= 0: continue
  var away := enemy.global_position-peer.global_position
  if away.length_squared() > 0.01 and away.length() < 42.0: desired += away.normalized()*speed*0.65
 desired = desired.limit_length(speed)
 enemy.velocity = _path.steer(enemy.terrain,enemy.global_position,enemy.velocity,desired,goal,speed,dt,enemy.can_swim)
 enemy.terrain_move_and_slide()
 enemy.global_position = enemy.constrain_movement(enemy.global_position)
 _contact_timer = maxf(0.0,_contact_timer-dt)
 if squad.state == DesertMustacheGroup.State.CHARGE and player != null and _contact_timer <= 0.0 and enemy.global_position.distance_to(player.global_position) <= enemy.contact_range:
  enemy.deal_hit(player,enemy.contact_damage,OnHit.DELIVERY_CONTACT)
  enemy.play_action(&"attack")
  _contact_timer = enemy.contact_cooldown
func debug_state_text() -> String:
 return "DESERT SQUAD"
