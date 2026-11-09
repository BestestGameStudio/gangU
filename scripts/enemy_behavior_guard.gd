class_name EnemyBehaviorGuard
extends EnemyBehaviorChaseContact
## #346: overworld entrance guard. The default chase/contact behavior chases
## the player from anywhere, which in a large overworld would pull every
## entrance's guards onto the player at once. A guard instead holds its post
## (its spawn position) until the target comes within AGGRO_RADIUS or it is
## hurt, then chases exactly like the default behavior. When the target gets
## farther than LEASH_RADIUS from the post it gives up and walks back.
## Extends the default so Enemy._resolve_target keeps summon targeting.
## Radii are provisional implementation choices, not approved balance.

const AGGRO_RADIUS := 220.0
const LEASH_RADIUS := 520.0
const HOME_EPSILON := 6.0

var home := Vector2.INF
var engaged := false
var _last_hp := -1

func physics_step(enemy: Enemy, player, delta: float) -> void:
	if home == Vector2.INF:
		home = enemy.global_position
	if _last_hp >= 0 and enemy.hp < _last_hp:
		engaged = true # hit from outside aggro range: fight back
	_last_hp = enemy.hp
	var alive: bool = player != null and is_instance_valid(player) and player.hp > 0
	if alive:
		var target_pos: Vector2 = player.global_position
		if not engaged and enemy.global_position.distance_to(target_pos) <= AGGRO_RADIUS:
			engaged = true
		if engaged and home.distance_to(target_pos) > LEASH_RADIUS:
			engaged = false
	else:
		engaged = false
	if engaged:
		super(enemy, player, delta)
		return
	_contact_timer = maxf(0.0, _contact_timer - delta)
	var to_home := home - enemy.global_position
	var walk := to_home.normalized() * enemy.speed if to_home.length() > HOME_EPSILON else Vector2.ZERO
	enemy.velocity = TerrainMotion.resolve(enemy.terrain, enemy.global_position, enemy.velocity, walk, delta, enemy.can_swim)
	enemy.move_and_slide()
