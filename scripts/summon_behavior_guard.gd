class_name SummonBehaviorGuard
extends RefCounted
## #212: the first concrete summon behavior - the guard ally cast by the
## summon spell. Owner-approved behavior (Daniel, 2026-11-08): "taunts and
## attacks enemies close range. Stays at a distance from you but will follow
## if you get too far"; starting balance 30 HP / 5 melee per 0.8s / no expiry,
## tuned after the demo. Stats live on SummonDefinition, never hardcoded here.
##
## Contract:
##   (a) RETURN PRIORITY - when the player is beyond follow_far, move toward
##       the player and ignore combat entirely ("will follow if you get too
##       far" wins over "attacks enemies close range").
##   (b) Otherwise engage the nearest live enemy inside aggro_range: chase to
##       contact_range, then apply contact_damage with contact_cooldown
##       between hits through the one DamageCalc path. The timer lives on
##       this per-summon instance and is never shared (EnemyBehaviorChaseContact
##       idiom).
##   (c) Otherwise hold position ("stays at a distance from you").
##
## Taunt is NOT implemented here: enemies retarget through enemy.gd's
## _resolve_target (the #212 local taunt_range gate; bosses are structurally
## player-only). This script only moves the summon and deals damage.

var _contact_timer: float = 0.0

func physics_step(summon: Summon, player: Node2D, delta: float) -> void:
	_contact_timer = maxf(0.0, _contact_timer - delta)
	var def := summon.definition
	if def == null:
		summon.velocity = Vector2.ZERO
		summon.move_and_slide()
		return
	# (a) Return to the player overrides combat.
	if player != null and is_instance_valid(player):
		var to_player: Vector2 = player.global_position - summon.global_position
		if to_player.length() > def.follow_far:
			summon.velocity = to_player.normalized() * def.speed
			summon.move_and_slide()
			return
	# (b) Engage the nearest live enemy inside aggro_range.
	var target := _nearest_enemy_in_range(summon, def.aggro_range)
	if target != null:
		var to_enemy: Vector2 = target.global_position - summon.global_position
		if to_enemy.length() > def.contact_range:
			summon.velocity = to_enemy.normalized() * def.speed
		else:
			summon.velocity = Vector2.ZERO
			if _contact_timer <= 0.0:
				target.apply_damage(DamageCalc.compute(def.contact_damage, summon.damage_modifiers, target.damage_modifiers, summon.damage_rng).amount)
				_contact_timer = def.contact_cooldown
		summon.move_and_slide()
		return
	# (c) Hold position.
	summon.velocity = Vector2.ZERO
	summon.move_and_slide()

func _nearest_enemy_in_range(summon: Summon, aggro_range: float) -> Enemy:
	var best: Enemy = null
	var best_d := aggro_range * aggro_range
	for e in summon.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.hp <= 0:
			continue
		var d := summon.global_position.distance_squared_to(enemy.global_position)
		if d <= best_d:
			best_d = d
			best = enemy
	return best
