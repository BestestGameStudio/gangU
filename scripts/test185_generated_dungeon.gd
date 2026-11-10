extends SceneTree
## Generated test dungeon: seed determinism and navigability of the scene
## itself, then the production flow through main.tscn (hub gate in, terrain
## wired to Player and enemies, exit portal out), DungeonA left unchanged,
## and real input stopped by a generated wall.

const GENERATED_SCENE := "res://scenes/dungeon_generated.tscn"
const SPAWN_WORLD := Vector2(96, 800)
const EXIT_WORLD := Vector2(2464, 800)
const SEED1_ENEMY_SPAWNS: Array[Vector2] = [Vector2(992, 480), Vector2(1504, 416), Vector2(2144, 800), Vector2(1056, 1248), Vector2(1504, 1056)]

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[185] ", name, " -> PASS")
	else:
		failures += 1
		print("[185] ", name, " -> FAIL")

func _initialize() -> void:
	await _scene_legs()
	await _main_flow_legs()
	print("[185] DONE failures=", failures)
	quit(1 if failures > 0 else 0)

func _instance(map_seed: int) -> Node2D:
	var d: Node2D = (load(GENERATED_SCENE) as PackedScene).instantiate()
	d.set("map_seed", map_seed)
	root.add_child(d)
	return d

func _grid(d: Node) -> Dictionary:
	var terrain: TerrainMap = d.get_node("Terrain")
	var out := {}
	for cell: Vector2i in terrain.assigned_cells():
		out[cell] = terrain.tile_type_at_cell(cell)
	return out

func _entry_positions(d: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for entry: Dictionary in (d.get_node("SpawnData") as AreaSpawnData).entries:
		out.append(entry["position"])
	return out

func _scene_legs() -> void:
	var a := _instance(1)
	var b := _instance(1)
	var other := _instance(2)
	await process_frame
	var terrain: TerrainMap = a.get_node("Terrain")
	var spawn: Vector2 = a.get_node("PlayerSpawn").global_position
	var exit: Vector2 = a.get_node("ExitPoint").global_position
	_check(_grid(a).size() == 960, "seed 1 assigns every cell of the 40x24 map (got %d)" % _grid(a).size())
	_check(_grid(a) == _grid(b), "seed 1 twice: identical terrain grids")
	_check(_grid(a) != _grid(other), "seed 2 builds a different grid")
	_check(spawn == SPAWN_WORLD and b.get_node("PlayerSpawn").global_position == SPAWN_WORLD, "PlayerSpawn at %s both times (got %s)" % [SPAWN_WORLD, spawn])
	_check(exit == EXIT_WORLD and b.get_node("ExitPoint").global_position == EXIT_WORLD, "ExitPoint at %s both times (got %s)" % [EXIT_WORLD, exit])
	var positions := _entry_positions(a)
	_check(positions == SEED1_ENEMY_SPAWNS and _entry_positions(b) == SEED1_ENEMY_SPAWNS, "seed 1 twice: SpawnData at %s (got %s)" % [SEED1_ENEMY_SPAWNS, positions])
	_check(TerrainNav.is_navigable(terrain, spawn, exit), "exit reachable from PlayerSpawn")
	for pos in positions:
		var world := a.to_global(pos)
		_check(terrain.is_walkable_at(world) and TerrainNav.is_navigable(terrain, spawn, world), "enemy spawn %s walkable and reachable" % pos)
		_check(world.distance_to(spawn) >= 6 * 64, "enemy spawn %s at least 6 cells from PlayerSpawn" % pos)
	_check(terrain.tile_type_at(spawn + Vector2(-64, 0)) == TerrainTypes.OBSTACLE, "cell left of PlayerSpawn is the OBSTACLE border")
	for d in [a, b, other]:
		d.queue_free()
	await process_frame

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _enter(main: Node, gate_name: String) -> void:
	if main.area_loader.current_area.get_node_or_null(gate_name) == null:
		main.area_loader.enter_overworld() # #346: dungeon entrances live in the overworld
	var gate: Gate = main.area_loader.current_area.get_node(gate_name)
	gate.entered.emit(gate)
	await _frames(3)

func _main_flow_legs() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	var p: Player = main.get_node("Player")
	_check(main.area_loader.current_area.name == "Hub", "boots into the hub")
	main.area_loader.enter_overworld() # #346: the generated entrance moved to the overworld
	var gate: Gate = main.area_loader.current_area.get_node_or_null("GateGenerated")
	_check(gate != null and gate.gate_type == Gate.GateType.NORMAL, "overworld has a NORMAL GateGenerated")
	_check(gate != null and gate.get_node("TypeLabel").text == "GENERATED", "GateGenerated is labelled GENERATED")
	# #391: the overworld has its own (tree collision) grid since #391.
	_check(p.terrain == main.area_loader.current_area.get_node("Terrain"), "overworld: Player.terrain is the overworld grid")

	await _enter(main, "GateGenerated")
	var area: Node = main.area_loader.current_area
	_check(area.name == "DungeonGenerated", "generated gate leads to DungeonGenerated (got %s)" % area.name)
	var terrain: TerrainMap = area.get_node("Terrain")
	_check(p.global_position == SPAWN_WORLD, "Player placed at PlayerSpawn %s (got %s)" % [SPAWN_WORLD, p.global_position])
	_check(p.terrain == terrain, "Player.terrain is the dungeon's TerrainMap")
	var enemies: Array[Enemy] = []
	for n in area.get_children():
		if n is Enemy:
			enemies.append(n)
	_check(enemies.size() == 5, "5 enemies mounted from SpawnData (got %d)" % enemies.size())
	_check(enemies.all(func(e: Enemy) -> bool: return e.terrain == terrain), "every spawned enemy has .terrain set")
	var portal: ExitPortal = area.get_node_or_null("ExitPortal")
	_check(portal != null and portal.global_position == EXIT_WORLD and not portal.locked, "unlocked ExitPortal at ExitPoint %s" % EXIT_WORLD)
	_check(area.get_node_or_null("DungeonObjective") == null and area.get_node_or_null("ReviveItem") == null, "no objective or revive item in the generated dungeon")

	Input.action_press(&"move_left")
	await _frames(30)
	Input.action_release(&"move_left")
	_check(p.global_position.x < SPAWN_WORLD.x, "move_left moved the player (x %.1f)" % p.global_position.x)
	_check(terrain.world_to_cell(p.global_position) == Vector2i(1, 12), "player stopped before the OBSTACLE cell (0, 12) (in %s)" % terrain.world_to_cell(p.global_position))

	portal.entered.emit(portal)
	await _frames(3)
	_check(main.area_loader.current_area.name == "Overworld", "exit portal returns to the overworld entrance (#378)")
	_check(p.terrain == main.area_loader.current_area.get_node("Terrain"), "back in the overworld: Player.terrain is the overworld grid again (#391)")

	await _enter(main, "GateNormal")
	area = main.area_loader.current_area
	_check(area.name == "DungeonA", "normal gate still leads to DungeonA")
	_check(area.get_node_or_null("DungeonObjective") != null, "DungeonA still mounts its objective")
	var a_portal: ExitPortal = area.get_node_or_null("ExitPortal")
	_check(a_portal != null and a_portal.position == Vector2(576, 120), "DungeonA portal still at (576, 120)")
	_check(area.get_node_or_null("ReviveItem") != null, "DungeonA still mounts its revive item")
	# #396: DungeonA is a terrain map now (fixed hand-designed layout).
	_check(p.terrain != null and p.terrain == area.get_node_or_null("Terrain"), "DungeonA: Player.terrain is DungeonA's own grid (#396)")
