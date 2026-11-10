class_name EnemyBehaviorFishyGuard
extends EnemyBehaviorFishy
## #464: the overworld Fishy. Same rod as the dungeon Fishy, but like the
## #346 entrance guards it holds its post until the player comes within
## NOTICE_RADIUS (or hits it), and walks back home once the player is more
## than LEASH_RADIUS from the post. Without this every overworld Fishy would
## walk across the whole map toward the player. PLACEHOLDER radii.

const NOTICE_RADIUS := 420.0
const LEASH_RADIUS := 800.0

func _notice_radius() -> float:
	return NOTICE_RADIUS

func _leash_radius() -> float:
	return LEASH_RADIUS
