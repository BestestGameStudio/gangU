class_name TerrainPath
extends RefCounted
## #391: shared steer-around-terrain routing, extracted from
## SummonBehaviorGuard (#281) so summons AND enemies route around blocking
## terrain the same way (Daniel, 2026-11-09: "enemies can pathfind around
## trees"). Pure steering over the TerrainMap lookup seam
## (is_walkable_at / world_to_cell / cell_to_world - read-only); no state
## beyond one mover's current path, and no writes to the map.
##
## Shared routing contract (preserves each caller's prior water behavior):
##   - A clear straight line steers direct (zero overhead, no path state).
##   - A line blocked by a HARD obstacle triggers a bounded 4-dir A* over
##     the grid (no diagonal corner cutting between blocked cells),
##     replanned on a short timer because the target moves. Hard obstacle =
##     a cell nobody can enter: BLOCKING and not swimmable (trees, walls,
##     mountains, blocks), or FALLING.
##   - By default water is not a routing obstacle: enemies keep #165
##     swim-or-halt behavior. Summons opt into detour_unwalkable to retain
##     #281 routing around ALL cells they cannot enter, including water.
##     Swimmers cross water directly in either mode. The A* only routes a
##     mover through cells IT can enter (walkable, or swimmable when it can
##     swim), so a non-swimmer is never pathed through water.
##   - TerrainMotion.resolve always has the last word on the velocity, so a
##     blocked step is cancelled (never entered) even at corners.
##   - map == null (harnesses, areas with no Terrain node) returns the
##     desired velocity unchanged - exactly the pre-grid behavior.
##
## One instance per mover (the behavior instance idiom): path, waypoint and
## replan state are per-mover and never shared.

const REPLAN_INTERVAL: float = 0.25
const WAYPOINT_EPS: float = 8.0
const MAX_EXPANSIONS: int = 2000
const SEARCH_MARGIN: int = 16
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SEQ_BITS := 24
const SEQ_MASK := (1 << SEQ_BITS) - 1
const G_NONE := -1
const PENALTY_UNKNOWN := 255
const PASS_UNKNOWN := 0
const PASS_YES := 1
const PASS_NO := 2
const NODE_NEW := 0
const NODE_OPEN := 1
const NODE_CLOSED := 2

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _replan_timer: float = 0.0
var _memo_map_id: int = 0
var _memo_revision: int = -1
var _memo_start: Vector2i
var _memo_goal: Vector2i
var _memo_swim: bool = false
var _memo_path: Array[Vector2i] = []

## The resolved velocity toward `dest`. `desired` is the direct velocity the
## mover wants (used verbatim when no grid is wired or the line is clear);
## `speed` shapes waypoint segments when a detour is needed. Call once per
## physics step: the replan clock accumulates from delta here.
func steer(map: TerrainMap, pos: Vector2, previous: Vector2, desired: Vector2, dest: Vector2, speed: float, delta: float, can_swim: bool = false, detour_unwalkable: bool = false) -> Vector2:
	_replan_timer = maxf(0.0, _replan_timer - delta)
	if map == null:
		return desired
	if desired == Vector2.ZERO:
		return TerrainMotion.resolve(map, pos, previous, desired, delta, can_swim)
	if _line_routable(map, pos, dest, can_swim, detour_unwalkable):
		_path = []
		_replan_timer = REPLAN_INTERVAL
		return TerrainMotion.resolve(map, pos, previous, desired, delta, can_swim)
	if _replan_timer <= 0.0 or _path.is_empty():
		_path = _find_path(map, pos, dest, can_swim)
		_path_index = 0
		_replan_timer = REPLAN_INTERVAL
	if _path.is_empty():
		# No route found within the search bounds: keep the #165 slide
		# behavior (blocked step cancels) rather than freezing or clipping.
		return TerrainMotion.resolve(map, pos, previous, desired, delta, can_swim)
	var waypoint: Vector2 = map.cell_to_world(_path[_path_index])
	if pos.distance_to(waypoint) < WAYPOINT_EPS and _path_index < _path.size() - 1:
		_path_index += 1
		waypoint = map.cell_to_world(_path[_path_index])
	var wp_desired: Vector2 = (waypoint - pos).normalized() * speed
	var resolved := TerrainMotion.resolve(map, pos, previous, wp_desired, delta, can_swim)
	if resolved == Vector2.ZERO:
		# Wedged (corner or moving target shifted the map): replan next frame.
		_replan_timer = 0.0
	return resolved

## Default callers detour hard obstacles only (#165 enemy swim-or-halt).
## Summons opt into all unwalkable cells to preserve their #281 behavior.
## Sample at half-cell steps so no blocked cell is skipped.
func _line_routable(map: TerrainMap, from: Vector2, to: Vector2, can_swim: bool = false, detour_unwalkable: bool = false) -> bool:
	var dist := from.distance_to(to)
	var steps := int(ceil(dist / (map.cell_size * 0.5))) + 1
	for i in steps + 1:
		var cell := map.world_to_cell(from.lerp(to, float(i) / steps))
		if (detour_unwalkable and not _passable(map, cell, can_swim)) or _hard_obstacle(map, cell):
			return false
	return true

## A cell no mover can enter: BLOCKING and not swimmable, or FALLING.
func _hard_obstacle(map: TerrainMap, cell: Vector2i) -> bool:
	return map.is_hard_obstacle_cell(cell)

## A cell THIS mover may be routed through (can_swim-aware). FALLING tiles
## are never swimmable (TerrainTypes.apply_movement), so this is exactly
## walkable-or-swimmable.
func _passable(map: TerrainMap, cell: Vector2i, can_swim: bool) -> bool:
	return map.can_enter_cell(cell, can_swim)

## Bounded 4-dir A* over the walkability grid (4-dir: no diagonal corner
## cutting between blocked cells). Returns the cell path EXCLUDING the start
## cell, ending at the goal cell or the reachable walkable cell nearest to it
## (the target may hug a wall); empty when nothing reachable improves on the
## start cell.
##
## The result is a pure function of (start cell, goal cell, can_swim, map
## contents), so a repeat of the last query on an unchanged map returns the
## last answer: a mover parked against an unreachable target stops paying a
## capped search on every replan.
func _find_path(map: TerrainMap, from: Vector2, to: Vector2, can_swim: bool = false) -> Array[Vector2i]:
	var start := map.world_to_cell(from)
	var goal := map.world_to_cell(to)
	if start == goal:
		return []
	if map.get_instance_id() == _memo_map_id and map.revision == _memo_revision and start == _memo_start and goal == _memo_goal and can_swim == _memo_swim:
		return _memo_path.duplicate()
	var path := _search(map, start, goal, can_swim)
	_memo_map_id = map.get_instance_id()
	_memo_revision = map.revision
	_memo_start = start
	_memo_goal = goal
	_memo_swim = can_swim
	_memo_path = path.duplicate()
	return path

## The open list is ordered by (f, insertion order): the node popped is the
## lowest f, ties going to the node that entered the open list first.
##
## Step cost is 1 plus a soft one-cell clearance of 0.75 per side of the
## entered cell this mover cannot enter: keeps waypoints (and the sprite) off
## wall corners so it never visibly brushes terrain. The goal cell is exempt -
## a target hugging a wall must stay reachable. Costs are kept in quarter
## steps, which makes them exact integers.
func _search(map: TerrainMap, start: Vector2i, goal: Vector2i, can_swim: bool) -> Array[Vector2i]:
	var min_c := Vector2i(mini(start.x, goal.x) - SEARCH_MARGIN, mini(start.y, goal.y) - SEARCH_MARGIN)
	var max_c := Vector2i(maxi(start.x, goal.x) + SEARCH_MARGIN, maxi(start.y, goal.y) + SEARCH_MARGIN)
	# Grid over the search box plus a one-cell ring (clearance looks at the
	# neighbours of box cells).
	var ox := min_c.x - 1
	var oy := min_c.y - 1
	var w := max_c.x - min_c.x + 3
	var n := w * (max_c.y - min_c.y + 3)
	var passable := PackedByteArray()
	passable.resize(n)
	passable.fill(PASS_UNKNOWN)
	var penalty := PackedByteArray()
	penalty.resize(n)
	penalty.fill(PENALTY_UNKNOWN)
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(G_NONE)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var state := PackedByteArray()
	state.resize(n)
	state.fill(NODE_NEW)
	var seq_of := PackedInt32Array()
	seq_of.resize(n)
	var idx_of_seq := PackedInt32Array()
	var open := PackedInt64Array()
	var goal_i := (goal.y - oy) * w + (goal.x - ox)
	var start_i := (start.y - oy) * w + (start.x - ox)
	g[start_i] = 0
	state[start_i] = NODE_OPEN
	seq_of[start_i] = 0
	idx_of_seq.append(start_i)
	_open_push(open, (_h4(start, goal) << SEQ_BITS))
	var best_i := start_i
	var best_h := _h4(start, goal)
	var expansions := 0
	while expansions < MAX_EXPANSIONS:
		var ci := -1
		while not open.is_empty():
			var sq := _open_pop(open) & SEQ_MASK
			var i := idx_of_seq[sq]
			if state[i] == NODE_OPEN and seq_of[i] == sq:
				ci = i
				break
		if ci < 0:
			break
		state[ci] = NODE_CLOSED
		var current := Vector2i(ci % w + ox, ci / w + oy)
		var ch := _h4(current, goal)
		if ch < best_h and (passable[ci] if passable[ci] != PASS_UNKNOWN else _probe(map, passable, ci, current, can_swim)) == PASS_YES:
			best_i = ci
			best_h = ch
		if ci == goal_i:
			best_i = ci
			break
		expansions += 1
		for d in DIRS:
			var next: Vector2i = current + d
			if next.x < min_c.x or next.y < min_c.y or next.x > max_c.x or next.y > max_c.y:
				continue
			var ni := ci + d.x + d.y * w
			var pv := passable[ni]
			if pv == PASS_UNKNOWN:
				pv = _probe(map, passable, ni, next, can_swim)
			if pv == PASS_NO:
				continue
			var ng := g[ci] + 4
			if ni != goal_i:
				var pen := penalty[ni]
				if pen == PENALTY_UNKNOWN:
					pen = 0
					for e in DIRS:
						var ei := ni + e.x + e.y * w
						var ev := passable[ei]
						if ev == PASS_UNKNOWN:
							ev = _probe(map, passable, ei, next + e, can_swim)
						if ev == PASS_NO:
							pen += 3
					penalty[ni] = pen
				ng += pen
			if g[ni] == G_NONE or ng < g[ni]:
				g[ni] = ng
				came[ni] = ci
				if state[ni] != NODE_OPEN:
					state[ni] = NODE_OPEN
					seq_of[ni] = idx_of_seq.size()
					idx_of_seq.append(ni)
				_open_push(open, ((ng + _h4(next, goal)) << SEQ_BITS) | seq_of[ni])
	if best_i == start_i:
		return []
	var rev: Array[Vector2i] = []
	var c := best_i
	while c != start_i and c >= 0:
		rev.append(Vector2i(c % w + ox, c / w + oy))
		c = came[c]
	rev.reverse()
	return rev

func _probe(map: TerrainMap, cache: PackedByteArray, i: int, cell: Vector2i, can_swim: bool) -> int:
	var p := PASS_YES if map.can_enter_cell(cell, can_swim) else PASS_NO
	cache[i] = p
	return p

func _h4(a: Vector2i, b: Vector2i) -> int:
	return 4 * (absi(a.x - b.x) + absi(a.y - b.y))

## Open list: keys stored negated in ascending order, so the lowest key is
## the last element (O(1) pop) and an insert is one native binary search
## plus one native insert.
func _open_push(open: PackedInt64Array, key: int) -> void:
	open.insert(open.bsearch(-key), -key)

func _open_pop(open: PackedInt64Array) -> int:
	var last := open.size() - 1
	var top := -open[last]
	open.resize(last)
	return top
