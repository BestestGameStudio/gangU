extends EnemyBehavior
class_name EnemyBehaviorDesertMustache
var _path := TerrainPath.new()
var _contact_timer := 0.0
func physics_step(enemy: Enemy, _target, dt: float) -> void:
 var squad := enemy.get_parent() as DesertMustacheGroup
 if squad == null:
  enemy.velocity = Vector2.ZERO
  enemy.terrain_move_and_slide()
  return
 var player := squad.target()
 var goal := squad.destination(enemy)
 var speed := enemy.speed*(1.85 if squad.state == DesertMustacheGroup.State.CHARGE else 1.0)
 var desired := enemy.global_position.direction_to(goal)*speed if enemy.global_position.distance_to(goal) > 10.0 else Vector2.ZERO
 if squad.state != DesertMustacheGroup.State.TRAVEL and squad.state != DesertMustacheGroup.State.CHARGE and player != null:
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
