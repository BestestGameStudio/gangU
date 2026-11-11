extends SceneTree
## FlowNav field cache: every cell write (plain set_cell included, e.g. a
## stone block placed by the spell) keeps the cached fields equal to a fresh
## BFS; a write drops only the fields it can affect; a full cache drops the
## least recently used goal.
## Run: godot --headless --path . -s tests/terrain/test_flow_nav_cache.gd

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[flowcache] ", name, " -> PASS")
	else:
		failures += 1
		print("[flowcache] ", name, " -> FAIL")

func _initialize() -> void:
	var m := TerrainMap.new()
	m.cell_size = 32
	root.add_child(m)
	var cells := {}
	for y in range(0, 9):
		for x in range(0, 21):
			if x == 0 or y == 0 or x == 20 or y == 8 or x == 10:
				cells[Vector2i(x, y)] = TerrainTypes.OBSTACLE
	m.set_cells(cells)
	var nav := FlowNav.new()
	nav.bounds = Rect2i(0, 0, 21, 9)
	nav.map = m
	root.add_child(nav)
	var left := Vector2i(2, 4)
	var right := Vector2i(18, 4)

	var before := nav.path(Vector2i(8, 4), left)
	m.set_cell(Vector2i(5, 4), TerrainTypes.BLOCK)
	var after := nav.path(Vector2i(8, 4), left)
	_check(before.has(Vector2i(5, 4)) and not after.has(Vector2i(5, 4)) and nav.field(left) == _fresh(nav, m, left), "a block placed with plain set_cell re-routes the cached field around it (%d -> %d cells)" % [before.size(), after.size()])

	nav.field(left)
	nav.field(right)
	var builds := nav.builds
	m.set_cell(Vector2i(15, 4), TerrainTypes.BLOCK)
	nav.field(left)
	_check(nav.builds == builds, "a write in the right room keeps the left room's field")
	nav.field(right)
	_check(nav.builds == builds + 1 and nav.field(right) == _fresh(nav, m, right), "and rebuilds the right room's field, equal to a fresh BFS")
	builds = nav.builds
	m.set_cell(Vector2i(3, 2), TerrainTypes.GRASS)
	m.set_cell(Vector2i(10, 4), TerrainTypes.OBSTACLE)
	nav.field(left)
	nav.field(right)
	_check(nav.builds == builds, "writes that do not change passability (grass on ground, wall on wall) keep every field")
	m.destroy_cell(Vector2i(15, 4))
	nav.field(left)
	_check(nav.builds == builds, "a cell that becomes passable away from a field keeps that field")
	nav.field(right)
	_check(nav.builds == builds + 1 and nav.field(right) == _fresh(nav, m, right), "and drops the field next to it (destroyed block: right room rebuilt)")

	nav.invalidate()
	var goals: Array[Vector2i] = []
	for i in FlowNav.MAX_FIELDS:
		goals.append(Vector2i(1 + i, 1))
		nav.field(goals[i])
	nav.field(goals[0])
	builds = nav.builds
	nav.field(Vector2i(1, 7))
	nav.field(goals[0])
	_check(nav.builds == builds + 1, "a full cache keeps the recently used goal when it makes room")
	nav.field(goals[1])
	_check(nav.builds == builds + 2, "and drops the least recently used one")
	nav.queue_free()
	m.queue_free()
	print("[flowcache] ", "RESULT: ALL PASS" if failures == 0 else "RESULT: %d FAILED" % failures)
	quit(1 if failures > 0 else 0)

func _fresh(nav: FlowNav, m: TerrainMap, goal: Vector2i) -> Dictionary:
	var f := FlowNav.new()
	f.bounds = nav.bounds
	f.map = m
	var out := f.field(goal)
	f.map = null
	f.free()
	return out
