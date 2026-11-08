class_name EnemySpawner
extends Node
## #220: enemy spawner foundation (one per mounted area).
##
## FOUNDATION ONLY. It gives later spawn controls (waves, timers, caps,
## triggers, budgets) a single place to hook in without touching the mount
## code. No concrete policy ships here: the default behavior is identical to
## the old mount-everything-once flow.
##
## - request_spawn(entry) is the ONE instantiate + wire + parent point.
## - spawn_initial() requests every entry once (called once per area mount).
## - should_spawn(entry) is the policy seam, default true. Later controls
##   override it (same role as SummonManager.effective_cap).
## - Bookkeeping: spawned / spawn_died signals and alive_count(entry).
##
## Entry format is the AreaSpawnData one ("position", "enemy",
## "reward_table"); unknown extra keys are tolerated and ignored.

signal spawned(enemy: Enemy, entry: Dictionary)
signal spawn_died(enemy: Enemy, entry: Dictionary)

var entries: Array = []
var player_path: NodePath = NodePath("../../Player")
var terrain: TerrainMap = null
var parent_area: Node = null

## alive spawns per entry: entry index -> Array of Enemy
var _alive: Dictionary = {}

func setup(p_entries: Array, p_player_path: NodePath, p_terrain: TerrainMap, p_parent_area: Node) -> void:
	entries = p_entries
	player_path = p_player_path
	terrain = p_terrain
	parent_area = p_parent_area

## Policy seam. Default: always allow. Override (or replace the script) to
## add caps, timers, triggers, budgets later.
func should_spawn(_entry: Dictionary) -> bool:
	return true

func spawn_initial() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for entry: Dictionary in entries:
		var e := request_spawn(entry)
		if e != null:
			out.append(e)
	return out

## The one spawn path. Returns null when the policy refuses.
## Wiring is lifted unchanged from the old Main._mount_area_spawns:
## player_path is assigned BEFORE add_child so Enemy._ready resolves it, the
## terrain comes from the area, and the enemy is parented to the area so a
## gate swap frees it.
func request_spawn(entry: Dictionary) -> Enemy:
	if not should_spawn(entry):
		return null
	var enemy_scene := entry["enemy"] as PackedScene
	var e := enemy_scene.instantiate() as Enemy
	e.position = entry["position"] as Vector2
	e.reward_table = entry["reward_table"] as RewardTable
	e.player_path = player_path
	e.terrain = terrain
	var idx := entries.find(entry)
	if not _alive.has(idx):
		_alive[idx] = []
	(_alive[idx] as Array).append(e)
	e.died.connect(_on_enemy_died.bind(e, entry, idx))
	parent_area.add_child(e)
	spawned.emit(e, entry)
	return e

func alive_count(entry: Dictionary) -> int:
	var idx := entries.find(entry)
	if not _alive.has(idx):
		return 0
	var n := 0
	for e in _alive[idx]:
		if is_instance_valid(e):
			n += 1
	return n

func total_alive() -> int:
	var n := 0
	for idx in _alive:
		for e in _alive[idx]:
			if is_instance_valid(e):
				n += 1
	return n

func _on_enemy_died(e: Enemy, entry: Dictionary, idx: int) -> void:
	if _alive.has(idx):
		(_alive[idx] as Array).erase(e)
	spawn_died.emit(e, entry)
