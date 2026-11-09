extends SceneTree
## #367 harness: maze map generator for defense missions - enemies spawn at
## the maze's edge entrances and pathfind through it to the objective.
## Run: godot --headless --path . -s scripts/test367_maze_defense.gd
##
## Legs:
##   (A) MazeGen: deterministic per seed, different across seeds; for many
##       seeds every entrance is a walkable gap in the outer wall on its own
##       side, the whole maze is one connected region sealed inside its
##       bounds, the objective/spawn/exit are walkable, and it is a real
##       maze (mostly wall, entrance->objective path much longer than the
##       straight distance).
##   (B) FlowNav: entrance -> objective path is 4-connected, walkable, as long
##       as the BFS distance; waypoint() aims at the next cell's centre and at
##       the real target in the goal cell; no map / unreachable falls back to
##       the target; a changed cell drops the cached fields.
##   (C) dungeon_maze.tscn: core on the objective, one WaveSpawns marker per
##       entrance, FlowNav wired to the Terrain.
##   (D) overworld GateMaze: NORMAL gate to DungeonMaze, >= 200 px from others.
##   (E) production flow: GateMaze -> DEFENSE objective dungeon_maze with the
##       area's FlowNav; waves spawn in the entrances, every wave enemy has
##       the nav; a core attacker walks the maze from its entrance to the core
##       without ever standing in a wall and damages it; a player hunter
##       finds the player in a far corner of the maze.
##   (F) unchanged elsewhere: DungeonE wave enemies carry no nav, and a
##       nav-less enemy still chases in a straight line.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[367] ", name, " -> PASS")
	else:
		failures += 1
		print("[367] ", name, " -> FAIL")

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	Bestiary.save_path = "user://test367_bestiary.cfg"
	await _leg_generator()
	await _leg_nav()
	await _leg_scene()
	await _leg_overworld()
	for s in FLOW_SEEDS:
		await _leg_flow(s)
	MazeDefenseDungeon.forced_seed = -1
	await _leg_unchanged()
	print("[367] DONE failures=", failures)
	print("RESULT: ALL PASS" if failures == 0 else "RESULT: FAIL")
	quit(failures)

func _new_map() -> TerrainMap:
	var m := TerrainMap.new()
	root.add_child(m)
	return m

func _snapshot(m: TerrainMap) -> Dictionary:
	var out := {}
	for c in m.assigned_cells():
		out[c] = m.tile_type_at_cell(c)
	return out

func _leg_generator() -> void:
	var m1 := _new_map()
	var m2 := _new_map()
	var m3 := _new_map()
	var r1 := MazeGen.generate(m1, 7)
	var r2 := MazeGen.generate(m2, 7)
	MazeGen.generate(m3, 8)
	_check(_snapshot(m1) == _snapshot(m2) and r1["entrances"] == r2["entrances"], "(A) same seed -> same maze and entrances")
	_check(_snapshot(m1) != _snapshot(m3), "(A) different seed -> different maze")
	for m in [m1, m2, m3]:
		m.queue_free()
	await process_frame

	var ok_count := true
	var ok_sides := true
	var ok_gap := true
	var ok_reach := true
	var ok_sealed := true
	var ok_points := true
	var ok_maze := true
	var ok_detour := true
	var seeds := 25
	var path_total := 0
	var straight_total := 0
	for s in seeds:
		var m := _new_map()
		var r := MazeGen.generate(m, 1000 + s)
		var bounds: Rect2i = r["bounds"]
		var cs := float(m.cell_size)
		var goal := m.world_to_cell(m.to_global(r["objective"]))
		var reach := TerrainNav.reachable_from_cell(m, goal)
		var reach_set := {}
		for c in reach:
			reach_set[c] = true
		ok_count = ok_count and r["entrances"].size() == MazeGen.DEFAULT_ENTRANCES
		var sides := {}
		for sd in r["entrance_sides"]:
			sides[sd] = true
		ok_sides = ok_sides and sides.size() == 4
		for gap: Array in r["entrance_cells"]:
			for c: Vector2i in gap:
				var on_border := c.x == 1 or c.y == 1 or c.x == bounds.size.x - 2 or c.y == bounds.size.y - 2
				ok_gap = ok_gap and on_border and m.is_walkable_at_cell(c)
				ok_reach = ok_reach and reach_set.has(c)
		# Every walkable cell inside the bounds is one region with the goal,
		# and that region never leaves the bounds' interior.
		var floor_cells := 0
		for y in bounds.size.y:
			for x in bounds.size.x:
				if m.is_walkable_at_cell(Vector2i(x, y)):
					floor_cells += 1
					ok_reach = ok_reach and reach_set.has(Vector2i(x, y))
		for c: Vector2i in reach:
			ok_sealed = ok_sealed and c.x >= 1 and c.y >= 1 and c.x <= bounds.size.x - 2 and c.y <= bounds.size.y - 2
		for key in ["objective", "player_spawn", "exit"]:
			ok_points = ok_points and m.is_walkable_at(m.to_global(r[key]))
		var total := bounds.size.x * bounds.size.y
		ok_maze = ok_maze and float(floor_cells) / float(total) < 0.65
		var nav := FlowNav.new()
		nav.bounds = bounds
		root.add_child(nav)
		nav.map = m
		for at: Vector2 in r["entrances"]:
			var from := m.world_to_cell(m.to_global(at + Vector2(-1, -1)))
			var steps := nav.distance(from, goal)
			var straight := (from - goal).abs()
			ok_detour = ok_detour and steps > 0 and steps >= straight.x + straight.y
			path_total += steps
			straight_total += straight.x + straight.y
		nav.queue_free()
		m.queue_free()
		await process_frame
	_check(ok_count, "(A) %d seeds: %d entrances each" % [seeds, MazeGen.DEFAULT_ENTRANCES])
	_check(ok_sides, "(A) one entrance per side (W, E, N, S)")
	_check(ok_gap, "(A) entrances are walkable gaps in the outer maze wall")
	_check(ok_reach, "(A) every entrance and every floor cell connects to the objective")
	_check(ok_sealed, "(A) the walkable region is sealed inside the map (no walking off the edge)")
	_check(ok_points, "(A) objective, player spawn and exit are on floor")
	_check(ok_maze, "(A) it is a maze: under 65% of the map is floor")
	_check(ok_detour, "(A) entrance -> objective path >= its Manhattan distance")
	var ratio := float(path_total) / float(maxi(straight_total, 1))
	_check(ratio >= 1.5, "(A) routes wind: entrance paths average %.2fx their Manhattan distance" % ratio)

func _leg_nav() -> void:
	var m := _new_map()
	var r := MazeGen.generate(m, 42)
	var nav := FlowNav.new()
	root.add_child(nav)
	nav.bounds = r["bounds"]
	nav.map = m
	var goal := m.world_to_cell(m.to_global(r["objective"]))
	var start: Vector2i = r["entrance_cells"][0][0]
	for gap: Array in r["entrance_cells"]:
		if nav.distance(gap[0], goal) > nav.distance(start, goal):
			start = gap[0]
	var p := nav.path(start, goal)
	var ok := p.size() == nav.distance(start, goal) + 1 and p[0] == start and p[-1] == goal
	for i in p.size():
		ok = ok and m.is_walkable_at_cell(p[i])
		if i > 0:
			ok = ok and (p[i] - p[i - 1]).abs().x + (p[i] - p[i - 1]).abs().y == 1
	_check(ok, "(B) entrance -> objective path: %d cells, 4-connected, all floor" % p.size())
	# Longer than a straight line through the walls: the maze matters.
	var straight := (start - goal).abs()
	_check(p.size() - 1 > straight.x + straight.y, "(B) path detours (%d steps vs %d straight)" % [p.size() - 1, straight.x + straight.y])
	var target_px: Vector2 = m.to_global(r["objective"])
	_check(nav.waypoint(m.cell_to_world(start), target_px) == m.cell_to_world(p[1]), "(B) waypoint() aims at the next path cell's centre")
	var near := m.cell_to_world(goal) + Vector2(5, 5)
	_check(nav.waypoint(near, target_px) == target_px, "(B) in the goal cell waypoint() aims at the target itself")
	var wall := Vector2i(0, 0)
	_check(nav.waypoint(m.cell_to_world(wall), target_px) == target_px, "(B) off the field: falls back to the target (straight chase)")
	var bare := FlowNav.new()
	_check(bare.waypoint(Vector2(1, 2), Vector2(300, 400)) == Vector2(300, 400), "(B) no map: falls back to the target")
	bare.free()
	var builds := nav.builds
	nav.waypoint(m.cell_to_world(start), target_px)
	_check(nav.builds == builds, "(B) the goal's field is cached (no re-BFS)")
	m.set_cell(p[3], TerrainTypes.TREE)
	m.destroy_cell(p[3])
	nav.waypoint(m.cell_to_world(start), target_px)
	_check(nav.builds == builds + 1, "(B) a changed map cell drops the cached fields")
	nav.queue_free()
	m.queue_free()
	await process_frame

func _leg_scene() -> void:
	var a: Node2D = (load("res://scenes/dungeon_maze.tscn") as PackedScene).instantiate()
	a.randomize_seed = false
	a.map_seed = 5
	root.add_child(a)
	await process_frame
	_check(a.name == "DungeonMaze", "(C) root is named DungeonMaze")
	var terrain := a.get_node("Terrain") as TerrainMap
	var core := a.get_node("DefenseCore") as DefenseCore
	_check(core.global_position.is_equal_approx(terrain.to_global(a.maze["objective"])), "(C) DefenseCore sits on the maze objective")
	var spawns := a.get_node("WaveSpawns").get_children()
	var ok: bool = spawns.size() == a.maze["entrances"].size() and spawns.size() >= 1
	for i in spawns.size():
		ok = ok and (spawns[i] as Node2D).global_position.is_equal_approx(terrain.to_global(a.maze["entrances"][i]))
	_check(ok, "(C) one WaveSpawns marker per maze entrance (%d)" % spawns.size())
	var nav := a.get_node("FlowNav") as FlowNav
	_check(nav.map == terrain and nav.bounds == a.maze["bounds"], "(C) FlowNav wired to the maze Terrain and bounds")
	_check(terrain.is_walkable_at(a.get_node("PlayerSpawn").global_position) and terrain.is_walkable_at(a.get_node("ExitPoint").global_position),
		"(C) PlayerSpawn and ExitPoint are on floor")
	_check(a.get_node_or_null("SpawnData") == null, "(C) no SpawnData: enemies come from waves")
	a.queue_free()
	await process_frame

func _leg_overworld() -> void:
	var ow: Node = (load("res://scenes/overworld.tscn") as PackedScene).instantiate()
	root.add_child(ow)
	await process_frame
	var g := ow.get_node_or_null("GateMaze") as Gate
	_check(g != null and g.gate_type == Gate.GateType.NORMAL and g.target_dungeon != null \
		and g.target_dungeon.resource_path == "res://scenes/dungeon_maze.tscn", "(D) GateMaze is a NORMAL gate to DungeonMaze")
	if g != null:
		_check((g.get_node("TypeLabel") as Label).text == "MAZE", "(D) gate label reads MAZE")
		var ok := true
		for c in ow.get_children():
			if c != g and c is Gate and (c as Node2D).position.distance_to(g.position) < 200.0:
				ok = false
		_check(ok, "(D) >= 200px from every other gate")
		_check((ow.get_node("Ground") as OverworldGround).covers(g.position), "(D) overworld ground covers it")
	ow.queue_free()
	await process_frame

func _wave_enemies(area: Node) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in get_nodes_in_group(&"enemies"):
		if e.get_parent() == area and (e as Enemy).hp > 0:
			out.append(e)
	return out

## Production flow is replayed on several pinned mazes (production rolls a
## fresh seed per visit).
const FLOW_SEEDS: Array[int] = [11, 22, 33, 44, 55]

func _leg_flow(maze_seed: int) -> void:
	MazeDefenseDungeon.forced_seed = maze_seed
	print("[367] --- (E) flow on maze seed ", maze_seed)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var p: Player = main.get_node("Player")
	p.max_hp = 100000
	p.hp = 100000
	main.enter_overworld()
	await _physics(4)
	var gate := main.current_area.get_node("GateMaze") as Gate
	gate._on_body_entered(p)
	await _physics(4)
	var area: Node = main.current_area
	_check(area.name == "DungeonMaze", "(E) GateMaze enters DungeonMaze (got %s)" % area.name)
	var obj := area.get_node_or_null("DungeonObjective") as DungeonObjective
	_check(obj != null and obj.objective_type == DungeonObjective.ObjectiveType.DEFENSE and obj.dungeon_id == &"dungeon_maze",
		"(E) DEFENSE objective dungeon_maze mounted")
	if obj == null:
		main.queue_free()
		return
	var nav := area.get_node("FlowNav") as FlowNav
	var terrain := area.get_node("Terrain") as TerrainMap
	_check(obj.wave_nav == nav, "(E) the objective hands out the area's FlowNav")
	_check(obj.core() == area.get_node("DefenseCore"), "(E) the maze's DefenseCore is the defended core")
	var portal := area.get_node_or_null("ExitPortal") as ExitPortal
	_check(portal != null and not portal.locked and terrain.is_walkable_at(portal.global_position), "(E) normal gate: exit portal unlocked, on floor")
	_check(terrain.is_walkable_at(p.global_position) and p.terrain == terrain, "(E) player arrives on floor in the chamber")
	obj.spawn_next_wave()
	# Hold later waves: their enemies would crowd the walks measured below.
	obj.set_physics_process(false)
	await _physics(2)
	var wave := _wave_enemies(area)
	_check(wave.size() == obj.wave_size(1), "(E) wave 1: %d enemies" % wave.size())
	var entrances: Array = []
	for mk in area.get_node("WaveSpawns").get_children():
		entrances.append((mk as Node2D).global_position)
	var at_entrances := true
	var all_nav := true
	for e in wave:
		all_nav = all_nav and e.nav == nav
		var near := false
		for at: Vector2 in entrances:
			near = near or e.global_position.distance_to(at) < 64.0
		at_entrances = at_entrances and near
	_check(all_nav, "(E) every wave enemy carries the FlowNav")
	_check(at_entrances, "(E) every wave enemy spawns at a maze entrance")
	var core := obj.core()
	var attackers := wave.filter(func(e: Enemy) -> bool: return e.objective_target == core)
	var hunters := wave.filter(func(e: Enemy) -> bool: return e.objective_target == null)
	_check(not attackers.is_empty(), "(E) the wave has core attackers (%d) - mixed targeting kept" % attackers.size())

	# Core attacker walks the maze. Player parked outside the maze, others off.
	if not attackers.is_empty():
		var a: Enemy = attackers[0]
		for e in wave:
			if e != a:
				e.process_mode = Node.PROCESS_MODE_DISABLED
		p.global_position = Vector2(-20000, -20000)
		var start := a.global_position
		var steps := nav.distance(terrain.world_to_cell(start), terrain.world_to_cell(core.global_position))
		var hp0 := core.hp
		var in_wall := false
		var frames := 0
		while core.hp == hp0 and frames < 7200:
			await physics_frame
			frames += 1
			if not terrain.is_walkable_at(a.global_position):
				in_wall = true
		_check(core.hp < hp0, "(E) core attacker reached and damaged the core through the maze (%d frames, %d-cell path)" % [frames, steps])
		_check(not in_wall, "(E) ...without ever standing inside a wall")
		for e in wave:
			e.process_mode = Node.PROCESS_MODE_INHERIT

	# Player hunter tracks the player to a far corner room of the maze.
	if not hunters.is_empty():
		var h: Enemy = hunters[0]
		# Remove (not freeze) the others: a frozen body parked in a corridor
		# would block the hunter's way, which live enemies never do for long.
		for e in _wave_enemies(area):
			if e != h:
				e.queue_free()
		await process_frame
		var maze: Dictionary = area.maze
		var hcell := terrain.world_to_cell(h.global_position)
		var best := Vector2i.ZERO
		var best_d := -1
		var rooms: Vector2i = maze["rooms"]
		for corner in [Vector2i(0, 0), Vector2i(rooms.x - 1, 0), Vector2i(0, rooms.y - 1), Vector2i(rooms.x - 1, rooms.y - 1)]:
			var c: Vector2i = MazeGen.room_cells(corner)[0]
			var d := nav.distance(hcell, c)
			if d > best_d:
				best_d = d
				best = c
		p.global_position = terrain.cell_to_world(best)
		var frames := 0
		var in_wall := false
		while h.global_position.distance_to(p.global_position) > h.contact_range and frames < 7200:
			await physics_frame
			frames += 1
			if not terrain.is_walkable_at(h.global_position):
				in_wall = true
		_check(h.global_position.distance_to(p.global_position) <= h.contact_range,
			"(E) player hunter found the player %d cells away through the maze (%d frames)" % [best_d, frames])
		_check(not in_wall, "(E) ...without ever standing inside a wall")
	main.queue_free()
	current_scene = null
	await process_frame

func _leg_unchanged() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	main._swap((load("res://scenes/dungeon_e.tscn") as PackedScene).instantiate())
	await _physics(2)
	var obj := main.current_area.get_node("DungeonObjective") as DungeonObjective
	_check(obj.wave_nav == null, "(F) DungeonE objective has no FlowNav")
	obj.spawn_next_wave()
	await _physics(2)
	var ok := true
	for e in _wave_enemies(main.current_area):
		ok = ok and e.nav == null
	_check(ok, "(F) DungeonE wave enemies carry no nav (straight chase as before)")
	main.queue_free()
	current_scene = null
	await process_frame
	# A nav-less enemy on a bare map heads straight at its target.
	var e: Enemy = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
	var target := DefenseCore.new()
	root.add_child(target)
	root.add_child(e)
	target.global_position = Vector2(400, 300)
	e.global_position = Vector2(100, 0)
	e.objective_target = target
	await _physics(1)
	var before := e.global_position
	await _physics(10)
	var moved := (e.global_position - before).normalized()
	var want := (target.global_position - before).normalized()
	_check(moved.dot(want) > 0.99, "(F) nav-less enemy still chases in a straight line")
	e.queue_free()
	target.queue_free()
	await process_frame
