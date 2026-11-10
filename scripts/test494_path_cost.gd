extends SceneTree
## #494 (wolves drop the frame rate): TerrainPath must not run its bounded
## A* every physics frame. Checks, headless and deterministic (search COUNTS,
## not timings):
##   - unreachable target (enclosed by trees): <= 1 search per REPLAN_INTERVAL
##   - a reachable detour still finds the same route and arrives
##   - the heap A* returns the same path as the pre-#494 linear-scan A*
##     (paths are compared against an inline reference implementation)

var _fails := 0

func _check(label: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("[494] ", label, " -> ", "PASS" if ok else "FAIL")

func _initialize() -> void:
	_run.call_deferred()

func _ring_map() -> TerrainMap:
	var map := TerrainMap.new()
	# Target at cell (20, 5) fully enclosed by a one-cell tree ring.
	for x in range(18, 23):
		for y in range(3, 8):
			if x == 18 or x == 22 or y == 3 or y == 7:
				map.set_cell(Vector2i(x, y), TerrainTypes.TREE)
	return map

func _run() -> void:
	var map := _ring_map()
	var cs := float(map.cell_size)
	var from := map.cell_to_world(Vector2i(2, 5))
	var dest := map.cell_to_world(Vector2i(20, 5))
	var p := TerrainPath.new()
	var pos := from
	var vel := Vector2.ZERO
	var frames := 900
	var dt := 1.0 / 60.0
	for i in frames:
		var desired := (dest - pos).normalized() * 120.0
		vel = p.steer(map, pos, vel, desired, dest, 120.0, dt)
		pos += vel * dt
	# 900 frames = 15 s at a 0.25 s replan interval: at most 61 searches. The
	# mover reaches the ring and hugs it (nothing reachable improves on its
	# cell, so the path is EMPTY), the case that used to search every frame.
	_check("unreachable target: searches over 15 s are bounded by the replan interval (%d <= 61)" % p.plans, p.plans <= 61)
	_check("unreachable target: at least one search ran", p.plans >= 1)
	_check("unreachable target: mover stays outside the ring", pos.x < 18.0 * cs)
	# Reachable detour: a wall with a gap.
	var map2 := TerrainMap.new()
	for y in range(0, 12):
		if y != 9:
			map2.set_cell(Vector2i(10, y), TerrainTypes.TREE)
	var p2 := TerrainPath.new()
	var pos2 := map2.cell_to_world(Vector2i(4, 4))
	var dest2 := map2.cell_to_world(Vector2i(16, 4))
	var vel2 := Vector2.ZERO
	for i in 900:
		var d2 := (dest2 - pos2).normalized() * 120.0
		vel2 = p2.steer(map2, pos2, vel2, d2, dest2, 120.0, dt)
		pos2 += vel2 * dt
	_check("detour: reaches the far side through the gap", pos2.x > 14.0 * cs and pos2.distance_to(dest2) < 2.0 * cs)
	_check("detour: searches stay bounded (%d <= 60)" % p2.plans, p2.plans <= 60)
	# Same route as the reference linear-scan A* on the detour map.
	var ref := _ref_path(map2, map2.cell_to_world(Vector2i(4, 4)), dest2)
	var got := TerrainPath.new()._find_path(map2, map2.cell_to_world(Vector2i(4, 4)), dest2)
	_check("A*: heap search equals the reference linear-scan route (%d cells)" % got.size(), got == ref and got.size() > 0)
	print("[494] DONE failures=", _fails)
	quit(1 if _fails > 0 else 0)

## Reference: the pre-#494 A* (linear-scan open list), kept verbatim for the
## equivalence check.
func _ref_path(map: TerrainMap, from: Vector2, to: Vector2) -> Array[Vector2i]:
	var tp := TerrainPath.new()
	var start := map.world_to_cell(from)
	var goal := map.world_to_cell(to)
	var min_c := Vector2i(mini(start.x, goal.x) - TerrainPath.SEARCH_MARGIN, mini(start.y, goal.y) - TerrainPath.SEARCH_MARGIN)
	var max_c := Vector2i(maxi(start.x, goal.x) + TerrainPath.SEARCH_MARGIN, maxi(start.y, goal.y) + TerrainPath.SEARCH_MARGIN)
	var open: Array[Vector2i] = [start]
	var came := {}
	var g := {start: 0.0}
	var best := start
	var best_h := tp._h(start, goal)
	var expansions := 0
	while not open.is_empty() and expansions < TerrainPath.MAX_EXPANSIONS:
		var bi := 0
		var bf := INF
		for i in open.size():
			var f: float = g.get(open[i], INF) + tp._h(open[i], goal)
			if f < bf:
				bf = f
				bi = i
		var current := open[bi]
		open.remove_at(bi)
		if tp._passable(map, current, false) and tp._h(current, goal) < best_h:
			best = current
			best_h = tp._h(current, goal)
		if current == goal:
			best = current
			break
		expansions += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + d
			if next.x < min_c.x or next.y < min_c.y or next.x > max_c.x or next.y > max_c.y:
				continue
			if not tp._passable(map, next, false):
				continue
			var ng: float = g[current] + 1.0 + tp._clearance_penalty(map, next, goal, false)
			if ng < g.get(next, INF):
				g[next] = ng
				came[next] = current
				if not open.has(next):
					open.append(next)
	var rev: Array[Vector2i] = []
	if best == start:
		return rev
	rev.append(best)
	var c := best
	while came.has(c):
		c = came[c]
		if c != start:
			rev.push_front(c)
	return rev
