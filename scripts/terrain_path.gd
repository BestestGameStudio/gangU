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

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _replan_timer: float = 0.0
## #494: number of A* searches this mover has run (test hook / profiling).
var plans: int = 0
## #494: per-call cache of terrain type -> movement flags, so a search does
## not copy the registry's properties Dictionary for every cell it touches.
## Cleared at the start of each steer() so a palette change never goes stale.
var _flag_cache := {}
const F_WALK := 1
const F_SWIM := 2
const F_FALL := 4

## The resolved velocity toward `dest`. `desired` is the direct velocity the
## mover wants (used verbatim when no grid is wired or the line is clear);
## `speed` shapes waypoint segments when a detour is needed. Call once per
## physics step: the replan clock accumulates from delta here.
func steer(map: TerrainMap, pos: Vector2, previous: Vector2, desired: Vector2, dest: Vector2, speed: float, delta: float, can_swim: bool = false, detour_unwalkable: bool = false) -> Vector2:
	_replan_timer = maxf(0.0, _replan_timer - delta)
	_flag_cache.clear()
	if map == null:
		return desired
	if desired == Vector2.ZERO:
		return TerrainMotion.resolve(map, pos, previous, desired, delta, can_swim)
	if _line_routable(map, pos, dest, can_swim, detour_unwalkable):
		_path = []
		_replan_timer = REPLAN_INTERVAL
		return TerrainMotion.resolve(map, pos, previous, desired, delta, can_swim)
	# #494: replan on the timer only. An unreachable target leaves the path
	# empty, and replanning "because empty" ran a full bounded A* EVERY frame.
	if _replan_timer <= 0.0:
		plans += 1
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

## Movement flags of the cell's terrain type (F_WALK | F_SWIM | F_FALL),
## cached per steer() call by type.
func _flags(map: TerrainMap, cell: Vector2i) -> int:
	var type := map.tile_type_at_cell(cell)
	var f: Variant = _flag_cache.get(type)
	if f == null:
		var props := map.type_properties(type)
		var v := 0
		if props["walkable"]:
			v |= F_WALK
		if props["swimmable"]:
			v |= F_SWIM
		if props.get("movement", TerrainTypes.Movement.BLOCKING) == TerrainTypes.Movement.FALLING:
			v |= F_FALL
		_flag_cache[type] = v
		return v
	return f

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
func _find_path(map: TerrainMap, from: Vector2, to: Vector2, can_swim: bool = false) -> Array[Vector2i]:
	var start := map.world_to_cell(from)
	var goal := map.world_to_cell(to)
	if start == goal:
		return []
	var min_c := Vector2i(mini(start.x, goal.x) - SEARCH_MARGIN, mini(start.y, goal.y) - SEARCH_MARGIN)
	var max_c := Vector2i(maxi(start.x, goal.x) + SEARCH_MARGIN, maxi(start.y, goal.y) + SEARCH_MARGIN)
	# #494: binary-heap open set. Entries order by (f, seq); seq is the
	# cell's first-insertion order, which reproduces the old linear scan's
	# "first lowest f in the open list" tie-break exactly. Improved cells are
	# re-pushed under the same seq; stale entries are skipped on pop.
	_hf = PackedFloat64Array()
	_hs = PackedInt64Array()
	_hc = []
	var seqs := {start: 0}
	var next_seq := 1
	var came := {}
	var g := {start: 0.0}
	_heap_push(_h(start, goal), 0, start)
	var best := start
	var best_h := _h(start, goal)
	var expansions := 0
	while _hc.size() > 0 and expansions < MAX_EXPANSIONS:
		var top_f := _hf[0]
		var top_s := _hs[0]
		var current := _heap_pop()
		if seqs.get(current, -1) != top_s or top_f > g.get(current, INF) + _h(current, goal):
			continue # stale entry
		seqs.erase(current)
		if _passable(map, current, can_swim) and _h(current, goal) < best_h:
			best = current
			best_h = _h(current, goal)
		if current == goal:
			best = current
			break
		expansions += 1
		for d in DIRS:
			var next: Vector2i = current + d
			if next.x < min_c.x or next.y < min_c.y or next.x > max_c.x or next.y > max_c.y:
				continue
			if not _passable(map, next, can_swim):
				continue
			var ng: float = g[current] + 1.0 + _clearance_penalty(map, next, goal, can_swim)
			if ng < g.get(next, INF):
				g[next] = ng
				came[next] = current
				if not seqs.has(next):
					seqs[next] = next_seq
					next_seq += 1
				_heap_push(ng + _h(next, goal), seqs[next], next)
	if best == start:
		return []
	var rev: Array[Vector2i] = [best]
	var c := best
	while came.has(c):
		c = came[c]
		if c != start:
			rev.push_front(c)
	return rev

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
var _hf := PackedFloat64Array()
var _hs := PackedInt64Array()
var _hc: Array[Vector2i] = []

func _heap_less(f1: float, s1: int, f2: float, s2: int) -> bool:
	return f1 < f2 or (f1 == f2 and s1 < s2)

func _heap_push(f: float, s: int, c: Vector2i) -> void:
	var i := _hc.size()
	_hf.append(f)
	_hs.append(s)
	_hc.append(c)
	while i > 0:
		var p := (i - 1) >> 1
		if not _heap_less(_hf[i], _hs[i], _hf[p], _hs[p]):
			break
		_heap_swap(i, p)
		i = p

func _heap_pop() -> Vector2i:
	var top := _hc[0]
	var last := _hc.size() - 1
	_heap_swap(0, last)
	_hf.remove_at(last)
	_hs.remove_at(last)
	_hc.remove_at(last)
	var n := last
	var i := 0
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < n and _heap_less(_hf[l], _hs[l], _hf[m], _hs[m]):
			m = l
		if r < n and _heap_less(_hf[r], _hs[r], _hf[m], _hs[m]):
			m = r
		if m == i:
			break
		_heap_swap(i, m)
		i = m
	return top

func _heap_swap(a: int, b: int) -> void:
	if a == b:
		return
	var tf := _hf[a]
	_hf[a] = _hf[b]
	_hf[b] = tf
	var ts := _hs[a]
	_hs[a] = _hs[b]
	_hs[b] = ts
	var tc := _hc[a]
	_hc[a] = _hc[b]
	_hc[b] = tc

func _h(a: Vector2i, b: Vector2i) -> float:
	return absf(a.x - b.x) + absf(a.y - b.y)

## Soft one-cell clearance around cells this mover cannot enter: keeps
## waypoints (and the sprite) off wall corners so it never visibly brushes
## terrain. The goal cell is exempt - a target hugging a wall must stay
## reachable.
func _clearance_penalty(map: TerrainMap, cell: Vector2i, goal: Vector2i, can_swim: bool = false) -> float:
	if cell == goal:
		return 0.0
	var blocked := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _passable(map, cell + d, can_swim):
			blocked += 1
	return 0.75 * blocked
