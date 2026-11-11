class_name OverworldEventContext
extends RefCounted
## #365: what an OverworldEvent gets when its LocationTrigger fires.
##
## Built by Main for each fire. It hands the event the live nodes and one
## spawn helper, so events never reach into Main's internals.

var area: Node = null
var trigger: LocationTrigger = null
var player: Player = null
## Main (or any host); null in isolated tests.
var host: Node = null
## How many times this trigger id fired this run, this fire included.
var run_fire_count := 0

var _spawner: EnemySpawner = null

## Spawns SpawnEntry resources (position in the area's local space) through
## the area's event EnemySpawner (#220 seam), created on first use and parented to the
## area so leaving it frees the spawner and its enemies.
func spawn(entries: Array[SpawnEntry]) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if area == null or entries.is_empty():
		return out
	var spawner := _event_spawner()
	for entry: SpawnEntry in entries:
		spawner.entries.append(entry)
		var e := spawner.request_spawn(entry)
		if e != null:
			out.append(e)
	return out

func _event_spawner() -> EnemySpawner:
	if _spawner != null and is_instance_valid(_spawner):
		return _spawner
	_spawner = area.get_node_or_null("EventSpawner") as EnemySpawner
	if _spawner == null:
		_spawner = EnemySpawner.new()
		_spawner.name = "EventSpawner"
		area.add_child(_spawner)
		# Enemy.player_path resolves from the enemy, a direct area child.
		var path := NodePath("../../Player")
		if player != null and player.is_inside_tree():
			path = NodePath("../" + str(area.get_path_to(player)))
		_spawner.setup([], path, area.get_node_or_null("Terrain") as TerrainMap, area)
	return _spawner
