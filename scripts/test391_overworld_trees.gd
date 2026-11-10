extends SceneTree
## #391 harness: overworld trees have collision and enemies pathfind around
## them (Daniel, 2026-11-09: "trees block everything, enemies can pathfind
## around trees, all trees collide").
##   (A) grid population: every decor tree's ground is unwalkable (BLOCKING,
##       non-destroyable), while rocks, the arrival point, every gate and
##       every road stay walkable.
##   (B) movement seam: velocity movement (TerrainMotion.resolve, the
##       walk/dash seam) cannot step into a tree, and clamp_displacement
##       (the knockback/blink/push seam) stops at its edge.
##   (C) enemy pathfinding: a chaser with a tree squarely between it and the
##       player reaches contact WITHOUT ever standing on an unwalkable cell
##       (the pre-#391 axis-slide stalls head-on at a blocking cell).
##   (D) an area without a Terrain node keeps the pre-#391 decor-only
##       behavior (Ground builds fine, nothing marks cells).

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[391] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

## The most isolated tree in the decor: far from other decor, roads and
## gates, with a solid circle. Deterministic decor makes this stable.
func _pick_tree(ground: OverworldGround) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for d in ground.decor:
		if d["kind"] != "tree" or d["r"] < 24.0:
			continue
		var at: Vector2 = d["at"]
		var nearest := INF
		for o in ground.decor:
			if o == d:
				continue
			nearest = minf(nearest, at.distance_to(o["at"]))
		var score := minf(nearest, ground.road_distance(at))
		if score > best_score:
			best_score = score
			best = d
	return best

func _initialize() -> void:
	# Real production scene: ground, roads, gates and the hidden grid.
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	await _frames(2)
	var ground := area.get_node("Ground") as OverworldGround
	var map := area.get_node("Terrain") as TerrainMap

	# --- (A) grid population ---
	_check(map != null, "A: overworld has a Terrain grid")
	_check(map != null and map.cell_size == 32, "A: fine 32px cells")
	var tree_count := 0
	var trees_blocked := true
	var tree_type_ok := true
	var tree_undeletable := true
	for d in ground.decor:
		if d["kind"] != "tree":
			continue
		tree_count += 1
		if map.is_walkable_at(d["at"]):
			trees_blocked = false
		if map.tile_type_at(d["at"]) != TerrainTypes.OBSTACLE:
			tree_type_ok = false
		if map.destroy_at(d["at"]):
			tree_undeletable = false
	_check(tree_count > 0, "A: decor trees exist (%d)" % tree_count)
	_check(trees_blocked, "A: ALL decor trees are unwalkable")
	_check(tree_type_ok, "A: tree cells are non-destroyable OBSTACLE (not destroyable TREE)")
	_check(tree_undeletable, "A: spell damage cannot delete a tree's collision")
	var rocks_walkable := true
	for d in ground.decor:
		if d["kind"] == "rock" and not map.is_walkable_at(d["at"]):
			rocks_walkable = false
	_check(rocks_walkable, "A: rocks stay walkable decor")
	_check(map.is_walkable_at(ground.spawn), "A: arrival point walkable")
	var gates_walkable := true
	for l in ground.landmarks:
		if not map.is_walkable_at(l):
			gates_walkable = false
	_check(gates_walkable, "A: every gate landing walkable")
	var roads_walkable := true
	for road in ground.roads:
		for p in road:
			if not map.is_walkable_at(p):
				roads_walkable = false
	_check(roads_walkable, "A: every road spine walkable")

	# --- (B) movement seam ---
	var tree := _pick_tree(ground)
	var t: Vector2 = tree["at"]
	_check(not tree.is_empty(), "B: found an isolated tree for movement legs")
	var from := t + Vector2(0, 90)
	var pos := from
	var vel := Vector2.ZERO
	var entered := false
	for i in 120:
		var desired := (t - pos).normalized() * 320.0
		vel = TerrainMotion.resolve(map, pos, vel, desired, 1.0 / 60.0, false)
		pos += vel * (1.0 / 60.0)
		if not map.is_walkable_at(pos):
			entered = true
	_check(not entered, "B: velocity movement never enters a tree cell")
	_check(pos.distance_to(t) > 8.0, "B: tree is not crossed (stopped at its edge)")
	var displaced: Vector2 = TerrainMotion.clamp_displacement(map, from, t, false)
	_check(map.is_walkable_at(displaced) and displaced.distance_to(t) > 8.0,
		"B: knockback/blink displacement stops at the tree edge")

	# --- (C) enemy pathfinding around a tree ---
	var player: Player = load("res://scenes/player.tscn").instantiate()
	area.add_child(player)
	player.global_position = t + Vector2(0, 120)
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	area.add_child(enemy)
	enemy.terrain = map
	enemy.global_position = t + Vector2(0, -120)
	# Direct line is blocked: proves the reach is a detour, not a beeline.
	var line_blocked := false
	for i in 25:
		if not map.is_walkable_at(enemy.global_position.lerp(player.global_position, float(i) / 24.0)):
			line_blocked = true
	_check(line_blocked, "C: fixture has the tree blocking the straight line")
	var stepped_on_tree := false
	var reached := false
	for i in 600: # 10s of physics
		await physics_frame
		if not is_instance_valid(enemy):
			break
		if not map.is_walkable_at(enemy.global_position):
			stepped_on_tree = true
		if enemy.global_position.distance_to(player.global_position) <= enemy.contact_range:
			reached = true
			break
	_check(not stepped_on_tree, "C: chaser never stands on a tree cell")
	_check(reached, "C: chaser paths AROUND the tree and reaches the player")
	if is_instance_valid(enemy):
		enemy.queue_free()
	player.queue_free()
	area.queue_free()
	await _frames(2)

	# --- (D) no Terrain sibling: pre-#391 decor-only behavior ---
	var plain := Node2D.new()
	plain.name = "PlainArea"
	var marker := Marker2D.new()
	marker.name = "PlayerSpawn"
	plain.add_child(marker)
	var bare_ground := OverworldGround.new()
	bare_ground.name = "Ground"
	plain.add_child(bare_ground)
	root.add_child(plain)
	await _frames(2)
	_check(bare_ground.decor.size() > 0, "D: ground still builds decor without a Terrain node")
	plain.queue_free()

	await _water_routing_parity()

	print("[391] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

## #281 extraction parity: summons detour finite water, ordinary enemies
## retain #165 shore halt, swimmers cross. Exercise the actual summon
## wrapper as well as the shared helper; do not only test A* internals.
func _water_routing_parity() -> void:
	var map := TerrainMap.new()
	root.add_child(map)
	for y in range(1, 6):
		map.set_cell(Vector2i(4, y), TerrainTypes.WATER)
	var start := Vector2(160, 224)
	var dest := Vector2(480, 224)
	var ally := Summon.new()
	ally.terrain = map
	ally.position = start
	var behavior := SummonBehaviorGuard.new()
	var walker_path := TerrainPath.new()
	var swimmer_path := TerrainPath.new()
	var walker := start
	var swimmer := start
	var walker_velocity := Vector2.ZERO
	var swimmer_velocity := Vector2.ZERO
	var ally_wet := false
	var swimmer_wet := false
	for i in 600:
		if ally.position.distance_to(dest) > 8.0:
			ally.velocity = behavior._steer_toward(ally, dest, 180.0, 1.0 / 60.0)
			ally.position += ally.velocity / 60.0
		ally_wet = ally_wet or not map.is_walkable_at(ally.position)
		if walker.distance_to(dest) > 8.0:
			walker_velocity = walker_path.steer(map, walker, walker_velocity, walker.direction_to(dest) * 180.0, dest, 180.0, 1.0 / 60.0, false)
			walker += walker_velocity / 60.0
		if swimmer.distance_to(dest) > 8.0:
			swimmer_velocity = swimmer_path.steer(map, swimmer, swimmer_velocity, swimmer.direction_to(dest) * 180.0, dest, 180.0, 1.0 / 60.0, true)
			swimmer += swimmer_velocity / 60.0
		swimmer_wet = swimmer_wet or map.tile_type_at(swimmer) == TerrainTypes.WATER
	_check(ally.position.distance_to(dest) <= 8.0, "E: summon detours finite WATER strip and reaches target (#281 parity)")
	_check(not ally_wet, "E: summon detour never enters WATER")
	_check(walker.x < 256.0 and walker_velocity == Vector2.ZERO, "E: ordinary non-swimming enemy still halts at WATER (#165 parity)")
	_check(swimmer_wet and swimmer.distance_to(dest) <= 8.0, "E: swimming enemy crosses WATER directly")
	ally.free()
	map.queue_free()
	await process_frame
