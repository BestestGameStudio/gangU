class_name TerrainNav
## #142 (Terrain A1) navigability flood-fill - a REUSABLE helper, delivered
## because A2 (generation) and A4 reuse it for their acceptance legs.
## Pure queries over the TerrainMap lookup seam only; no state, no writes.
##
## 4-neighborhood flood fill (up/down/left/right): diagonal corner-cutting
## policy is a movement-rules decision owned by A3, not guessed here.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Every walkable cell reachable from `from_world`, including the start
## cell. An unwalkable (or missing-map) start reaches NOTHING. `max_cells`
## is a safety valve for unbounded maps: the fill stops once that many
## cells are visited, so callers on open worlds must pass a bound they
## actually expect (the A1 debug map is wall-enclosed and terminates
## naturally far below the default).
static func reachable(map: TerrainMap, from_world: Vector2, max_cells: int = 65536) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if map == null or not map.is_walkable_at(from_world):
		return out
	var start := map.world_to_cell(from_world)
	var visited := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty() and visited.size() < max_cells:
		var c: Vector2i = stack.pop_back()
		out.append(c)
		for d in DIRS:
			var n: Vector2i = c + d
			if visited.has(n) or not map.is_walkable_at_cell(n):
				continue
			visited[n] = true
			stack.append(n)
	return out

## True iff a walkable path exists from `from_world` to `to_world`.
## Either endpoint on unwalkable terrain is NOT navigable.
static func is_navigable(map: TerrainMap, from_world: Vector2, to_world: Vector2, max_cells: int = 65536) -> bool:
	if map == null or not map.is_walkable_at(to_world):
		return false
	var target := map.world_to_cell(to_world)
	return reachable(map, from_world, max_cells).has(target)
