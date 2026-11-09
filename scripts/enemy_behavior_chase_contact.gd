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
##
## #391 (Daniel, 2026-11-09: "enemies can pathfind around trees"): when a
## terrain grid is wired, the chase routes around blocking terrain through
## the shared TerrainPath helper (the #281 summon routing, extracted): a
## clear straight line steers exactly as before, a blocked line follows a
## bounded A* detour. enemy.terrain == null behaves exactly as #99.

var _contact_timer: float = 0.0
## #391: per-enemy routing state (never shared), one helper per behavior
## instance - the same idiom as the cooldown timer.
var _terrain_path := TerrainPath.new()

## #209: target parameter widened (Player -> duck-typed) so the default
## chase/contact behavior can target Summons; the target contract used here
## is hp, global_position, damage_modifiers and apply_damage, which both
## Player and Summon provide.
func physics_step(enemy: Enemy, player, delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.hp <= 0:
		enemy.velocity = Vector2.ZERO
		_slide(enemy)
		return
	var to_player: Vector2 = player.global_position - enemy.global_position
	# #337: a target with a contact_radius (DefenseCore) is hit at its rim.
	# Player/Summon have none, so pad stays 0 and nothing changes for them.
	var pad: float = 0.0
	if player is DefenseCore:
		pad = player.contact_radius
	# #367: an enemy with a FlowNav (maze defense) steers along the grid path
	# instead of straight at the target; range checks still use the target.
	# #391: a nav-less enemy instead routes around terrain obstacles (trees)
	# through TerrainPath's bounded A* detour; both paths end in
	# TerrainMotion.resolve, so terrain semantics are identical either way.
	var heading: Vector2 = to_player
	if enemy.nav != null:
		heading = enemy.nav.waypoint(enemy.global_position, player.global_position) - enemy.global_position
	var chase: Vector2 = heading.normalized() * enemy.speed if to_player.length() > 8.0 + pad else Vector2.ZERO
	if enemy.nav != null:
		enemy.velocity = TerrainMotion.resolve(enemy.terrain, enemy.global_position, enemy.velocity, chase, delta, enemy.can_swim)
	else:
		enemy.velocity = _terrain_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, chase, player.global_position, enemy.speed, delta, enemy.can_swim)
	_slide(enemy)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	if to_player.length() <= enemy.contact_range + pad and _contact_timer <= 0.0:
		var hit := DamageCalc.compute(enemy.contact_damage, enemy.damage_modifiers, player.damage_modifiers, enemy.damage_rng)
		var receipt := OnHit.begin(player)
		player.apply_damage(hit.amount)
		OnHit.end(receipt, player)
		OnHit.report(enemy, null, player, hit, OnHit.DELIVERY_CONTACT, receipt) # #390
		_contact_timer = enemy.contact_cooldown
		enemy.play_action(&"attack") # #177: visual swing only

## move_and_slide, plus (#367, nav enemies only) a terrain clamp on the result.
## TerrainMotion.resolve only vets the requested velocity. When a crowding
## peer overlaps this body, the physics recovery step pushes it out in a
## direction nobody checked, even at zero velocity. In the maze that push
## carried enemies into OBSTACLE cells, which are terrain, not colliders, and
## left them stuck there (seed 22, crowded waves). Clamping the frame's
## displacement with the same seam pushes use keeps a nav enemy on walkable
## cells. Nav-less enemies keep the plain move_and_slide they had before.
static func _slide(enemy: Enemy) -> void:
	if enemy.nav == null:
		enemy.move_and_slide()
		return
	var before := enemy.global_position
	enemy.move_and_slide()
	enemy.global_position = TerrainMotion.clamp_displacement(enemy.terrain, before, enemy.global_position, enemy.can_swim)
