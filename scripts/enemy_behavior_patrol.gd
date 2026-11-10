class_name EnemyBehaviorPatrol
extends EnemyBehaviorGuard
## #373: overworld patrol. Walks a short CLOSED loop of waypoints (the
## spawn entry's "route") around its beat, pausing briefly at each corner.
## Aggro, hit-to-engage and chase are the guard's (#346); the leash is
## measured from where the engagement started.
##
## #414 (Daniel, 2026-11-09: "Patrollers should drop their route and
## follow the player using the cover mechanic. Make the chase distance
## larger"): while engaged the patroller leaves its loop and follows the
## player with the shared chase (cover-seeking for opted-in moustache men,
## #406) out to the larger PATROL_LEASH_RADIUS (Daniel-approved 900).
## After giving up it RETURNS TO ITS OLD ROUTE (Daniel, same thread:
## "return to its old route") - it walks back onto the loop at the
## waypoint it was heading for, exactly as #373. Without a route it
## degrades to a stationary guard.
## Numbers other than PATROL_LEASH_RADIUS are provisional implementation
## choices, not approved balance.

## Fraction of enemy.speed used while strolling the loop.
const STROLL := 0.45
## Seconds spent at each waypoint before heading to the next.
const PAUSE := 0.8
## #414: the patroller give-up distance (Daniel-approved; the guard's
## post leash stays 520).
const PATROL_LEASH_RADIUS := 900.0
## #463 (Daniel, 2026-11-09: "increase the chase radius of the mustache
## men so that they continue chasing the player while they're still
## visible on screen"; bigger fixed number; basic mustache men only): the
## give-up distance for the basic mustache men - the Mustache Warrior
## scene (scenes/enemy.tscn), the patroller that opts into cover_seek
## (#406). 1350 px clears the 1152x648 viewport diagonal (~1322), so an
## engaged mustache man keeps chasing while the player is still on
## screen. Other patrollers (the slime) keep PATROL_LEASH_RADIUS.
const MUSTACHE_LEASH_RADIUS := 1350.0

var waypoint := 0
var _pause := 0.0

func _leash_radius(enemy: Enemy) -> float:
	if enemy.cover_seek:
		return MUSTACHE_LEASH_RADIUS
	return PATROL_LEASH_RADIUS

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
