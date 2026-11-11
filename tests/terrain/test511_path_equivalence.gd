extends SceneTree
## #511 B: the array-based A* in TerrainPath must return the same path as the
## reference linear-scan search (the #494 semantics) on random maps: random
## blockers/water/mountain/tree/block, swim and no-swim, near and far goals,
## unreachable goals included.
## Run: godot --headless --fixed-fps 60 --path . -s tests/terrain/test511_path_equivalence.gd

var _fails := 0
var _total := 0
var _nonempty := 0

func _initialize() -> void:
	_run.call_deferred()

func _ref_path(map: TerrainMap, from: Vector2, to: Vector2, sw: bool) -> Array[Vector2i]:
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
		if tp._passable(map, current, sw) and tp._h(current, goal) < best_h:
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
			if not tp._passable(map, next, sw):
				continue
			var ng: float = g[current] + 1.0 + tp._clearance_penalty(map, next, goal, sw)
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


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 511
	var types: Array[StringName] = [&"obstacle", &"water", &"mountain", &"tree", &"block", &"mud", &"grass"]
	for m in 12:
		var map := TerrainMap.new()
		root.add_child(map)
		var dens := rng.randf_range(0.05, 0.45)
		var cells := {}
		for x in range(-30, 70):
			for y in range(-30, 70):
				if rng.randf() < dens:
					cells[Vector2i(x, y)] = types[rng.randi() % types.size()]
		map.set_cells(cells)
		for i in 30:
			var a := Vector2(rng.randf_range(-10, 50), rng.randf_range(-10, 50)) * map.cell_size
			var b := a + Vector2(rng.randf_range(-70, 70), rng.randf_range(-70, 70)) * map.cell_size * (1.0 if i % 3 else 0.2)
			for sw in [false, true]:
				var got: Array[Vector2i] = TerrainPath.new()._find_path(map, a, b, sw)
				var want: Array[Vector2i] = _ref_path(map, a, b, sw)
				_total += 1
				if not got.is_empty():
					_nonempty += 1
				if got != want:
					_fails += 1
		map.queue_free()
	# Box above MAX_BOX_CELLS: the sparse fallback must equal the reference too,
	# with obstacles around the start (detours inside the expansion cap).
	var big_fails := 0
	for m in 4:
		var bmap := TerrainMap.new()
		root.add_child(bmap)
		var bcells := {}
		for x in range(-30, 120):
			for y in range(-30, 120):
				if rng.randf() < 0.22:
					bcells[Vector2i(x, y)] = types[rng.randi() % types.size()]
		bmap.set_cells(bcells)
		for i in 3:
			var ba := Vector2(rng.randf_range(0, 40), rng.randf_range(0, 40)) * bmap.cell_size
			var bb := ba + Vector2(rng.randf_range(600, 900), rng.randf_range(-400, 400)) * bmap.cell_size
			for sw in [false, true]:
				var bgot: Array[Vector2i] = TerrainPath.new()._find_path(bmap, ba, bb, sw)
				var bwant: Array[Vector2i] = _ref_path(bmap, ba, bb, sw)
				_total += 1
				if not bgot.is_empty():
					_nonempty += 1
				if bgot != bwant:
					big_fails += 1
		bmap.queue_free()
	print("[511] large-box searches differing from the reference: %d" % big_fails)
	_fails += big_fails
	# Far endpoints: the search box is clamped (MAX_SPAN), so this must return
	# promptly with a bounded path toward the goal instead of allocating a
	# 10,000 x 10,000 box.
	var far_map := TerrainMap.new()
	root.add_child(far_map)
	var far_a := Vector2(0, 0)
	var far_b := Vector2(10000, 10000) * far_map.cell_size
	var t0 := Time.get_ticks_msec()
	var far_path: Array[Vector2i] = TerrainPath.new()._find_path(far_map, far_a, far_b, false)
	var far_ms := Time.get_ticks_msec() - t0
	var far_ok := not far_path.is_empty() and far_path.size() <= TerrainPath.MAX_EXPANSIONS + 2 and far_ms < 2000
	var back_path: Array[Vector2i] = TerrainPath.new()._find_path(far_map, far_b, far_a, false)
	far_ok = far_ok and not back_path.is_empty()
	print("[511] far endpoints: %d cells, %d ms, back %d" % [far_path.size(), far_ms, back_path.size()])
	if not far_ok:
		_fails += 1
	far_map.queue_free()
	print("[511] %d searches (%d with a route), %d differ from the reference" % [_total, _nonempty, _fails])
	print("[511] RESULT: ", "ALL PASS" if _fails == 0 and _nonempty > 100 else "FAIL")
	quit(0 if _fails == 0 and _nonempty > 100 else 1)
