extends SceneTree
## Terrain / pathfinding microbenchmark and behavior dump (audit 2026-11 perf
## findings 1-5). Loads the real overworld and a seeded dungeon_maze and calls
## the production functions directly.
##
##   godot --headless --path . -s tools/bench/terrain_perf.gd -- bench
##       timings, one line per function (median of 5 samples)
##   godot --headless --path . -s tools/bench/terrain_perf.gd -- dump=<file>
##       writes the outputs of a fixed query set (A* paths, steering runs,
##       FlowNav fields, motion, sight, cover, every art/color layer cell
##       after a scripted series of cell changes). Two builds behave the
##       same iff their dumps are byte-identical.

const MAZE_SEED := 22
const PAIR_SEED := 7

var _frames := 0
var _ow: Node = null
var _maze: Node = null
var _mode := "bench"
var _dump_path := ""
var _out := PackedStringArray()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "bench":
			_mode = "bench"
		elif a.begins_with("dump="):
			_mode = "dump"
			_dump_path = a.substr(5)
	MazeDefenseDungeon.forced_seed = MAZE_SEED
	_ow = (load("res://scenes/overworld.tscn") as PackedScene).instantiate()
	root.add_child(_ow)
	_maze = (load("res://scenes/dungeon_maze.tscn") as PackedScene).instantiate()
	_maze.position = Vector2(100000, 100000)
	root.add_child(_maze)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _mode == "dump":
		_dump()
		var f := FileAccess.open(_dump_path, FileAccess.WRITE)
		f.store_string("\n".join(_out) + "\n")
		f.close()
		print("dump lines=%d -> %s" % [_out.size(), _dump_path])
	else:
		_bench()
	return true

func _find_map(n: Node) -> TerrainMap:
	if n is TerrainMap:
		return n
	for c in n.get_children():
		var m := _find_map(c)
		if m != null:
			return m
	return null

func _t(label: String, reps: int, f: Callable) -> void:
	var samples: Array[float] = []
	for r in 5:
		var t0 := Time.get_ticks_usec()
		for i in reps:
			f.call()
		samples.append(float(Time.get_ticks_usec() - t0) / reps)
	samples.sort()
	print("BENCH %-44s median %9.2f us  min %9.2f  max %9.2f  (reps %d x5)" % [label, samples[2], samples[0], samples[4], reps])

## Deterministic start/goal cell pairs <= 12 cells apart whose straight line
## is blocked (the case that runs A*), around `origin`.
func _pairs(map: TerrainMap, origin: Vector2i, spread: int, n: int) -> Array:
	var tp := TerrainPath.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = PAIR_SEED
	var out := []
	for k in n:
		var a: Vector2i = origin + Vector2i(rng.randi_range(-spread, spread), rng.randi_range(-spread, spread))
		var b: Vector2i = a + Vector2i(rng.randi_range(-12, 12), rng.randi_range(-12, 12))
		if not map.is_walkable_at_cell(a):
			continue
		if tp._line_routable(map, map.cell_to_world(a), map.cell_to_world(b)):
			continue
		out.append([a, b])
	return out

func _bench() -> void:
	var map := _find_map(_ow)
	var mmap := _find_map(_maze)
	var nav := _maze.get_node("FlowNav") as FlowNav
	print("overworld cells=%d bounds=%s; maze cells=%d bounds=%s" % [map.assigned_cells().size(), map.art_bounds(), mmap.assigned_cells().size(), mmap.art_bounds()])
	var some_cell: Vector2i = map.assigned_cells()[0]
	var p := map.cell_to_world(some_cell)
	_t("TerrainMap.is_walkable_at_cell", 20000, func(): return map.is_walkable_at_cell(some_cell))
	_t("TerrainMap.conceals_at", 20000, func(): return map.conceals_at(p))
	_t("TallGrass.can_see", 20000, func(): return TallGrass.can_see(map, p, p + Vector2(50, 0)))
	_t("TerrainMotion.resolve (1 enemy step)", 5000, func(): return TerrainMotion.resolve(map, p, Vector2.ZERO, Vector2(100, 0), 1.0 / 60.0, false))
	var visuals := _ow.get_node("BlockVisuals")
	_t("TerrainBlockVisuals._physics_process", 200, func():
		if visuals.has_method("_physics_process"):
			visuals._physics_process(1.0 / 60.0))
	var tp := TerrainPath.new()
	var pairs := _pairs(map, map.world_to_cell(p), 60, 4000)
	for run in 2:
		var times: Array[float] = []
		for pr in pairs:
			var t0 := Time.get_ticks_usec()
			tp._find_path(map, map.cell_to_world(pr[0]), map.cell_to_world(pr[1]))
			times.append(float(Time.get_ticks_usec() - t0))
		times.sort()
		print("BENCH A* blocked pairs<=12 (run %d) n=%d p50 %.1f us p90 %.1f us max %.1f us total %.1f ms" % [run, times.size(), times[times.size() / 2], times[int(times.size() * 0.9)], times[-1], _sum(times) / 1000.0])
	var far := p + Vector2(32 * 40, 32 * 10)
	_t("TerrainPath._find_path far goal (cap)", 5, func(): return TerrainPath.new()._find_path(map, p, far, false))
	var parked := TerrainPath.new()
	_t("steer: 1 s (60 frames) parked, far target", 3, func():
		for f in 60:
			parked.steer(map, p, Vector2.ZERO, (far - p).normalized() * 100.0, far, 100.0, 1.0 / 60.0))
	var ty := map.tile_type_at_cell(some_cell)
	_t("TerrainMap.set_cell overworld", 5, func(): return map.set_cell(some_cell, ty))
	var mcells := mmap.assigned_cells()
	var goals: Array[Vector2i] = []
	for y in range(nav.bounds.position.y, nav.bounds.end.y):
		for x in range(nav.bounds.position.x, nav.bounds.end.x):
			if nav.passable(Vector2i(x, y)):
				goals.append(Vector2i(x, y))
	var i := [0]
	_t("FlowNav.field new goal (BFS)", 5, func():
		nav.invalidate()
		i[0] += 1
		return nav.field(goals[(i[0] * 37) % goals.size()]).size())
	var wall := _first_of(mmap, TerrainTypes.OBSTACLE, nav.bounds)
	_t("TerrainMap.set_cell maze (art visible)", 5, func(): return mmap.set_cell(wall, TerrainTypes.OBSTACLE))
	_t("FlowNav: cell change + 4 cached goals reused", 5, func():
		for g in 4:
			nav.field(goals[g * 11])
		mmap.destroy_cell(wall)
		mmap.set_cell(wall, TerrainTypes.BLOCK)
		for g in 4:
			nav.field(goals[g * 11]))
	map.visible = true
	_t("TerrainMap.set_cell overworld (art visible)", 5, func(): return map.set_cell(some_cell, ty))

func _sum(a: Array[float]) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s

func _first_of(map: TerrainMap, type: StringName, inside: Rect2i) -> Vector2i:
	var best := Vector2i(1 << 30, 1 << 30)
	for c: Vector2i in map.assigned_cells():
		if map.tile_type_at_cell(c) != type or not inside.has_point(c):
			continue
		if c.y < best.y or (c.y == best.y and c.x < best.x):
			best = c
	return best

func _emit(s: String) -> void:
	_out.append(s)

func _dump() -> void:
	var map := _find_map(_ow)
	var mmap := _find_map(_maze)
	var nav := _maze.get_node("FlowNav") as FlowNav
	_emit("ow cells=%d bounds=%s maze cells=%d bounds=%s nav=%s" % [map.assigned_cells().size(), map.art_bounds(), mmap.assigned_cells().size(), mmap.art_bounds(), nav.bounds])
	var origin := map.world_to_cell(map.cell_to_world(map.assigned_cells()[0]))
	for m: TerrainMap in [map, mmap]:
		var o := origin if m == map else mmap.art_bounds().get_center()
		var tp := TerrainPath.new()
		for pr in _pairs(m, o, 60 if m == map else 18, 1500):
			for swim in [false, true]:
				_emit("path %s->%s swim=%s %s" % [pr[0], pr[1], swim, tp._find_path(m, m.cell_to_world(pr[0]), m.cell_to_world(pr[1]), swim)])
		_emit("far %s" % [tp._find_path(m, m.cell_to_world(o), m.cell_to_world(o + Vector2i(40, 10)))])
		_dump_sweep(m)
		_dump_steer(m, o)
	_dump_flow(nav, mmap)
	_dump_layers("maze-initial", mmap)
	_dump_changes(mmap, nav)
	map.visible = true
	_dump_layers("ow-visible", map)
	_dump_changes(map, null)

func _dump_sweep(m: TerrainMap) -> void:
	var b := m.art_bounds().grow(2)
	var rows := PackedStringArray()
	for y in range(b.position.y, b.end.y):
		var row := ""
		for x in range(b.position.x, b.end.x):
			var c := Vector2i(x, y)
			row += "%d%d%d" % [int(m.is_walkable_at_cell(c)), m.movement_at_cell(c), int(m.conceals_at(m.cell_to_world(c)))]
		rows.append(row)
	_emit("sweep %d %s" % [rows.size(), "|".join(rows).md5_text()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lo := m.cell_to_world(b.position)
	var hi := m.cell_to_world(b.end)
	for i in 600:
		var pos := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		var prev := Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
		var want := Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))
		var to := pos + Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
		_emit("motion %s %s %s %s %s %s %s %s %s" % [
			TerrainMotion.resolve(m, pos, prev, want, 1.0 / 60.0, false),
			TerrainMotion.resolve(m, pos, prev, want, 1.0 / 60.0, true),
			TerrainMotion.can_enter(m, pos, false), TerrainMotion.can_enter(m, pos, true),
			TerrainMotion.clamp_displacement(m, pos, to, false),
			TallGrass.can_see(m, pos, to), m.lob_blocked(pos, to), m.properties_at(pos), m.projectile_block_t(pos, to - pos)])

## Whole steering runs: a mover chasing a fixed or circling target, its
## position integrated from the resolved velocity (replans included).
func _dump_steer(m: TerrainMap, o: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for run in 24:
		var start := o + Vector2i(rng.randi_range(-20, 20), rng.randi_range(-20, 20))
		if not m.is_walkable_at_cell(start):
			continue
		var target := m.cell_to_world(start + Vector2i(rng.randi_range(-15, 15), rng.randi_range(-15, 15)))
		var swim := run % 3 == 0
		var detour := run % 4 == 1
		var tp := TerrainPath.new()
		var pos := m.cell_to_world(start)
		var vel := Vector2.ZERO
		var trace := PackedStringArray()
		for f in 240:
			var dest := target + Vector2(40, 0).rotated(f * 0.05) if run % 2 == 0 else target
			var desired := (dest - pos).normalized() * 120.0
			vel = tp.steer(m, pos, vel, desired, dest, 120.0, 1.0 / 60.0, swim, detour)
			pos += vel / 60.0
			if f % 20 == 19:
				trace.append("%.3f,%.3f" % [pos.x, pos.y])
		_emit("steer %d %s" % [run, " ".join(trace)])

func _dump_flow(nav: FlowNav, mmap: TerrainMap) -> void:
	var goals: Array[Vector2i] = []
	for y in range(nav.bounds.position.y, nav.bounds.end.y):
		for x in range(nav.bounds.position.x, nav.bounds.end.x):
			if nav.passable(Vector2i(x, y)):
				goals.append(Vector2i(x, y))
	for k in 12:
		var g: Vector2i = goals[(k * 53) % goals.size()]
		var f := nav.field(g)
		var keys := f.keys()
		keys.sort()
		var parts := PackedStringArray()
		for c in keys:
			parts.append("%s=%d" % [c, f[c]])
		var src: Vector2i = goals[(k * 97 + 5) % goals.size()]
		_emit("flow %s n=%d %s path=%s wp=%s" % [g, f.size(), " ".join(parts).md5_text(), nav.path(src, g), nav.waypoint(mmap.cell_to_world(src) + Vector2(3, -2), mmap.cell_to_world(g))])

func _dump_layers(tag: String, m: TerrainMap) -> void:
	var lines := PackedStringArray()
	for child in m.get_children():
		var layer := child as TileMapLayer
		if layer == null:
			continue
		var cells := layer.get_used_cells()
		cells.sort()
		var parts := PackedStringArray()
		for c in cells:
			parts.append("%s:%d:%s:%d" % [c, layer.get_cell_source_id(c), layer.get_cell_atlas_coords(c), layer.get_cell_alternative_tile(c)])
		lines.append("%s n=%d %s" % [layer.name, cells.size(), " ".join(parts).md5_text()])
	_emit("layers %s %s" % [tag, " ; ".join(lines)])

## A scripted series of cell changes (destroy, interact, plain writes,
## erase, batch) with the presentation and the FlowNav answers dumped
## after each step.
func _dump_changes(m: TerrainMap, nav: FlowNav) -> void:
	var b := m.art_bounds()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var types := TerrainTypes.ALL
	var goal := Vector2i.ZERO
	if nav != null:
		goal = nav.bounds.get_center()
		while not nav.passable(goal):
			goal.x += 1
	for step in 40:
		var c := Vector2i(rng.randi_range(b.position.x, b.end.x - 1), rng.randi_range(b.position.y, b.end.y - 1))
		match step % 5:
			0: m.set_cell(c, types[rng.randi_range(0, types.size() - 1)])
			1: m.destroy_cell(c)
			2: m.interact_cell(c, [&"cold"])
			3: m.clear_cell(c)
			4:
				var batch := {}
				for k in 6:
					batch[c + Vector2i(k % 3, k / 3)] = types[rng.randi_range(0, types.size() - 1)]
				m.set_cells(batch)
		if step % 4 == 3:
			_dump_layers("%s step %d" % [m.name, step], m)
		if nav != null:
			var f := nav.field(goal)
			var keys := f.keys()
			keys.sort()
			var parts := PackedStringArray()
			for k in keys:
				parts.append("%s=%d" % [k, f[k]])
			var fresh := FlowNav.new()
			fresh.bounds = nav.bounds
			fresh.max_cells = nav.max_cells
			fresh.map = m
			_emit("flowstep %d n=%d %s" % [step, f.size(), " ".join(parts).md5_text()])
			_emit("flowfresh %d %s" % [step, fresh.field(goal) == f])
			fresh.map = null
			fresh.free()
	m.season = TerrainSeason.Season.WINTER
	_dump_layers("%s winter" % m.name, m)
