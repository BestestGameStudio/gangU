class_name EnemyBehaviorWolf
extends EnemyBehavior
## #474 (Daniel, 2026-11-09): wolf pack hunter. Wolves spawn from overworld
## caves at night, hunt the player in a pack, and pounce: a 0.5s crouch
## telegraph, then a fast lunge that lands HEAVY damage ("heavy damage,
## 0.5s"). At daybreak their cave orders a retreat: a wolf that is NOT in a
## fight runs home and despawns into the cave; a wolf the player is
## fighting "fights back and does not retreat" - it keeps fighting until
## the fight ends, then goes home.
##
## Per-enemy instance (the Enemy instantiates its own behavior from the
## definition slot, #99). Movement weaves around trees through the shared
## TerrainPath helper (#391), same as the chase/contact behavior. The
## owning WolfCave drives the day/night state through enemy metadata:
##   "wolf_anchor"  Vector2  - the cave mouth (spawn/prowl/retreat point)
##   "wolf_cave"    WolfCave - pack bookkeeping + absorb callback
##   "wolf_index"   int      - slot in the pack (flanking offset)
##   "wolf_retreat" bool     - daybreak: go home unless engaged
## Damage, speed and ranges ride the enemy's stats (its EnemyDefinition);
## only the pounce deals damage - wolves have no plain contact hit.

## Seconds the pounce telegraph (crouch) shows before the lunge
## (Daniel: "0.5s").
const TELEGRAPH_TIME := 0.5
## Distance from the player at which the wolf starts a pounce.
const POUNCE_RANGE := 200.0
## Lunge speed and duration.
const POUNCE_SPEED := 720.0
const POUNCE_TIME := 0.24
## Cooldown between a finished pounce and the next telegraph.
const POUNCE_COOLDOWN := 1.4
## How far the wolf hunts the player on its own.
const HUNT_RANGE := 1150.0
## A packmate's fight pulls the whole pack in from this far.
const PACK_ALERT_RANGE := 1500.0
## "In a fight" for the retreat rule: the player is this close, or the
## wolf was hit within COMBAT_MEMORY seconds.
const FIGHT_RANGE := 500.0
const COMBAT_MEMORY := 3.0
## Prowl: wolves idle-wander this far around the cave mouth.
const PROWL_RADIUS := 280.0
const PROWL_SPEED := 0.45
## Arrival distance at the cave mouth on retreat (then despawn).
const RETREAT_ARRIVE := 48.0
## Recover drift after a pounce (vulnerable beat).
const RECOVER_TIME := 0.9

enum { PROWL, HUNT, TELEGRAPH, POUNCE, RECOVER, RETREAT }

var state: int = PROWL
var _cooldown: float = 0.0
var _timer: float = 0.0
var _aim: Vector2 = Vector2.RIGHT
var _pounce_hit: bool = false
var _combat_t: float = 0.0
var _last_hp: int = -1
var _wander_to: Vector2 = Vector2.INF
var _wander_t: float = 0.0
var _rng := RandomNumberGenerator.new()
## #391: per-state routing state, never shared (same idiom as the guard's
## separate idle/chase helpers).
var _hunt_path := TerrainPath.new()
var _walk_path := TerrainPath.new()

func _init() -> void:
	_rng.randomize()

func physics_step(enemy: Enemy, player, delta: float) -> void:
	if _last_hp >= 0 and enemy.hp < _last_hp:
		_combat_t = COMBAT_MEMORY # hit: fight back, cancel any retreat
		if state == RETREAT:
			state = HUNT
	_last_hp = enemy.hp
	_combat_t = maxf(0.0, _combat_t - delta)
	_cooldown = maxf(0.0, _cooldown - delta)

	var alive: bool = player != null and is_instance_valid(player) and player.hp > 0
	var dist: float = enemy.global_position.distance_to(player.global_position) if alive else INF
	var engaged: bool = alive and (_combat_t > 0.0 or dist <= FIGHT_RANGE)

	# Report combat so the cave raises the pack alert (pack hunt).
	if engaged and (state == HUNT or state == TELEGRAPH or state == POUNCE):
		var cave := _cave_of(enemy)
		if cave != null and cave.has_method("notify_engaged"):
			cave.notify_engaged(enemy)

	# Daybreak order from the cave: go home unless in a fight.
	if state != RETREAT and state != TELEGRAPH and state != POUNCE \
			and enemy.has_meta("wolf_retreat") and enemy.get_meta("wolf_retreat") and not engaged:
		state = RETREAT

	match state:
		PROWL:
			_step_prowl(enemy, player, alive, dist, delta)
		HUNT:
			_step_hunt(enemy, player, alive, dist, delta)
		TELEGRAPH:
			_step_telegraph(enemy, delta)
		POUNCE:
			_step_pounce(enemy, player, alive, delta)
		RECOVER:
			_step_recover(enemy, player, alive, delta)
		RETREAT:
			_step_retreat(enemy, delta)

func _step_prowl(enemy: Enemy, player, alive: bool, dist: float, delta: float) -> void:
	if alive and (dist <= HUNT_RANGE or _pack_alert(enemy, dist)):
		state = HUNT
		return
	# Loiter around the cave mouth so the pack reads as a group.
	_wander_t -= delta
	var anchor := _anchor_of(enemy)
	if _wander_to == Vector2.INF or _wander_t <= 0.0:
		_wander_to = anchor + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(40.0, PROWL_RADIUS)
		_wander_t = _rng.randf_range(1.6, 3.2)
	_walk(enemy, _wander_to, enemy.speed * PROWL_SPEED, delta)

func _step_hunt(enemy: Enemy, player, alive: bool, dist: float, delta: float) -> void:
	if not alive or (dist > HUNT_RANGE and _combat_t <= 0.0 and not _pack_alert(enemy, dist)):
		state = PROWL
		return
	if dist <= POUNCE_RANGE and _cooldown <= 0.0:
		# Lock the aim NOW: the 0.5s crouch shows where the lunge goes and
		# a moving player can dodge it.
		state = TELEGRAPH
		_timer = TELEGRAPH_TIME
		_aim = (player.global_position - enemy.global_position).normalized()
		_pounce_hit = false
		enemy.velocity = Vector2.ZERO
		enemy.move_and_slide()
		enemy.play_action(&"telegraph", true)
		if enemy.sprite != null:
			enemy.sprite.set_glow(true)
		return
	# Chase with a per-wolf flanking offset so the pack surrounds instead
	# of stacking on one point.
	var idx := _index_of(enemy)
	var flank := Vector2.from_angle(TAU * idx / 6.0) * minf(90.0, dist * 0.4)
	var goal: Vector2 = player.global_position + flank
	if dist < 130.0:
		goal = player.global_position
	var chase := (goal - enemy.global_position).normalized() * enemy.speed
	enemy.velocity = _hunt_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, chase, goal, enemy.speed, delta, enemy.can_swim)
	enemy.move_and_slide()

func _step_telegraph(enemy: Enemy, delta: float) -> void:
	enemy.velocity = Vector2.ZERO
	enemy.move_and_slide()
	_timer -= delta
	if _timer <= 0.0:
		state = POUNCE
		_timer = POUNCE_TIME
		enemy.play_action(&"pounce", true)
		if enemy.sprite != null:
			enemy.sprite.set_glow(false)

func _step_pounce(enemy: Enemy, player, alive: bool, delta: float) -> void:
	_timer -= delta
	enemy.velocity = _aim * POUNCE_SPEED
	enemy.terrain_move_and_slide() # #396 seam: the lunge stops at trees
	if alive and not _pounce_hit \
			and enemy.global_position.distance_to(player.global_position) <= enemy.contact_range:
		_pounce_hit = true
		var hit := DamageCalc.compute(enemy.contact_damage, enemy.damage_modifiers, player.damage_modifiers, enemy.damage_rng)
		var receipt := OnHit.begin(player)
		player.apply_damage(hit.amount)
		OnHit.end(receipt, player)
		OnHit.report(enemy, null, player, hit, OnHit.DELIVERY_CONTACT, receipt) # #390
	if _timer <= 0.0 or _pounce_hit:
		state = RECOVER
		_timer = RECOVER_TIME
		_cooldown = POUNCE_COOLDOWN
		enemy.clear_action()

func _step_recover(enemy: Enemy, player, alive: bool, delta: float) -> void:
	_timer -= delta
	var drift := Vector2.ZERO
	if alive:
		drift = (player.global_position - enemy.global_position).normalized() * enemy.speed * 0.2
	enemy.velocity = _walk_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, drift, enemy.global_position + drift, enemy.speed, delta, enemy.can_swim)
	enemy.move_and_slide()
	if _timer <= 0.0:
		state = HUNT if alive else PROWL

func _step_retreat(enemy: Enemy, delta: float) -> void:
	var anchor := _anchor_of(enemy)
	if _walk(enemy, anchor, enemy.speed, delta):
		var cave := _cave_of(enemy)
		if cave != null and cave.has_method("absorb_wolf"):
			cave.absorb_wolf(enemy)
		else:
			enemy.queue_free()

## Terrain-aware walk toward `at`; true once within the arrival epsilon.
func _walk(enemy: Enemy, at: Vector2, speed: float, delta: float) -> bool:
	var to := at - enemy.global_position
	var arrived := to.length() <= RETREAT_ARRIVE * 0.5
	var walk := Vector2.ZERO if arrived else to.normalized() * minf(speed, to.length() / maxf(delta, 0.0001))
	enemy.velocity = _walk_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, walk, at, speed, delta, enemy.can_swim)
	enemy.move_and_slide()
	return arrived

## Pack hunt: the cave reports a packmate in combat; converge from afar.
func _pack_alert(enemy: Enemy, dist: float) -> bool:
	if dist > PACK_ALERT_RANGE:
		return false
	var cave := _cave_of(enemy)
	return cave != null and cave.has_method("pack_alert_active") and cave.pack_alert_active()

## Meta reads are has_meta-guarded: in 4.5 even the two-arg get_meta
## ERR_PRINTs on a missing key, and fixture wolves carry no cave meta.
func _cave_of(enemy: Enemy) -> Object:
	if not enemy.has_meta("wolf_cave"):
		return null
	var cave: Object = enemy.get_meta("wolf_cave")
	return cave if cave != null and is_instance_valid(cave) else null

func _anchor_of(enemy: Enemy) -> Vector2:
	return enemy.get_meta("wolf_anchor") if enemy.has_meta("wolf_anchor") else enemy.global_position

func _index_of(enemy: Enemy) -> int:
	return enemy.get_meta("wolf_index") if enemy.has_meta("wolf_index") else 0

## Harness introspection: state name for test assertions.
func state_name() -> String:
	return ["PROWL", "HUNT", "TELEGRAPH", "POUNCE", "RECOVER", "RETREAT"][state]
