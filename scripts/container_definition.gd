class_name ContainerDefinition
extends Resource
## #214: data-driven destroyable-container config, mirroring the
## EnemyDefinition/SummonDefinition idiom - stats live HERE, never hardcoded
## in destroyable_container.gd. The max_hp default is a TEST-FIXTURE value:
## production HP, loot contents, weights, art and placements are the deferred
## content phase (human-open, issue #214 "Open - not decided, do not invent").

@export var max_hp: int = 10
## Optional loot table rolled on destruction. Null = no drop: a container CAN
## have a loot table (Daniel's #214 request), it is not required to.
@export var reward_table: RewardTable
## Placeholder body color until real container art lands (content phase).
@export var body_color: Color = Color(0.6, 0.45, 0.25)
