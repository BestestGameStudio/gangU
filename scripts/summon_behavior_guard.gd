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
## #281 (Daniel, 2026-11-08): "summons should pathfind around terrain not
## walk through it". Movement requests route through the TerrainMap lookup
## seam (world_to_cell/cell_to_world/is_walkable_at - read-only): a clear
## straight line steers direct, a blocked line triggers a bounded 4-dir A*
## over the walkability grid, replanned on a short timer because the target
## moves. TerrainMotion.resolve still shapes the final velocity (speed
## multiplier/friction/wall cancel), so corner cells can never be entered.
## summon.terrain == null (harnesses without a Terrain node) behaves exactly
## as #280 - no lookup, no pathfinding.
## #391: the routing itself now lives in the shared TerrainPath helper
## so enemies can share its obstacle routing. Summons opt into routing
## around all unwalkable cells (including water), preserving #281.
##
## Contract:
##   (a) ENGAGE FIRST - while any live enemy exists, chase the nearest one at
##       ANY distance to contact_range (pathfinding around terrain when a
##       terrain grid is wired), then apply contact_damage with
##       contact_cooldown between hits through the one DamageCalc path. The
##       timer lives on this per-summon instance and is never shared
##       (EnemyBehaviorChaseContact idiom).
##   (b) RETURN - with NO live enemies, when the player is beyond follow_far,
##       move toward the player ("will follow if you get too far"), with the
##       same terrain routing.
##   (c) Otherwise hold position ("stays at a distance from you").
##
## Taunt is NOT implemented here: enemies retarget through enemy.gd's
## _resolve_target (the #212 local taunt_range gate; bosses are structurally
## player-only). This script only moves the summon and deals damage.

var _contact_timer: float = 0.0

## #281/#391: per-summon routing state (never shared), one helper per
## behavior instance - the EnemyBehaviorChaseContact idiom.
var _terrain_path := TerrainPath.new()

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
			summon.velocity = _steer_toward(summon, target.global_position, def.speed, delta)
		else:
			summon.velocity = Vector2.ZERO
			if _contact_timer <= 0.0:
				var hit := DamageCalc.compute(def.contact_damage, summon.damage_modifiers, target.damage_modifiers, summon.damage_rng)
				var receipt := OnHit.begin(target)
				target.apply_damage(hit.amount, hit.crit_tier) # #208: tier colors the number
				OnHit.end(receipt, target)
				OnHit.report(summon, null, target, hit, OnHit.DELIVERY_CONTACT, receipt) # #390
				_contact_timer = def.contact_cooldown
		summon.move_and_slide()
		_hit_blocking_barricade(summon, def)
		return
	# (b) RETURN - no live enemies: follow a too-far player.
	if player != null and is_instance_valid(player):
		var to_player: Vector2 = player.global_position - summon.global_position
		if to_player.length() > def.follow_far:
			summon.velocity = _steer_toward(summon, player.global_position, def.speed, delta)
			summon.move_and_slide()
			return
	# (c) Hold position.
	summon.velocity = Vector2.ZERO
	summon.move_and_slide()

## #420: a player-owned summon pressed against a barricade on its way to an
## enemy hits the barricade with its contact attack (barricades take any
## player-sourced damage). Shares the contact cooldown with enemy hits.
func _hit_blocking_barricade(summon: Summon, def: SummonDefinition) -> void:
	if _contact_timer > 0.0 or not Barricade.is_player_side(summon):
		return
	for i in summon.get_slide_collision_count():
		var b := summon.get_slide_collision(i).get_collider() as Barricade
		if b == null or not is_instance_valid(b) or b.hp <= 0:
			continue
		var hit := DamageCalc.compute(def.contact_damage, summon.damage_modifiers, null, summon.damage_rng)
		var receipt := OnHit.begin(b)
		b.apply_damage(hit.amount, hit.crit_tier)
		OnHit.end(receipt, b)
		OnHit.report(summon, null, b, hit, OnHit.DELIVERY_CONTACT, receipt)
		_contact_timer = def.contact_cooldown
		return

# #280: no range gate - the nearest live enemy anywhere is the target.
func _nearest_enemy(summon: Summon) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in summon.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.hp <= 0:
			continue
		# #461: an enemy hidden in tall grass is not a target.
		if not TallGrass.can_see(summon.terrain, summon.global_position, enemy.global_position):
			continue
		var d := summon.global_position.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best

## #281: desired velocity toward dest, routed around unwalkable terrain when
## a grid is wired; #391 moved the routing to the shared TerrainPath helper.
func _steer_toward(summon: Summon, dest: Vector2, speed: float, delta: float) -> Vector2:
	var desired: Vector2 = (dest - summon.global_position).normalized() * speed
	return _terrain_path.steer(summon.terrain, summon.global_position, summon.velocity, desired, dest, speed, delta, false, true)
