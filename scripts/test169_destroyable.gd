extends SceneTree
## Destroyable terrain: the registry destroyable/destroyed_into data, the
## TerrainMap destroy_cell/destroy_at entry point, its signal, the rendered
## layers, and navigability before and after a destroy.

const GEN_SIZE := Vector2i(40, 24)

var failures := 0
var events: Array = []

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[169] ", name, " -> PASS")
	else:
		failures += 1
		print("[169] ", name, " -> FAIL")

func _initialize() -> void:
	_registry_legs()
	await process_frame
	_destroy_legs()
	_refusal_legs()
	_navigability_legs()
	_world_pos_legs()
	_generated_map_legs()
	print("[169] DONE failures=", failures)
	quit(1 if failures > 0 else 0)

func _new_map() -> TerrainMap:
	var m := TerrainMap.new()
	m.cell_size = 64
	root.add_child(m)
	m.cell_destroyed.connect(func(cell: Vector2i, old_type: StringName, new_type: StringName) -> void:
		events.append([cell, old_type, new_type]))
	return m

func _registry_legs() -> void:
	var destroyable: Array[StringName] = []
	for type: StringName in TerrainTypes.ALL:
		if TerrainTypes.is_destroyable(type):
			destroyable.append(type)
	_check(destroyable == [&"tree"], "only TREE is destroyable among registered types (got %s)" % [destroyable])
	_check(TerrainTypes.destroyed_into(TerrainTypes.TREE) == &"grass", "TREE is destroyed into GRASS")
	_check(TerrainTypes.properties(TerrainTypes.TREE)["destroyable"] == true, "properties() carries destroyable")
	_check(not TerrainTypes.is_destroyable(&"lava") and TerrainTypes.destroyed_into(&"lava") == &"", "unknown type is not destroyable")

func _destroy_legs() -> void:
	var m := _new_map()
	var cell := Vector2i(3, 2)
	m.set_cells({cell: TerrainTypes.TREE, Vector2i(5, 5): TerrainTypes.OBSTACLE, Vector2i(6, 6): TerrainTypes.SNOW})
	var obstacle_before := m.debug_layer_cells(false).size()
	var ground_before := m.debug_layer_cells(true).size()
	_check(obstacle_before == 2 and ground_before == 1, "fixture renders 2 obstacle-layer and 1 ground-layer cells")
	_check(not m.is_walkable_at_cell(cell), "TREE cell starts unwalkable")
	events.clear()
	_check(m.destroy_cell(cell) == true, "destroy_cell on TREE returns true")
	_check(m.tile_type_at_cell(cell) == &"grass", "destroyed TREE cell is now GRASS")
	_check(m.is_walkable_at_cell(cell), "destroyed cell is walkable")
	_check(events == [[cell, &"tree", &"grass"]], "cell_destroyed fired once with (cell, tree, grass) (got %s)" % [events])
	_check(m.debug_layer_cells(false).size() == obstacle_before - 1, "obstacle layer lost exactly one cell")
	_check(m.debug_layer_cells(true).size() == ground_before + 1, "ground layer gained exactly one cell")
	_check(m.debug_layer_cells(true).has(cell) and not m.debug_layer_cells(false).has(cell), "the destroyed cell moved to the ground layer")
	events.clear()
	_check(m.destroy_cell(cell) == false, "destroying the same cell again returns false")
	_check(events.is_empty() and m.tile_type_at_cell(cell) == &"grass", "second destroy emits nothing and leaves GRASS")

func _refusal_legs() -> void:
	var m := _new_map()
	var cases := {
		Vector2i(1, 1): TerrainTypes.OBSTACLE,
		Vector2i(2, 1): TerrainTypes.MOUNTAIN,
		Vector2i(3, 1): TerrainTypes.GRASS,
	}
	m.set_cells(cases)
	cases[Vector2i(4, 1)] = TerrainTypes.GROUND
	var layers_before := [m.debug_layer_cells(false), m.debug_layer_cells(true)]
	_check(layers_before[0].size() == 2 and layers_before[1].size() == 1, "refusal fixture renders 2 obstacle-layer and 1 ground-layer cells")
	for cell: Vector2i in cases:
		events.clear()
		var ok := m.destroy_cell(cell)
		_check(not ok and m.tile_type_at_cell(cell) == cases[cell] and events.is_empty(), "%s refuses destroy: false, unchanged, no signal" % cases[cell])
	_check([m.debug_layer_cells(false), m.debug_layer_cells(true)] == layers_before, "refused destroys leave both layers unchanged")
	_check(m.assigned_cells().size() == 3, "unset GROUND cell stays unassigned")

func _navigability_legs() -> void:
	var m := _new_map()
	var cells := {}
	for y in range(0, 7):
		for x in range(0, 11):
			if x == 0 or y == 0 or x == 10 or y == 6:
				cells[Vector2i(x, y)] = TerrainTypes.OBSTACLE
			elif x == 5:
				cells[Vector2i(x, y)] = TerrainTypes.TREE
	m.set_cells(cells)
	var spawn := m.cell_to_world(Vector2i(2, 3))
	var exit := m.cell_to_world(Vector2i(8, 3))
	_check(not TerrainNav.is_navigable(m, spawn, exit), "TREE wall cuts spawn from exit")
	_check(m.destroy_cell(Vector2i(5, 1)), "destroy one wall tree")
	_check(TerrainNav.is_navigable(m, spawn, exit), "spawn reaches exit through the destroyed tree")

func _world_pos_legs() -> void:
	var m := _new_map()
	m.position = Vector2(100, 40)
	var cell := Vector2i(2, 4)
	m.set_cell(cell, TerrainTypes.TREE)
	var inside := m.cell_to_world(cell) + Vector2(-30, 30)
	_check(m.world_to_cell(inside) == cell, "probe point lies inside the target cell")
	events.clear()
	_check(m.destroy_at(inside) == true, "destroy_at on a TREE world position returns true")
	_check(m.tile_type_at_cell(cell) == &"grass" and events == [[cell, &"tree", &"grass"]], "destroy_at destroyed the containing cell and signalled it")
	_check(m.destroy_at(inside) == false, "destroy_at again returns false")
	_check(m.destroy_at(m.cell_to_world(Vector2i(9, 9))) == false, "destroy_at on unset ground returns false")

func _generated_map_legs() -> void:
	var m := _new_map()
	var info := TerrainGen.generate(m, 1, GEN_SIZE)
	var trees: Array[Vector2i] = []
	for cell: Vector2i in m.assigned_cells():
		if m.tile_type_at_cell(cell) == TerrainTypes.TREE:
			trees.append(cell)
	_check(trees.size() > 0, "seed 1 map has TREE cells (%d)" % trees.size())
	events.clear()
	var destroyed := 0
	for cell in trees:
		if m.destroy_cell(cell):
			destroyed += 1
	_check(destroyed == trees.size() and events.size() == trees.size(), "every TREE destroyed and signalled (%d)" % destroyed)
	var left := 0
	var border_ok := true
	for y in range(GEN_SIZE.y):
		for x in range(GEN_SIZE.x):
			var type := m.tile_type_at_cell(Vector2i(x, y))
			if type == TerrainTypes.TREE:
				left += 1
			if (x == 0 or y == 0 or x == GEN_SIZE.x - 1 or y == GEN_SIZE.y - 1) and type != TerrainTypes.OBSTACLE:
				border_ok = false
	_check(left == 0, "no TREE cells remain")
	_check(border_ok, "border is still all OBSTACLE")
	_check(TerrainNav.reachable_from_cell(m, info["spawn"]).has(info["exit"]), "spawn still reaches exit")
