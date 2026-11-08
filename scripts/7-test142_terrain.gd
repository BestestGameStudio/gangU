extends SceneTree
## #142 (Terrain A1) harness: tile-type registry contract, the TerrainMap
## world-position lookup seam (THE downstream API), presentation derived
## from data, and flood-fill navigability on the flat debug map - plus REAL
## NEGATIVES: a fully blocked map is NOT navigable, obstacle endpoints are
## NOT navigable, invalid types and unknown lookups refuse safely.
## Standalone debug scene only; no production scene is touched or needed.
## Ready notifications are deferred past _initialize, so all tree-dependent
## legs run in phase 0 once every node reports is_node_ready() (repo idiom).

var failures := 0
var phase := 0
var t := 0.0
var m: TerrainMap
var scene: Node2D
var map: TerrainMap

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[142] ", name, " -> PASS")
	else:
		failures += 1
		print("[142] ", name, " -> FAIL")

func _initialize() -> void:
	# --- Registry legs (pure statics, no tree) ---
	_check(TerrainTypes.is_valid(TerrainTypes.GROUND), "GROUND is a registered type")
	_check(TerrainTypes.is_valid(TerrainTypes.OBSTACLE), "OBSTACLE is a registered type")
	_check(not TerrainTypes.is_valid(&"lava"), "unregistered type id refused")
	var gp := TerrainTypes.properties(TerrainTypes.GROUND)
	_check(gp["walkable"] == true and gp["speed_multiplier"] == 1.0, "GROUND walkable, speed 1.0")
	var op := TerrainTypes.properties(TerrainTypes.OBSTACLE)
	_check(op["walkable"] == false and op["speed_multiplier"] == 0.0, "OBSTACLE not walkable, speed 0.0")
	var up := TerrainTypes.properties(&"lava")
	_check(up["walkable"] == false and up["speed_multiplier"] == 0.0 and up["element_tags"].is_empty(), "unknown type gets blocking fallback")
	up["walkable"] = true
	_check(TerrainTypes.properties(&"lava")["walkable"] == false, "returned properties are copies (registry immutable from outside)")
	m = TerrainMap.new()
	root.add_child(m)
	scene = load("res://scenes/test142_terrain_debug.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene

func _process(delta: float) -> bool:
	t += delta
	if phase == 0:
		if not m.is_node_ready() or not scene.is_node_ready():
			if t > 4.0:
				_check(false, "nodes never became ready")
				return _done()
			return false
		_run_tree_legs()
		return _done()
	return true

func _run_tree_legs() -> void:
	# --- Lookup seam legs (standalone map) ---
	_check(m.tile_type_at(Vector2(5000, 5000)) == TerrainTypes.GROUND, "unset far cell reads as GROUND default")
	_check(m.is_walkable_at(Vector2(5000, 5000)), "unset cell is walkable (flat-world default)")
	_check(not m.set_cell(Vector2i(2, 2), &"lava"), "set_cell refuses unregistered type")
	_check(m.tile_type_at_cell(Vector2i(2, 2)) == TerrainTypes.GROUND, "refused write left no residue")
	_check(m.set_cell(Vector2i(2, 2), TerrainTypes.OBSTACLE), "set_cell OBSTACLE accepted")
	var center: Vector2 = m.cell_to_world(Vector2i(2, 2))
	_check(m.world_to_cell(center) == Vector2i(2, 2), "cell_to_world center round-trips to the same cell")
	_check(m.tile_type_at(center) == TerrainTypes.OBSTACLE, "world-pos lookup returns assigned type")
	_check(not m.is_walkable_at(center), "OBSTACLE cell not walkable via world pos")
	var pp := m.properties_at(center)
	_check(pp["type"] == TerrainTypes.OBSTACLE and pp["walkable"] == false, "properties_at merges type + registry data")
	_check(m.world_to_cell(Vector2(-1, -1)) == Vector2i(-1, -1), "negative world coords floor to the containing cell")
	_check(m.set_cell(Vector2i(2, 2), TerrainTypes.GROUND), "GROUND write accepted (reset)")
	_check(m.tile_type_at_cell(Vector2i(2, 2)) == TerrainTypes.GROUND, "reset cell reads as default again")
	_check(m.assigned_cells().is_empty(), "sparse store empty after reset")

	# --- Debug scene legs ---
	map = scene.get_node_or_null("TerrainMap") as TerrainMap
	_check(map != null, "debug scene carries a TerrainMap")
	var spawn: Vector2 = scene.spawn_world()
	var exit: Vector2 = scene.exit_world()
	_check(map.is_walkable_at(spawn), "spawn point on walkable ground")
	_check(map.is_walkable_at(exit), "exit point on walkable ground")
	var wall := map.cell_to_world(Vector2i(9, 3))
	_check(map.tile_type_at(wall) == TerrainTypes.OBSTACLE and not map.is_walkable_at(wall), "wall cell lookup: OBSTACLE, not walkable")
	var gap := map.cell_to_world(Vector2i(9, 5))
	_check(map.tile_type_at(gap) == TerrainTypes.GROUND and map.is_walkable_at(gap), "wall gap cell lookup: GROUND, walkable")

	# Presentation derived from data: the two contract layers exist and the
	# obstacle layer carries exactly the assigned non-walkable cells.
	_check(map.get_node_or_null("Ground") is TileMapLayer, "Ground TileMapLayer present")
	_check(map.get_node_or_null("Obstacle") is TileMapLayer, "Obstacle TileMapLayer present")
	var obstacle_cells := map.debug_layer_cells(false)
	_check(obstacle_cells.size() == map.assigned_cells().size(), "obstacle layer cell count == assigned non-walkable cell count")
	_check(obstacle_cells.has(Vector2i(9, 3)), "obstacle layer renders the wall cell")
	_check(not obstacle_cells.has(Vector2i(1, 5)), "no tile painted on the open spawn cell")

	# --- Navigability legs ---
	_check(TerrainNav.is_navigable(map, spawn, exit), "debug map: walkable path spawn -> exit")
	var reach := TerrainNav.reachable(map, spawn)
	_check(reach.has(map.world_to_cell(spawn)) and reach.has(map.world_to_cell(exit)), "reachable set contains spawn and exit cells")
	_check(not reach.has(Vector2i(9, 3)), "reachable set excludes wall cells")
	_check(reach.size() > 50 and reach.size() < 1000, "flood fill bounded and covers the open field (%d cells)" % reach.size())

	# REAL NEGATIVE 1: same field, wall with NO gap -> not navigable.
	var blocked := TerrainMap.new()
	root.add_child(blocked)
	for x in range(18):
		blocked.set_cell(Vector2i(x, 0), TerrainTypes.OBSTACLE)
		blocked.set_cell(Vector2i(x, 9), TerrainTypes.OBSTACLE)
	for y in range(10):
		blocked.set_cell(Vector2i(0, y), TerrainTypes.OBSTACLE)
		blocked.set_cell(Vector2i(17, y), TerrainTypes.OBSTACLE)
	for y in range(1, 9):
		blocked.set_cell(Vector2i(9, y), TerrainTypes.OBSTACLE)
	var bspawn := blocked.cell_to_world(Vector2i(1, 5))
	var bexit := blocked.cell_to_world(Vector2i(16, 5))
	_check(not TerrainNav.is_navigable(blocked, bspawn, bexit), "gap-less wall map is NOT navigable")
	_check(not TerrainNav.reachable(blocked, bspawn).has(Vector2i(16, 5)), "blocked fill never crosses the wall")
	# REAL NEGATIVE 2: endpoints on unwalkable terrain are not navigable.
	_check(not TerrainNav.is_navigable(blocked, blocked.cell_to_world(Vector2i(9, 3)), bexit), "start on an obstacle is NOT navigable")
	_check(not TerrainNav.is_navigable(blocked, bspawn, blocked.cell_to_world(Vector2i(9, 3))), "target on an obstacle is NOT navigable")
	_check(TerrainNav.reachable(blocked, blocked.cell_to_world(Vector2i(9, 3))).is_empty(), "fill from an obstacle reaches nothing")
	blocked.queue_free()
	print("[142] checks complete, failures=", failures)

func _done() -> bool:
	if failures == 0:
		print("[142] PASS")
	else:
		print("[142] DONE failures=", failures)
	quit(0 if failures == 0 else 1)
	return true
