class_name SummonBehaviorGuard
extends RefCounted
## #212: the first concrete summon behavior - the guard ally cast by the
## summon spell. Behavior per Daniel (2026-11-08): "taunts and attacks
## enemies close range. Stays at a distance from you but will follow if you
## get too far"; starting balance 30 HP / 5 melee per 0.8s / no expiry,
## tuned after the demo. Stats live on SummonDefinition, never hardcoded here.
## #280 (Daniel, 2026-11-08): "pathfind towards closest enemies ... even if
## the enemy is outside the range" so the blocks stop trailing the player at
## max distance - ENGAGEMENT IS NOW THE TOP PRIORITY and aggro_range no
## longer gates target selection (the field stays on SummonDefinition as
## inert data for later tuning).
##
## Contract:
##   (a) ENGAGE FIRST - while any live enemy exists, chase the nearest one at
##       ANY distance to contact_range, then apply contact_damage with
##       contact_cooldown between hits through the one DamageCalc path. The
##       timer lives on this per-summon instance and is never shared
##       (EnemyBehaviorChaseContact idiom).
##   (b) RETURN - with NO live enemies, when the player is beyond follow_far,
##       move toward the player ("will follow if you get too far").
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
	# (a) ENGAGE FIRST (#280): chase the nearest live enemy at ANY distance,
	# so the summon never trails the player at max distance while enemies live.
	var target := _nearest_enemy(summon)
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
	# (b) RETURN - no live enemies: follow a too-far player.
	if player != null and is_instance_valid(player):
		var to_player: Vector2 = player.global_position - summon.global_position
		if to_player.length() > def.follow_far:
			summon.velocity = to_player.normalized() * def.speed
			summon.move_and_slide()
			return
	# (c) Hold position.
	summon.velocity = Vector2.ZERO
	summon.move_and_slide()

# #280: no range gate - the nearest live enemy anywhere is the target.
func _nearest_enemy(summon: Summon) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in summon.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.hp <= 0:
			continue
		var d := summon.global_position.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best
