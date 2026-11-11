class_name SpawnEntry
extends Resource
## #518: typed construction data at the Dictionary spawn boundary.
## The original Dictionary stays with policy, routes, signals and identity
## bookkeeping. Unknown keys and unsupported optional definitions retain the
## old compatibility behavior; required construction fields are validated.

@export var position: Vector2 = Vector2.ZERO
@export var enemy: PackedScene
@export var reward_table: RewardTable
@export var definition: EnemyDefinition

## A strict, read-only adapter. Never duplicates or mutates the source entry:
## two equal Dictionary instances must keep separate alive-count buckets.
static func from_dictionary(entry: Dictionary) -> SpawnEntry:
	if not entry.has("position") or not entry["position"] is Vector2:
		push_error("SpawnEntry: position must be a Vector2.")
		return null
	if not entry.has("enemy") or not entry["enemy"] is PackedScene:
		push_error("SpawnEntry: enemy must be a PackedScene.")
		return null
	if not entry.has("reward_table"):
		push_error("SpawnEntry: reward_table is required (null is allowed).")
		return null
	var table: Variant = entry["reward_table"]
	if table != null and not table is RewardTable:
		push_error("SpawnEntry: reward_table must be a RewardTable or null.")
		return null
	var out := SpawnEntry.new()
	out.position = entry["position"]
	out.enemy = entry["enemy"]
	out.reward_table = table
	# Existing callers only apply a correctly typed optional definition.
	if entry.get("definition") is EnemyDefinition:
		out.definition = entry["definition"]
	return out
