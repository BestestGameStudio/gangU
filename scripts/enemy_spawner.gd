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

## Typed construction options shared by independent spawn owners. Tree entry,
## policy, signals and owner bookkeeping stay with each caller.
class SpawnOptions extends RefCounted:
	var wire_enemy: bool = false
	var player_path: NodePath = NodePath("")
	var terrain: TerrainMap = null
	var reward_table: RewardTable = null
	var definition: EnemyDefinition = null
	var context: RefCounted = null

## Single construction/wiring seam. Deliberately does not add to the tree:
## callers preserve their existing immediate/deferred entry and ready order.
## Non-Enemy fixture bosses retain their original Node/Node2D contract.
static func spawn(scene: PackedScene, pos: Vector2, opts: SpawnOptions) -> Node:
	var node := scene.instantiate()
	if node is Node2D:
		node.position = pos
	if node is Enemy:
		if opts.wire_enemy:
			node.player_path = opts.player_path
			node.terrain = opts.terrain
			node.reward_table = opts.reward_table
		if opts.definition != null:
			node.definition = opts.definition
		if opts.context != null:
			node.context = opts.context
	return node

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
	var e := _prepare_spawn(entry)
	if e == null:
		return null
	parent_area.add_child(e)
	_apply_route(e, entry)
	spawned.emit(e, entry)
	return e

## #392: deferred tree-entry variant of request_spawn for spawns requested
## from inside a death (EnemySlime split), where a synchronous add_child is
## unsafe (D14). Same policy, wiring, bookkeeping and signals as
## request_spawn; only the tree entry, route hand-off and `spawned` emission
## move to the idle frame. Descendants of splitting enemies go through here,
## so should_spawn governs them and the counters/signals never miss them.
func request_spawn_deferred(entry: Dictionary) -> Enemy:
	var e := _prepare_spawn(entry)
	if e == null:
		return null
	call_deferred("_finish_spawn", e, entry)
	return e

## Shared policy + instantiate + wiring + bookkeeping for both spawn paths.
## No tree mutation here, so it is safe inside a physics/death callback.
func _prepare_spawn(entry: Dictionary) -> Enemy:
	if not should_spawn(entry):
		return null
	var data := SpawnEntry.from_dictionary(entry)
	if data == null:
		return null
	var opts := SpawnOptions.new()
	opts.wire_enemy = true
	opts.player_path = player_path
	opts.terrain = terrain
	opts.reward_table = data.reward_table
	opts.definition = data.definition
	var e := spawn(data.enemy, data.position, opts) as Enemy
	var idx := _entry_index(entry)
	if not _alive.has(idx):
		_alive[idx] = []
	(_alive[idx] as Array).append(e)
	e.died.connect(_on_enemy_died.bind(e, entry, idx))
	# #392: splitting enemies (EnemySlime) route their death-spawned
	# descendants back through this spawner's policy/bookkeeping seam.
	if "spawner" in e:
		e.set("spawner", self)
	return e

func _finish_spawn(e: Enemy, entry: Dictionary) -> void:
	if not is_instance_valid(e) or parent_area == null:
		return
	parent_area.add_child(e)
	_apply_route(e, entry)
	spawned.emit(e, entry)

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
