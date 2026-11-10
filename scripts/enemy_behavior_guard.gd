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
##
## #373: this is also the base of the moving overworld roles
## (EnemyBehaviorPatrol, EnemyBehaviorMigrate). They share the aggro / leash /
## hit-to-engage logic here and only override what the enemy does while NOT
## engaged (_idle_step) and where the leash is measured from (_leash_anchor).
## A plain guard is the stationary gate-guard role: idle = stand at the post.

const AGGRO_RADIUS := 220.0
const LEASH_RADIUS := 520.0
const HOME_EPSILON := 6.0

var home := Vector2.INF
var engaged := false
var _last_hp := -1
## #373: where the current engagement started; moving roles leash from here.
var engaged_from := Vector2.INF
## #373: waypoints in global space (patrol loop / migration path). Unused by
## a stationary guard. Set by configure_route after the enemy enters the tree.
var route := PackedVector2Array()

## #391: idle-walk routing state, SEPARATE from the inherited chase helper -
## engaged chases and post/route walks never share a half-walked path.
var _walk_path := TerrainPath.new()

## #373: EnemySpawner calls this with an entry's "route" (converted to global
## space) right after the enemy enters the tree.
func configure_route(points: PackedVector2Array) -> void:
	route = points

func physics_step(enemy: Enemy, player, delta: float) -> void:
	if home == Vector2.INF:
		home = enemy.global_position
	var was_engaged := engaged
	if _last_hp >= 0 and enemy.hp < _last_hp:
		engaged = true # hit from outside aggro range: fight back
	_last_hp = enemy.hp
	var alive: bool = player != null and is_instance_valid(player) and player.hp > 0
	if alive:
		var target_pos: Vector2 = player.global_position
		if not engaged and enemy.global_position.distance_to(target_pos) <= AGGRO_RADIUS:
			engaged = true
		if engaged and not was_engaged:
			engaged_from = enemy.global_position
		if engaged and _leash_anchor().distance_to(target_pos) > _leash_radius():
			engaged = false
	else:
		engaged = false
	if engaged:
		super(enemy, player, delta)
		return
	_contact_timer = maxf(0.0, _contact_timer - delta)
	_idle_step(enemy, delta)

## Where the leash is measured from. A guard is tied to its post.
func _leash_anchor() -> Vector2:
	return home

## The give-up distance. A stationary guard keeps LEASH_RADIUS; #414
## (Daniel, 2026-11-09: "Make the chase distance larger") lets moving
## roles override this - the patroller chases much farther before giving
## up.
func _leash_radius() -> float:
	return LEASH_RADIUS

## What the enemy does while not engaged. A guard walks back to its post.
func _idle_step(enemy: Enemy, delta: float) -> void:
	_walk_to(enemy, home, enemy.speed, delta)

## Walks toward `at` at `speed` (terrain-aware). True once within HOME_EPSILON.
## #391: routes around blocking terrain through the shared TerrainPath
## helper when a grid is wired - a patrol loop or migration path that
## crosses a tree detours around it instead of stalling on it. With no grid
## (or a clear straight line) the walk is exactly as #346/#373.
func _walk_to(enemy: Enemy, at: Vector2, speed: float, delta: float) -> bool:
	var to := at - enemy.global_position
	var arrived := to.length() <= HOME_EPSILON
	# Never overshoot the point in one step (fast movers would orbit it).
	var walk := Vector2.ZERO if arrived else to.normalized() * minf(speed, to.length() / maxf(delta, 0.0001))
	enemy.velocity = _walk_path.steer(enemy.terrain, enemy.global_position, enemy.velocity, walk, at, speed, delta, enemy.can_swim)
	enemy.move_and_slide()
	return arrived
