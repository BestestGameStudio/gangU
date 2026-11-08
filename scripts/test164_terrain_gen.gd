extends SceneTree
## Generator harness: determinism, biome coverage, navigability via the
## TerrainNav flood fill, the path guarantee as a real negative, and the
## all-or-nothing set_cells batch. Tree-dependent legs wait until the debug
## scene is ready (repo idiom).

const SIZE := Vector2i(40, 24)
const SEEDS := 20

var failures := 0
var t := 0.0
var scene: Node2D

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[164] ", name, " -> PASS")
	else:
		failures += 1
		print("[164] ", name, " -> FAIL")

func _initialize() -> void:
	_check(not TerrainTypes.is_walkable(TerrainTypes.TREE), "TREE not walkable")
	_check(TerrainTypes.is_walkable(TerrainTypes.GRASS) and TerrainTypes.is_walkable(TerrainTypes.SNOW), "GRASS and SNOW walkable")
	_check(TerrainTypes.is_walkable(TerrainTypes.ICE) and TerrainTypes.speed_multiplier(TerrainTypes.ICE) == 1.0, "ICE walkable at speed 1.0")
	_check(TerrainTypes.element_tags(TerrainTypes.ICE) == [&"ice"], "ICE carries the ice element tag")
	scene = load("res://scenes/test164_terrain_gen_debug.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _process(delta: float) -> bool:
	t += delta
	if not scene.is_node_ready():
		if t > 4.0:
			_check(false, "debug scene never became ready")
			return _done()
		return false
	_run_legs()
	return _done()

func _new_map() -> TerrainMap:
	var m := TerrainMap.new()
	root.add_child(m)
	return m

func _grid(m: TerrainMap) -> Array[StringName]:
	var out: Array[StringName] = []
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			out.append(m.tile_type_at_cell(Vector2i(x, y)))
	return out

func _count(m: TerrainMap, types: Array[StringName]) -> int:
	var n := 0
	for type in _grid(m):
		if types.has(type):
			n += 1
	return n

func _border_is_obstacle(m: TerrainMap) -> bool:
	for x in range(SIZE.x):
		if m.tile_type_at_cell(Vector2i(x, 0)) != TerrainTypes.OBSTACLE or m.tile_type_at_cell(Vector2i(x, SIZE.y - 1)) != TerrainTypes.OBSTACLE:
			return false
	for y in range(SIZE.y):
		if m.tile_type_at_cell(Vector2i(0, y)) != TerrainTypes.OBSTACLE or m.tile_type_at_cell(Vector2i(SIZE.x - 1, y)) != TerrainTypes.OBSTACLE:
			return false
	return true

func _run_legs() -> void:
	var a := _new_map()
	var b := _new_map()
	var ra := TerrainGen.generate(a, 7, SIZE)
	var rb := TerrainGen.generate(b, 7, SIZE)
	_check(_grid(a) == _grid(b), "same seed -> identical grid over all %d cells" % (SIZE.x * SIZE.y))
	_check(ra["spawn"] == Vector2i(1, 12) and rb["spawn"] == Vector2i(1, 12), "spawn is the left-middle interior cell (1, 12)")
	_check(ra["exit"] == Vector2i(38, 12) and rb["exit"] == Vector2i(38, 12), "exit is the right-middle interior cell (38, 12)")
	var c := _new_map()
	TerrainGen.generate(c, 8, SIZE)
	_check(_grid(a) != _grid(c), "different seed -> different grid")
	_check(a.debug_layer_cells(false).size() == _count(a, [TerrainTypes.OBSTACLE, TerrainTypes.TREE]), "obstacle layer renders exactly the OBSTACLE + TREE cells")
	_check(a.debug_layer_cells(true).size() == _count(a, [TerrainTypes.GRASS, TerrainTypes.SNOW, TerrainTypes.ICE]), "ground layer renders exactly the GRASS + SNOW + ICE cells")
	for m in [a, b, c]:
		m.free()

	var carved := 0
	var both := 0
	var navigable := 0
	var bordered := 0
	for s in range(1, SEEDS + 1):
		var m := _new_map()
		var r := TerrainGen.generate(m, s, SIZE)
		if r["carved"]:
			carved += 1
		if _count(m, [TerrainTypes.GRASS, TerrainTypes.TREE]) > 0 and _count(m, [TerrainTypes.SNOW, TerrainTypes.ICE]) > 0:
			both += 1
		if TerrainNav.is_navigable(m, m.cell_to_world(r["spawn"]), m.cell_to_world(r["exit"])):
			navigable += 1
		if _border_is_obstacle(m):
			bordered += 1
		m.free()
	_check(both == SEEDS, "seeds 1..%d: every map has both grass/forest and snow/ice cells (%d/%d)" % [SEEDS, both, SEEDS])
	_check(navigable == SEEDS, "seeds 1..%d: every map navigable spawn -> exit (%d/%d)" % [SEEDS, navigable, SEEDS])
	_check(bordered == SEEDS, "seeds 1..%d: every border cell is OBSTACLE (%d/%d)" % [SEEDS, bordered, SEEDS])
	print("[164] seeds 1..%d needing a carved corridor: %d" % [SEEDS, carved])

	var w := _new_map()
	var rw := TerrainGen.generate(w, 1, SIZE)
	var seed1 := _grid(w)
	var spawn: Vector2i = rw["spawn"]
	var exit: Vector2i = rw["exit"]
	_check(not TerrainGen.ensure_path(w, 1, spawn, exit), "ensure_path is a no-op on an already navigable map")
	var wall := {}
	for y in range(1, SIZE.y - 1):
		wall[Vector2i(20, y)] = TerrainTypes.TREE
	w.set_cells(wall)
	_check(not TerrainNav.reachable_from_cell(w, spawn).has(exit), "walled-off map: exit unreachable before the guarantee")
	_check(TerrainGen.ensure_path(w, 1, spawn, exit), "ensure_path reports it carved")
	_check(TerrainNav.is_navigable(w, w.cell_to_world(spawn), w.cell_to_world(exit)), "walled-off map navigable after the guarantee")
	var gap := w.tile_type_at_cell(Vector2i(20, 12))
	_check(gap == TerrainTypes.GRASS or gap == TerrainTypes.SNOW, "corridor cell (20, 12) carved to its biome's open tile (%s)" % gap)
	_check(w.tile_type_at_cell(Vector2i(20, 5)) == TerrainTypes.TREE, "wall cell (20, 5) off the corridor left untouched")
	var tw := TerrainMap.new()
	TerrainGen.generate(tw, 1, SIZE)
	_check(_grid(tw) == seed1, "generate on a map outside the tree matches the in-tree grid")
	tw.free()

	var before := _grid(w)
	_check(not w.set_cells({Vector2i(5, 5): TerrainTypes.GRASS, Vector2i(6, 6): &"lava"}), "set_cells refuses a batch with an unregistered type")
	_check(_grid(w) == before, "refused batch left every cell unchanged")
	_check(w.set_cells({Vector2i(5, 5): TerrainTypes.ICE, Vector2i(6, 6): TerrainTypes.GROUND}), "set_cells accepts an all-registered batch")
	_check(w.tile_type_at_cell(Vector2i(5, 5)) == TerrainTypes.ICE and not w.assigned_cells().has(Vector2i(6, 6)), "accepted batch applied (ICE set, GROUND erases)")
	w.free()

	var dmap := scene.get_node_or_null("TerrainMap") as TerrainMap
	_check(dmap != null, "debug scene carries a TerrainMap")
	_check(dmap != null and dmap.assigned_cells().size() == SIZE.x * SIZE.y, "debug map fills all %d cells" % (SIZE.x * SIZE.y))
	_check(dmap != null and dmap.debug_layer_cells(true).size() > 0, "debug map renders ground tiles")
	print("[164] checks complete, failures=", failures)

func _done() -> bool:
	if failures == 0:
		print("[164] PASS")
	else:
		print("[164] DONE failures=", failures)
	quit(0 if failures == 0 else 1)
	return true
