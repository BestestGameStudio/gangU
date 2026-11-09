class_name EnemyBehaviorPatrol
extends EnemyBehaviorGuard
## #373: overworld patrol. Walks a short CLOSED loop of waypoints (the
## spawn entry's "route") around its beat, pausing briefly at each corner,
## forever. Aggro, hit-to-engage and chase are the guard's (#346); the leash
## is measured from where the engagement started, and after giving up the
## patroller walks back onto its loop at the waypoint it was heading for.
## Without a route it degrades to a stationary guard.
## Numbers are provisional implementation choices, not approved balance.

## Fraction of enemy.speed used while strolling the loop.
const STROLL := 0.45
## Seconds spent at each waypoint before heading to the next.
const PAUSE := 0.8

var waypoint := 0
var _pause := 0.0

func _leash_anchor() -> Vector2:
	return engaged_from if engaged_from != Vector2.INF else home

func _idle_step(enemy: Enemy, delta: float) -> void:
	if route.is_empty():
		super(enemy, delta)
		return
	if _pause > 0.0:
		_pause -= delta
		_walk_to(enemy, enemy.global_position, 0.0, delta)
		return
	if _walk_to(enemy, route[waypoint], enemy.speed * STROLL, delta):
		waypoint = (waypoint + 1) % route.size()
		_pause = PAUSE
