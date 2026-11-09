class_name EnemyBehaviorMigrate
extends EnemyBehaviorGuard
## #373: overworld migrant. Unlike a patrol (a short loop around one beat),
## a migrant travels a long OPEN path (the spawn entry's "route") across the
## overworld from one end to the other, rests at the destination, then
## migrates back the way it came - a slow back-and-forth between two distant
## regions, not tied to any entrance. Aggro, hit-to-engage and chase are the
## guard's (#346); the leash is measured from where the engagement started,
## and after giving up the migrant resumes its journey where it left off.
## Without a route it degrades to a stationary guard.
## Numbers are provisional implementation choices, not approved balance.

## Fraction of enemy.speed used while travelling.
const TRAVEL := 0.55
## Seconds spent resting at either end of the path before turning around.
const REST := 6.0

var waypoint := 0
## +1 = outbound (toward the last point), -1 = homebound.
var direction := 1
var resting := false
var _rest := 0.0

func _leash_anchor() -> Vector2:
	return engaged_from if engaged_from != Vector2.INF else home

func _idle_step(enemy: Enemy, delta: float) -> void:
	if route.is_empty():
		super(enemy, delta)
		return
	if _rest > 0.0:
		_rest -= delta
		_walk_to(enemy, enemy.global_position, 0.0, delta)
		return
	resting = false
	if not _walk_to(enemy, route[waypoint], enemy.speed * TRAVEL, delta):
		return
	var next := waypoint + direction
	if next < 0 or next >= route.size():
		# Reached the destination: rest, then head back the other way.
		direction = -direction
		next = waypoint + direction
		resting = true
		_rest = REST
	waypoint = clampi(next, 0, route.size() - 1)
