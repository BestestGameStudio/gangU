class_name EnemyBehaviorChaseContact
extends RefCounted
## #99 (Foundation E2): the CURRENT chase/contact behavior, extracted
## unchanged from enemy.gd into a swappable behavior. enemy_definition.gd's
## behavior slot names a Script; each Enemy instantiates its OWN behavior
## instance in _ready, so per-enemy state (the contact cooldown timer)
## lives on the instance and is NEVER shared across enemies (no shared
## Resource state).
##
## Contract (unchanged): chase the resolved player at speed, stop within
## 8px, deal contact_damage inside contact_range with contact_cooldown
## between hits; idle (zero velocity) when there is no live player.
## Stats stay on the enemy (definition-supplied); this class owns only
## the cooldown timer.

var _contact_timer: float = 0.0

## #209: target parameter widened (Player -> duck-typed) so the default
## chase/contact behavior can target Summons; the target contract used here
## is hp, global_position, damage_modifiers and apply_damage, which both
## Player and Summon provide.
func physics_step(enemy: Enemy, player, delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.hp <= 0:
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		return
	var to_player: Vector2 = player.global_position - enemy.global_position
	var chase: Vector2 = to_player.normalized() * enemy.speed if to_player.length() > 8.0 else Vector2.ZERO
	enemy.velocity = TerrainMotion.resolve(enemy.terrain, enemy.global_position, enemy.velocity, chase, delta, enemy.can_swim)
	enemy.move_and_slide()
	_contact_timer = maxf(0.0, _contact_timer - delta)
	if to_player.length() <= enemy.contact_range and _contact_timer <= 0.0:
		player.apply_damage(DamageCalc.compute(enemy.contact_damage, enemy.damage_modifiers, player.damage_modifiers, enemy.damage_rng).amount)
		_contact_timer = enemy.contact_cooldown
		enemy.play_action(&"attack") # #177: visual swing only
