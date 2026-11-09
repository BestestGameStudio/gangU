class_name FlowNav
extends Node
## #367: grid pathfinding over a TerrainMap for enemies that must find their
## way through walls (the maze defense mission). OPT-IN: an Enemy only uses
## it when its `nav` is set, so every other enemy and mission keeps the
## straight-line chase it had before.
##
## One BFS distance field per goal cell (4-neighbourhood, same rule as
## TerrainNav, so it never asks for a diagonal the #328 corner rule would
## refuse), shared by every enemy heading to that cell. A static goal such
## as the DefenseCore costs one BFS for the whole mission; a moving goal
## (the player) costs one BFS each time it enters a new cell. Fields are
## dropped whenever the map changes a cell.
##
## Steering: from cell A the mover aims at the centre of the neighbour cell
## B one step closer to the goal. Two edge-adjacent cells form a rectangle,
## so the straight line to B's centre never leaves A or B and never clips a
## wall. In the goal cell (or one step from it) the mover aims at the real
## target position instead.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Old fields kept for moving goals before the cache is flushed.
const MAX_FIELDS := 8
var map: TerrainMap = null:
	set = set_map
## Cells the search may visit. An empty rect means unbounded, which is only
## safe on an enclosed map (the BFS stops at max_cells either way).
var bounds: Rect2i = Rect2i()
var max_cells: int = 65536

var _fields: Dictionary = {} ## goal cell -> {cell: steps to goal}
var builds: int = 0 ## BFS runs so far (harness introspection)

func set_map(value: TerrainMap) -> void:
	if map != null and is_instance_valid(map):
		if map.cell_destroyed.is_connected(_on_cell_changed):
			map.cell_destroyed.disconnect(_on_cell_changed)
		if map.cell_interacted.is_connected(_on_cell_interacted):
			map.cell_interacted.disconnect(_on_cell_interacted)
	map = value
	_fields.clear()
	if map != null:
		map.cell_destroyed.connect(_on_cell_changed)
		map.cell_interacted.connect(_on_cell_interacted)

## Call after writing cells without the destroy/interact signals.
func invalidate() -> void:
	_fields.clear()

## Where a mover at `from` should head next to reach `to`. Falls back to `to`
## itself (the old straight chase) when there is no map, the mover is off
## the searched area, or no path exists.
func waypoint(from: Vector2, to: Vector2) -> Vector2:
	if map == null:
		return to
	var a := map.world_to_cell(from)
	var goal := map.world_to_cell(to)
	if a == goal:
		return to
	var dist := field(goal)
	if not dist.has(a):
		# Recovery: a mover off the field (inside a wall after the map changed
		# under it, say) steps out into the best edge-adjacent field cell.
		# TerrainMotion lets a mover leave a cell it could not enter, so this
		# is a legal move. With no such neighbour, fall back to the target.
		var out := a
		var out_d := -1
		for d in DIRS:
			var c := a + d
			if dist.has(c) and (out_d < 0 or int(dist[c]) < out_d):
				out = c
				out_d = dist[c]
		return to if out == a else map.cell_to_world(out)
	var n := next_cell(a, goal)
	if n == a or n == goal:
		return to
	return map.cell_to_world(n)

## The neighbour of `cell` one step closer to `goal`, or `cell` itself when
## `cell` is the goal, unreachable, or outside the field.
func next_cell(cell: Vector2i, goal: Vector2i) -> Vector2i:
	var dist := field(goal)
	if not dist.has(cell):
		return cell
	var best := cell
	var best_d: int = dist[cell]
	for d in DIRS:
		var n := cell + d
		if dist.has(n) and int(dist[n]) < best_d:
			best_d = dist[n]
			best = n
	return best

## Steps from `cell` to `goal`, or -1 when unreachable.
func distance(cell: Vector2i, goal: Vector2i) -> int:
	var dist := field(goal)
	return int(dist[cell]) if dist.has(cell) else -1

## Cell path from `cell` to `goal` inclusive; empty when unreachable.
func path(cell: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if distance(cell, goal) < 0:
		return out
	out.append(cell)
	while cell != goal:
		cell = next_cell(cell, goal)
		out.append(cell)
	return out

## The BFS distance field toward `goal` (cached).
func field(goal: Vector2i) -> Dictionary:
	if _fields.has(goal):
		return _fields[goal]
	if _fields.size() >= MAX_FIELDS:
		_fields.clear()
	var dist := {}
	if map != null and passable(goal):
		dist[goal] = 0
		var queue: Array[Vector2i] = [goal]
		var head := 0
		while head < queue.size() and dist.size() < max_cells:
			var c: Vector2i = queue[head]
			head += 1
			var nd: int = dist[c] + 1
			for d in DIRS:
				var n := c + d
				if dist.has(n) or not passable(n):
					continue
				dist[n] = nd
				queue.append(n)
	_fields[goal] = dist
	builds += 1
	return dist

## True iff a walking (non-swimming) mover may stand in `cell`: the same
## test TerrainMotion applies, plus the search bounds.
func passable(cell: Vector2i) -> bool:
	if bounds.size != Vector2i.ZERO and not bounds.has_point(cell):
		return false
	var props := map.type_properties(map.tile_type_at_cell(cell))
	return props["walkable"] and props.get("movement", TerrainTypes.Movement.WALKABLE) != TerrainTypes.Movement.FALLING

func _on_cell_changed(_cell: Vector2i, _old: StringName, _new: StringName) -> void:
	_fields.clear()

func _on_cell_interacted(_cell: Vector2i, _old: StringName, _new: StringName, _rule: StringName) -> void:
	_fields.clear()
