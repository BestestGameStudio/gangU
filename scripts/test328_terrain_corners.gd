extends SceneTree
## #328: movers must not walk through terrain corners. A diagonal step that
## changes both the column and the row of the mover's cell is refused when
## either side cell is blocked, so nothing slips between two diagonally
## touching walls or clips the corner of a single wall. Covers the pure
## resolver, clamp_displacement (pushes/blinks), and real Player / Enemy
## nodes walking diagonally at a wall gap. Bodies get collision 0 so terrain
## is the only thing that stops them (the test165 idiom).

const DT := 1.0 / 60.0

var failures := 0
var _player_scene: PackedScene = preload("res://scenes/player.tscn")
var _enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[328] ", name, " -> PASS")
	else:
		failures += 1
		print("[328] ", name, " -> FAIL")

func _initialize() -> void:
	var m := _new_map()
	await process_frame
	_resolver_legs(m)
	_displacement_legs(m)
	await _player_legs()
	await _enemy_legs()
	print("[328] DONE failures=", failures)
	print("RESULT: ", "ALL PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)

func _new_map() -> TerrainMap:
	var m := TerrainMap.new()
	m.cell_size = 64
	root.add_child(m)
	return m

## Two walls touching only at a corner: (1,0) and (0,1). The mover sits in
## (0,0) just above-left of the shared corner (64,64).
func _gap_map(m: TerrainMap, origin: Vector2i, type: StringName) -> void:
	m.set_cells({origin + Vector2i(1, 0): type, origin + Vector2i(0, 1): type})

func _resolver_legs(m: TerrainMap) -> void:
	var diag := Vector2(320, 320)
	# Diagonal wall gap, for every blocking kind.
	var row := 0
	for type: StringName in [TerrainTypes.MOUNTAIN, TerrainTypes.OBSTACLE, TerrainTypes.TREE, TerrainTypes.BLOCK, TerrainTypes.WATER]:
		var o := Vector2i(0, row)
		_gap_map(m, o, type)
		var pos := Vector2(63, row * 64 + 63)
		var v := TerrainMotion.resolve(m, pos, Vector2.ZERO, diag, DT, false)
		_check(v == Vector2.ZERO, "diagonal through the gap between two %s cells is blocked (got %s)" % [type, v])
		_check(m.world_to_cell(pos + v * DT) == o, "mover stays in its own cell at the %s gap" % type)
		row += 3
	# A swimmer may cross the water gap (both side cells are enterable to it).
	_check(TerrainMotion.resolve(m, Vector2(63, 12 * 64 + 63), Vector2.ZERO, diag, DT, true) == diag, "a swimmer still crosses a WATER gap diagonally")
	# Single wall corner: only (1,15) blocked; moving from (0,15) to (1,16)
	# would clip its bottom-left corner. The y slide stays allowed.
	m.set_cell(Vector2i(1, 15), TerrainTypes.MOUNTAIN)
	var clip := Vector2(63, 15 * 64 + 63)
	var v2 := TerrainMotion.resolve(m, clip, Vector2.ZERO, diag, DT, false)
	_check(v2 == Vector2(0, 320), "diagonal past a single wall corner slides along it instead of clipping it (got %s)" % v2)
	# Open diagonal: nothing blocked around (0,18) -> full diagonal velocity.
	_check(TerrainMotion.resolve(m, Vector2(63, 18 * 64 + 63), Vector2.ZERO, diag, DT, false) == diag, "open diagonal still moves at full velocity")
	# The #165 rule still holds: blocked diagonal cell, open sides -> keep x.
	m.set_cell(Vector2i(1, 22), TerrainTypes.MOUNTAIN)
	_check(TerrainMotion.resolve(m, Vector2(60, 21 * 64 + 60), Vector2.ZERO, diag, DT, false) == Vector2(320, 0), "blocked diagonal cell with open sides keeps the x component")

func _displacement_legs(m: TerrainMap) -> void:
	# Gap at origin (0,24): walls (1,24) and (0,25). A push/blink straight
	# across the shared corner stops before it.
	_gap_map(m, Vector2i(0, 24), TerrainTypes.MOUNTAIN)
	var from := Vector2(32, 24 * 64 + 32)
	var to := TerrainMotion.clamp_displacement(m, from, from + Vector2(128, 128), false)
	_check(m.world_to_cell(to) == Vector2i(0, 24), "a diagonal push across a wall gap stops in the start cell (landed %s)" % m.world_to_cell(to))
	var open_from := Vector2(32, 28 * 64 + 32)
	var open_to := TerrainMotion.clamp_displacement(m, open_from, open_from + Vector2(128, 128), false)
	_check(open_to == open_from + Vector2(128, 128), "an open diagonal push is unchanged")

func _physics_frames(n: int) -> void:
	for i in n:
		await physics_frame

## A diagonal wall line from (3,0) down-left to (0,3): cells touch only at
## corners. A player walking down-right from the top-left pocket must never
## end up on the far side.
func _player_legs() -> void:
	var world := _new_map()
	var cells := {}
	for i in range(0, 8):
		cells[Vector2i(7 - i, i)] = TerrainTypes.MOUNTAIN
	world.set_cells(cells)
	var p: Player = _player_scene.instantiate() as Player
	p.collision_layer = 0
	p.collision_mask = 0
	p.terrain = world
	root.add_child(p)
	await _physics_frames(2)
	var start := Vector2(160, 160) # cell (2,2), inside the pocket (x + y < 7)
	p.global_position = start
	p.velocity = Vector2.ZERO
	Input.action_press(&"move_right")
	Input.action_press(&"move_down")
	var crossed := false
	for i in 120:
		await physics_frame
		var c := world.world_to_cell(p.global_position)
		if c.x + c.y > 7:
			crossed = true
		if not world.is_walkable_at(p.global_position):
			crossed = true
	Input.action_release(&"move_right")
	Input.action_release(&"move_down")
	var c_end := world.world_to_cell(p.global_position)
	_check(not crossed, "player walking diagonally into a corner-touching wall line never crosses it (ended in %s)" % c_end)
	_check(c_end.x + c_end.y < 7, "player stays inside the pocket (cell %s)" % c_end)
	p.queue_free()
	world.queue_free()
	await process_frame

func _enemy_legs() -> void:
	var world := _new_map()
	var cells := {}
	for i in range(0, 8):
		cells[Vector2i(7 - i, i)] = TerrainTypes.MOUNTAIN
	world.set_cells(cells)
	var target: Player = _player_scene.instantiate() as Player
	target.name = "Target328"
	target.collision_layer = 0
	target.collision_mask = 0
	root.add_child(target)
	var e: Enemy = _enemy_scene.instantiate() as Enemy
	e.collision_layer = 0
	e.collision_mask = 0
	e.terrain = world
	e.can_swim = false
	e.player_path = NodePath("../Target328")
	root.add_child(e)
	await process_frame
	target.set_physics_process(false)
	target.global_position = Vector2(64 * 8, 64 * 8) # far side of the line, straight down-right
	e.global_position = Vector2(160, 160)
	e.velocity = Vector2.ZERO
	var crossed := false
	for i in 240:
		await physics_frame
		var c := world.world_to_cell(e.global_position)
		if c.x + c.y > 7 or not world.is_walkable_at(e.global_position):
			crossed = true
	_check(not crossed, "chasing enemy never squeezes through the corner-touching wall line (ended in %s)" % world.world_to_cell(e.global_position))
