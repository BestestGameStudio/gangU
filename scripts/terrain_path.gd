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
	# Same search as #494 (same costs, same (f, first-insertion seq) ordering,
	# same stale-entry rule, cap and margin), with per-search state in flat
	# arrays indexed by the cell's position in the search box instead of
	# Dictionaries keyed by Vector2i, lazily cached passability and clearance
	# penalty per cell, and a heap of int cell indexes.
	var w := max_c.x - min_c.x + 1
	var n := w * (max_c.y - min_c.y + 1)
	var g := PackedFloat64Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var seqs := PackedInt32Array()
	seqs.resize(n)
	seqs.fill(-1)
	var pas := PackedByteArray()
	pas.resize(n)
	var pen := PackedFloat64Array()
	pen.resize(n)
	pen.fill(-1.0)
	var si := (start.y - min_c.y) * w + (start.x - min_c.x)
	var gi := (goal.y - min_c.y) * w + (goal.x - min_c.x)
	g[si] = 0.0
	seqs[si] = 0
	var next_seq := 1
	_hf = PackedFloat64Array()
	_hs = PackedInt64Array()
	_hi = PackedInt32Array()
	var h_start := float(absi(start.x - goal.x) + absi(start.y - goal.y))
	_ipush(h_start, 0, si)
	var best := si
	var best_h := h_start
	var expansions := 0
	var steps: Array[int] = [1, -1, w, -w]
	while _hi.size() > 0 and expansions < MAX_EXPANSIONS:
		var top_f := _hf[0]
		var top_s := _hs[0]
		var cur := _ipop()
		var cx := cur % w
		var cy := cur / w
		var ch := float(absi(cx + min_c.x - goal.x) + absi(cy + min_c.y - goal.y))
		if seqs[cur] != top_s or top_f > g[cur] + ch:
			continue # stale entry
		seqs[cur] = -1
		var cp := pas[cur]
		if cp == 0:
			cp = 1 if map.can_enter_cell(Vector2i(cx + min_c.x, cy + min_c.y), can_swim) else 2
			pas[cur] = cp
		if cp == 1 and ch < best_h:
			best = cur
			best_h = ch
		if cur == gi:
			best = cur
			break
		expansions += 1
		var gc := g[cur]
		for k in 4:
			var nx := cx + (1 if k == 0 else (-1 if k == 1 else 0))
			var ny := cy + (1 if k == 2 else (-1 if k == 3 else 0))
			if nx < 0 or ny < 0 or nx >= w or ny > max_c.y - min_c.y:
				continue
			var ni := cur + steps[k]
			var np := pas[ni]
			if np == 0:
				np = 1 if map.can_enter_cell(Vector2i(nx + min_c.x, ny + min_c.y), can_swim) else 2
				pas[ni] = np
			if np != 1:
				continue
			var pn := 0.0
			if ni != gi:
				pn = pen[ni]
				if pn < 0.0:
					var blocked := 0
					var ncell := Vector2i(nx + min_c.x, ny + min_c.y)
					for d in DIRS:
						var q := ncell + d
						var qx := q.x - min_c.x
						var qy := q.y - min_c.y
						var qp := 0
						if qx >= 0 and qy >= 0 and qx < w and qy <= max_c.y - min_c.y:
							qp = pas[qy * w + qx]
							if qp == 0:
								qp = 1 if map.can_enter_cell(q, can_swim) else 2
								pas[qy * w + qx] = qp
						else:
							qp = 1 if map.can_enter_cell(q, can_swim) else 2
						if qp != 1:
							blocked += 1
					pn = 0.75 * blocked
					pen[ni] = pn
			var ng := gc + 1.0 + pn
			if ng < g[ni]:
				g[ni] = ng
				came[ni] = cur
				if seqs[ni] < 0:
					seqs[ni] = next_seq
					next_seq += 1
				_ipush(ng + float(absi(nx + min_c.x - goal.x) + absi(ny + min_c.y - goal.y)), seqs[ni], ni)
	if best == si:
		return []
	var rev: Array[Vector2i] = [Vector2i(best % w + min_c.x, best / w + min_c.y)]
	var c := best
	while came[c] >= 0:
		c = came[c]
		if c != si:
			rev.push_front(Vector2i(c % w + min_c.x, c / w + min_c.y))
	return rev

var _hi := PackedInt32Array()

func _ipush(f: float, s: int, c: int) -> void:
	var i := _hi.size()
	_hf.append(f)
	_hs.append(s)
	_hi.append(c)
	while i > 0:
		var p := (i - 1) >> 1
		var pf := _hf[p]
		if f < pf or (f == pf and s < _hs[p]):
			_hf[i] = pf
			_hs[i] = _hs[p]
			_hi[i] = _hi[p]
			i = p
		else:
			break
	_hf[i] = f
	_hs[i] = s
	_hi[i] = c

func _ipop() -> int:
	var top := _hi[0]
	var last := _hi.size() - 1
	var f := _hf[last]
	var s := _hs[last]
	var c := _hi[last]
	_hf.resize(last)
	_hs.resize(last)
	_hi.resize(last)
	if last == 0:
		return top
	var i := 0
	while true:
		var l := 2 * i + 1
		if l >= last:
			break
		var m := l
		var r := l + 1
		if r < last and (_hf[r] < _hf[l] or (_hf[r] == _hf[l] and _hs[r] < _hs[l])):
			m = r
		if _hf[m] < f or (_hf[m] == f and _hs[m] < s):
			_hf[i] = _hf[m]
			_hs[i] = _hs[m]
			_hi[i] = _hi[m]
			i = m
		else:
			break
	_hf[i] = f
	_hs[i] = s
	_hi[i] = c
	return top

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
var _hf := PackedFloat64Array()
var _hs := PackedInt64Array()
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
