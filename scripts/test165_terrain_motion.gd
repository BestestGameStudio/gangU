extends SceneTree
## Terrain movement rules: the pure TerrainMotion resolver, the registry
## movement properties, and real Player/Enemy nodes moving over hand-placed
## cells. Bodies get collision_layer/mask 0 so terrain is the only thing
## that stops them (the test99 fixture idiom).

const DT := 1.0 / 60.0

var failures := 0
var _player_scene: PackedScene = preload("res://scenes/player.tscn")
var _enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[165] ", name, " -> PASS")
	else:
		failures += 1
		print("[165] ", name, " -> FAIL")

func _initialize() -> void:
	_registry_legs()
	var pure := _new_map()
	await process_frame
	_resolver_legs(pure)
	await _player_legs()
	await _enemy_legs()
	print("[165] DONE failures=", failures)
	quit(1 if failures > 0 else 0)

func _new_map() -> TerrainMap:
	var m := TerrainMap.new()
	m.cell_size = 64
	root.add_child(m)
	return m

func _fill_row(m: TerrainMap, row: int, from_x: int, to_x: int, type: StringName) -> void:
	var cells := {}
	for x in range(from_x, to_x + 1):
		cells[Vector2i(x, row)] = type
	m.set_cells(cells)

func _registry_legs() -> void:
	var expected := {
		TerrainTypes.GROUND: [1.0, false], TerrainTypes.OBSTACLE: [1.0, false], TerrainTypes.GRASS: [1.0, false],
		TerrainTypes.TREE: [1.0, false], TerrainTypes.SNOW: [1.0, false], TerrainTypes.ICE: [0.12, false],
		TerrainTypes.MUD: [1.0, false], TerrainTypes.WATER: [1.0, true], TerrainTypes.MOUNTAIN: [1.0, false],
		TerrainTypes.BLOCK: [1.0, false],
	}
	_check(expected.size() == TerrainTypes.ALL.size(), "every registered type has an expectation (%d types)" % TerrainTypes.ALL.size())
	for type: StringName in TerrainTypes.ALL:
		var e: Array = expected.get(type, [-1.0, false])
		_check(is_equal_approx(TerrainTypes.friction(type), e[0]) and TerrainTypes.is_swimmable(type) == e[1], "%s friction %s swimmable %s" % [type, e[0], e[1]])
	_check(TerrainTypes.friction(&"lava") == 1.0 and TerrainTypes.is_swimmable(&"lava") == false, "unknown type: friction 1.0, not swimmable")
	_check(TerrainTypes.properties(&"lava")["walkable"] == false, "unknown type still blocks")
	_check(TerrainTypes.is_walkable(TerrainTypes.MUD) and TerrainTypes.speed_multiplier(TerrainTypes.MUD) == 0.5, "MUD walkable at speed 0.5")
	_check(not TerrainTypes.is_walkable(TerrainTypes.WATER) and TerrainTypes.speed_multiplier(TerrainTypes.WATER) == 0.6 and TerrainTypes.element_tags(TerrainTypes.WATER) == [&"water"], "WATER unwalkable, swim speed 0.6, water tag")
	_check(not TerrainTypes.is_walkable(TerrainTypes.MOUNTAIN), "MOUNTAIN not walkable")
	for type: StringName in [TerrainTypes.MUD, TerrainTypes.WATER, TerrainTypes.MOUNTAIN]:
		_check(TerrainMap.TYPE_COLORS.has(type), "%s has a debug color" % type)

func _resolver_legs(m: TerrainMap) -> void:
	var right := Vector2(320, 0)
	_check(TerrainMotion.resolve(null, Vector2(5, 5), Vector2(99, 99), Vector2(123.5, -7.25), DT, false) == Vector2(123.5, -7.25), "null map returns desired unchanged")
	_check(TerrainMotion.resolve(m, Vector2(32, 32), Vector2.ZERO, right, DT, false) == right, "GROUND returns desired exactly")

	m.set_cell(Vector2i(0, 2), TerrainTypes.GRASS)
	_check(TerrainMotion.resolve(m, Vector2(32, 160), Vector2.ZERO, right, DT, false) == right, "GRASS returns desired exactly")

	_fill_row(m, 4, 0, 1, TerrainTypes.MUD)
	_check(TerrainMotion.resolve(m, Vector2(40, 288), Vector2.ZERO, right, DT, false) == Vector2(160, 0), "MUD halves speed: (320,0) -> (160,0)")

	_fill_row(m, 6, 0, 3, TerrainTypes.ICE)
	var ice_pos := Vector2(96, 416)
	var v := TerrainMotion.resolve(m, ice_pos, Vector2.ZERO, right, DT, false)
	_check(v.x > 0.0 and v.x < 320.0 and v.is_equal_approx(Vector2(7.2, 0)), "ICE from rest accelerates to (7.2,0) after one step (got %s)" % v)
	v = TerrainMotion.resolve(m, ice_pos, right, Vector2.ZERO, DT, false)
	_check(v.is_equal_approx(Vector2(312.8, 0)), "ICE with no input still slides at (312.8,0) after one step (got %s)" % v)
	v = right
	for i in 44:
		v = TerrainMotion.resolve(m, ice_pos, v, Vector2.ZERO, DT, false)
	_check(v.x > 0.0, "ICE still sliding after 44 steps (%.2f)" % v.x)
	v = TerrainMotion.resolve(m, ice_pos, v, Vector2.ZERO, DT, false)
	_check(v == Vector2.ZERO, "ICE stops at step 45 (0.75s from 320 px/s)")

	m.set_cell(Vector2i(1, 8), TerrainTypes.WATER)
	var shore := Vector2(60, 544)
	_check(TerrainMotion.resolve(m, shore, Vector2.ZERO, right, DT, false) == Vector2.ZERO, "WATER blocks a non-swimmer")
	_check(TerrainMotion.resolve(m, shore, Vector2.ZERO, right, DT, true) == right, "WATER admits a swimmer from the shore")
	_check(TerrainMotion.resolve(m, Vector2(96, 544), Vector2.ZERO, right, DT, true) == Vector2(192, 0), "swimmer in WATER moves at 0.6 speed: (192,0)")
	_check(TerrainMotion.resolve(m, Vector2(96, 544), Vector2.ZERO, right, DT, false) == right, "non-swimmer inside WATER walks out at full speed")

	for pair: Array in [[10, TerrainTypes.MOUNTAIN], [12, TerrainTypes.OBSTACLE], [14, TerrainTypes.TREE]]:
		m.set_cell(Vector2i(1, pair[0]), pair[1])
		var pos := Vector2(60, pair[0] * 64 + 32)
		_check(TerrainMotion.resolve(m, pos, Vector2.ZERO, right, DT, false) == Vector2.ZERO, "%s blocks" % pair[1])
		_check(TerrainMotion.resolve(m, pos, Vector2.ZERO, Vector2(320, 320), DT, false) == Vector2(0, 320), "diagonal into %s slides along it: (0,320)" % pair[1])
		_check(TerrainMotion.resolve(m, Vector2(96, pair[0] * 64 + 32), Vector2.ZERO, right, DT, false) == right, "mover inside %s can move out" % pair[1])

	m.set_cell(Vector2i(1, 17), TerrainTypes.MOUNTAIN)
	var corner := Vector2(60, 16 * 64 + 60)
	_check(TerrainMotion.resolve(m, corner, Vector2.ZERO, Vector2(320, 320), DT, false) == Vector2(320, 0), "diagonal into a blocked corner cell keeps the x component when both axis cells are open")

func _spawn_player(terrain: TerrainMap, pos: Vector2) -> Player:
	var p: Player = _player_scene.instantiate() as Player
	p.collision_layer = 0
	p.collision_mask = 0
	p.terrain = terrain
	root.add_child(p)
	p.global_position = pos
	return p

func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame

func _player_legs() -> void:
	var world := _new_map()
	_fill_row(world, 2, 0, 30, TerrainTypes.MUD)
	world.set_cell(Vector2i(3, 4), TerrainTypes.MOUNTAIN)
	_fill_row(world, 6, 0, 30, TerrainTypes.ICE)
	world.set_cell(Vector2i(3, 10), TerrainTypes.WATER)
	world.set_cell(Vector2i(3, 12), TerrainTypes.WATER)
	var starts: Array[Vector2] = [Vector2(32, 32), Vector2(32, 160), Vector2(40, 288), Vector2(32, 416), Vector2(32, 544), Vector2(40, 672), Vector2(40, 800)]
	var ground := _spawn_player(world, starts[0])
	var mud := _spawn_player(world, starts[1])
	var wall := _spawn_player(world, starts[2])
	var ice := _spawn_player(world, starts[3])
	var plain := _spawn_player(null, starts[4])
	var swimmer := _spawn_player(world, starts[5])
	var landlocked := _spawn_player(world, starts[6])
	landlocked.can_swim = false
	var players: Array[Player] = [ground, mud, wall, ice, plain, swimmer, landlocked]
	await _physics_frames(2)
	for i in players.size():
		players[i].global_position = starts[i]
		players[i].velocity = Vector2.ZERO

	Input.action_press(&"move_right")
	await _physics_frames(30)
	var ground_dx := ground.global_position.x - 32.0
	var mud_dx := mud.global_position.x - 32.0
	_check(is_equal_approx(ground_dx, 160.0), "player on GROUND covers 160px in 30 frames (%.2f)" % ground_dx)
	_check(is_equal_approx(mud_dx, 80.0), "player on MUD covers half that, 80px (%.2f)" % mud_dx)
	_check(plain.velocity == Vector2(1, 0) * plain.speed, "terrain null: velocity is exactly input_dir * speed (%s)" % plain.velocity)
	await _physics_frames(30)
	_check(wall.global_position.x < 192.0 and wall.global_position.x > 180.0, "player stops short of the MOUNTAIN cell at x=192 (x=%.2f)" % wall.global_position.x)
	_check(wall.velocity == Vector2.ZERO, "player against MOUNTAIN has zero velocity")
	_check(world.tile_type_at(wall.global_position) == TerrainTypes.GROUND, "player never entered the MOUNTAIN cell")
	_check(swimmer.can_swim, "player can swim by default")
	_check(swimmer.global_position.x > 256.0, "default player swims through the WATER cell at x=192..256 (x=%.2f)" % swimmer.global_position.x)
	_check(landlocked.global_position.x < 192.0 and landlocked.velocity == Vector2.ZERO, "player with can_swim off halts at the WATER edge x=192 (x=%.2f)" % landlocked.global_position.x)

	Input.action_release(&"move_right")
	var ice_x := ice.global_position.x
	await _physics_frames(10)
	_check(ground.velocity == Vector2.ZERO, "player on GROUND stops as soon as input is released")
	_check(ice.velocity.x > 0.0 and ice.global_position.x > ice_x, "player on ICE keeps sliding 10 frames after release (v=%.2f, +%.2fpx)" % [ice.velocity.x, ice.global_position.x - ice_x])
	await _physics_frames(40)
	_check(ice.velocity == Vector2.ZERO, "player on ICE comes to rest within 50 frames of release")

func _spawn_chase(terrain: TerrainMap, row_y: float, can_swim: bool, tag: String) -> Enemy:
	var target: Player = _player_scene.instantiate() as Player
	target.name = "Target" + tag
	target.collision_layer = 0
	target.collision_mask = 0
	root.add_child(target)
	target.global_position = Vector2(1500, row_y)
	var e: Enemy = _enemy_scene.instantiate() as Enemy
	e.collision_layer = 0
	e.collision_mask = 0
	e.terrain = terrain
	e.can_swim = can_swim
	e.player_path = NodePath("../Target" + tag)
	root.add_child(e)
	e.global_position = Vector2(32, row_y)
	return e

func _enemy_legs() -> void:
	var world := _new_map()
	_fill_row(world, 14, 0, 30, TerrainTypes.MUD)
	_fill_row(world, 16, 2, 3, TerrainTypes.WATER)
	_fill_row(world, 18, 2, 3, TerrainTypes.WATER)
	var rows: Array[float] = [12 * 64 + 32, 14 * 64 + 32, 16 * 64 + 32, 18 * 64 + 32]
	var ground := _spawn_chase(world, rows[0], false, "G")
	var mud := _spawn_chase(world, rows[1], false, "M")
	var walker := _spawn_chase(world, rows[2], false, "W")
	var swimmer := _spawn_chase(world, rows[3], true, "S")
	var enemies: Array[Enemy] = [ground, mud, walker, swimmer]
	await process_frame
	for i in enemies.size():
		enemies[i].global_position = Vector2(32, rows[i])
		enemies[i].velocity = Vector2.ZERO
		var target := root.get_node("Target" + "GMWS"[i]) as Player
		target.set_physics_process(false)
		target.global_position = Vector2(1500, rows[i])

	await _physics_frames(30)
	var ground_dx := ground.global_position.x - 32.0
	var mud_dx := mud.global_position.x - 32.0
	_check(ground.velocity == Vector2(110, 0) and mud.velocity == Vector2(55, 0), "enemy chases at (110,0) on GROUND and (55,0) on MUD")
	_check(ground_dx > 50.0 and is_equal_approx(mud_dx, ground_dx * 0.5), "enemy on MUD covers half the GROUND distance (%.2f vs %.2f)" % [mud_dx, ground_dx])
	await _physics_frames(120)
	_check(walker.global_position.x < 128.0 and walker.velocity == Vector2.ZERO, "non-swimming enemy halts at the WATER edge x=128 (x=%.2f)" % walker.global_position.x)
	_check(world.tile_type_at(swimmer.global_position) == TerrainTypes.WATER, "swimming enemy entered the WATER (x=%.2f)" % swimmer.global_position.x)
	_check(swimmer.velocity.is_equal_approx(Vector2(66, 0)), "swimming enemy moves at 0.6 speed in WATER (%s)" % swimmer.velocity)
