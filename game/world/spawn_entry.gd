class_name SpawnEntry
extends Resource
## One enemy spawn, as authored in an AreaSpawnData carrier or built by a
## producer (waves, ambushes, slime splits) and handed to EnemySpawner.

## Spawn position in the area's local space.
@export var position: Vector2 = Vector2.ZERO
## The enemy scene to instantiate. An entry without one is rejected.
@export var enemy: PackedScene
## Per-kill loot table. Null leaves the enemy without one (wave bosses drop
## from their definition's table).
@export var reward_table: RewardTable
## Assigned before tree entry. Null keeps the scene's own definition.
@export var definition: EnemyDefinition
## Patrol points in the area's local space, handed to the behavior's
## configure_route after tree entry. Empty means no route.
@export var route: PackedVector2Array = PackedVector2Array()

func _init(p_position := Vector2.ZERO, p_enemy: PackedScene = null, p_reward_table: RewardTable = null, p_definition: EnemyDefinition = null, p_route := PackedVector2Array()) -> void:
	position = p_position
	enemy = p_enemy
	reward_table = p_reward_table
	definition = p_definition
	route = p_route
