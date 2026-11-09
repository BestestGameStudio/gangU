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
## "reward_table"); an optional "definition" (EnemyDefinition, #346) is
## assigned before tree entry; an optional "route" (#373) is handed to the
## behavior after tree entry; other unknown keys are tolerated and ignored.

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
	# #346: optional per-entry definition (stats + behavior slot), assigned
	# before tree entry so Enemy._ready applies it.
	if entry.get("definition") is EnemyDefinition:
		e.definition = entry["definition"]
	e.player_path = player_path
	e.terrain = terrain
	var idx := _entry_index(entry)
	if not _alive.has(idx):
		_alive[idx] = []
	(_alive[idx] as Array).append(e)
	e.died.connect(_on_enemy_died.bind(e, entry, idx))
	parent_area.add_child(e)
	_apply_route(e, entry)
	spawned.emit(e, entry)
	return e

## #373: an optional "route" (Array/PackedVector2Array of points in the
## area's local space) is handed to the behavior AFTER tree entry (the
## behavior is created in Enemy._ready), converted to global space. Behaviors
## without configure_route ignore it.
func _apply_route(e: Enemy, entry: Dictionary) -> void:
	if not entry.has("route") or e._behavior == null or not e._behavior.has_method("configure_route"):
		return
	var pts := PackedVector2Array()
	var area_2d := parent_area as Node2D
	for p in entry["route"]:
		pts.append(area_2d.to_global(p) if area_2d != null else p)
	e._behavior.configure_route(pts)

## Index of this exact entry Dictionary (identity, not content), so two
## entries with identical content keep separate bookkeeping. -1 = an entry
## that is not in `entries` (one shared bucket).
func _entry_index(entry: Dictionary) -> int:
	for i in entries.size():
		if is_same(entries[i], entry):
			return i
	return -1

func alive_count(entry: Dictionary) -> int:
	var idx := _entry_index(entry)
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
