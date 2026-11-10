extends SceneTree
## #281 harness: the guard ally pathfinds AROUND unwalkable terrain instead
## of walking through it (Daniel, 2026-11-08).
## Proves: SummonManager injects the area's Terrain node into summon.terrain;
## with a solid wall between ally and enemy the ally reaches contact WITHOUT
## ever standing on an unwalkable cell (the old direct-chase behavior stalls
## at that wall); a null-terrain ally keeps the #280 direct behavior; the
## no-enemy follow/hold rules are unchanged with terrain wired.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[281] ", name, " -> ", "PASS" if cond else "FAIL")

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	var map := TerrainMap.new()
	map.name = "Terrain"
	stage.add_child(map)
	await process_frame
	# Solid wall: cell column x=5, rows 0..9 (non-walkable). Route exists
	# around row 10+. Direct axis-slide stalls against it.
	for y in range(10):
		map.set_cell(Vector2i(5, y), TerrainTypes.OBSTACLE)

	var def: SummonDefinition = load("res://resources/summons/ally.tres")
	var player: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(player)
	player.global_position = Vector2(96, 96)
	var manager := SummonManager.new()
	manager.caster_path = NodePath("../Stage/Player/SpellCaster")
	root.add_child(manager)
	await process_frame

	# Enemy behind the wall; terrain-wired so its own chase stalls there and
	# the fixture stays deterministic (enemy pathfinding is NOT #281 scope).
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy)
	enemy.terrain = map
	enemy.global_position = Vector2(576, 352) # cell (8,5) center, behind the wall

	# --- wiring: the manager injects the area's Terrain node ---
	var ally: Summon = manager.request_spawn(def, Vector2(160, 352)) # cell (2,5) center
	await process_frame
	_check(ally.terrain == map, "manager injects the area's TerrainMap into summon.terrain")

	# --- route-around: reaches the enemy without entering an unwalkable cell ---
	var enemy_hp0: int = enemy.hp
	var crossed := false
	var frames := 0
	while frames < 900:
		await physics_frame
		frames += 1
		if not map.is_walkable_at(ally.global_position):
			crossed = true
			break
		if is_instance_valid(enemy) and ally.global_position.distance_to(enemy.global_position) <= def.contact_range + 4.0:
			break
		if not is_instance_valid(enemy):
			break
	_check(not crossed, "pathfind: ally never enters an unwalkable cell while routing around the wall")
	var reached := false
	if is_instance_valid(enemy):
		reached = ally.global_position.distance_to(enemy.global_position) <= def.contact_range + 4.0 or enemy.hp < enemy_hp0
	else:
		reached = true # enemy died to the ally = contact achieved
	_check(reached, "pathfind: ally reaches contact behind a wall the old direct chase stalled against")
	if is_instance_valid(enemy):
		enemy.queue_free()
	if is_instance_valid(ally):
		ally.queue_free()
	await process_frame

	# --- null-terrain parity: no grid wired, exact #280 direct chase ---
	player.global_position = Vector2(2000, 2000)
	var enemy_b: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy_b)
	enemy_b.global_position = Vector2(4000, 2000)
	var ally_b: Summon = manager.request_spawn(def, Vector2(4060, 2000))
	await process_frame
	ally_b.terrain = null # harness without a Terrain node idiom
	var d0: float = ally_b.global_position.distance_to(enemy_b.global_position)
	for i in 20:
		await physics_frame
	_check(ally_b.global_position.distance_to(enemy_b.global_position) < d0 - 20.0, "null terrain: direct #280 chase unchanged (no lookup, no pathfinding)")
	if is_instance_valid(enemy_b):
		enemy_b.queue_free()
	if is_instance_valid(ally_b):
		ally_b.queue_free()
	await process_frame

	# --- no live enemies: hold unchanged with terrain wired ---
	player.global_position = Vector2(4096, 4096)
	var ally_c: Summon = manager.request_spawn(def, Vector2(4160, 4096))
	await process_frame
	var idle_pos: Vector2 = ally_c.global_position
	for i in 20:
		await physics_frame
	_check(ally_c.global_position.distance_to(idle_pos) < 1.0, "no enemies: ally holds position inside the follow band with terrain wired")
	if is_instance_valid(ally_c):
		ally_c.queue_free()
	await process_frame

	print("[281] failures: ", failures)
	quit(1 if failures > 0 else 0)
