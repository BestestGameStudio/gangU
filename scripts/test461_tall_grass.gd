extends SceneTree
## #461 harness: tall grass (Daniel: "Grass tiles are walkable, but prevent
## characters inside the grass from being seen by characters outside the
## grass. If characters are in the grass they can see other characters in
## the grass within a small radius. Characters are able to see outside of
## the grass freely").
##   (A) registry: TALL_GRASS is walkable, conceals, and only it conceals;
##       the fixed-layout legend knows it.
##   (B) the TallGrass.can_see rule, every case of the issue.
##   (C) an enemy outside the grass loses a player hidden in it (no target,
##       does not close in) and picks them up again once they step out.
##   (D) an enemy in the grass sees a player in the grass close by, and sees
##       a player outside the grass; a player in the grass far away is hidden.
##   (E) drawing: an enemy hidden in the grass is not drawn for a player
##       outside it, and is drawn once the player is in the grass beside it.
##       The player is drawn translucent while concealed.
##   (F) an overworld guard does not aggro on a hidden player in range.
##   (G) summons and homing shots skip enemies hidden in grass.
##   (H) production overworld: tall-grass patches exist on the grid, are
##       walkable, never replace a tree and stay clear of gates, the arrival
##       point and every guard post.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[461] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

## A 64 px grid with a tall-grass block over cells x 10..19, y 0..9
## (world x 640..1280, y 0..640).
func _grass_map() -> TerrainMap:
	var m := TerrainMap.new()
	m.cell_size = 64
	root.add_child(m)
	var cells := {}
	for x in range(10, 20):
		for y in range(0, 10):
			cells[Vector2i(x, y)] = TerrainTypes.TALL_GRASS
	m.set_cells(cells)
	return m

func _player(at: Vector2, map: TerrainMap) -> Player:
	var p: Player = load("res://scenes/player.tscn").instantiate()
	p.add_to_group("player")
	p.collision_layer = 0
	p.collision_mask = 0
	root.add_child(p)
	p.global_position = at
	p.terrain = map
	p.set_physics_process(false)
	return p

func _enemy(at: Vector2, map: TerrainMap, def: EnemyDefinition = null) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.collision_layer = 0
	e.collision_mask = 0
	e.cover_seek = false
	if def != null:
		e.definition = def
	root.add_child(e)
	e.terrain = map
	e.global_position = at
	return e

func _initialize() -> void:
	_registry_legs()
	_rule_legs()
	await _enemy_legs()
	await _overworld_legs()
	print("[461] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

func _registry_legs() -> void:
	_check(TerrainTypes.is_walkable(TerrainTypes.TALL_GRASS), "A: tall grass is walkable")
	_check(TerrainTypes.speed_multiplier(TerrainTypes.TALL_GRASS) == 1.0, "A: tall grass does not slow movement")
	_check(TerrainTypes.conceals(TerrainTypes.TALL_GRASS), "A: tall grass conceals")
	var others := true
	for t: StringName in TerrainTypes.ALL:
		if t != TerrainTypes.TALL_GRASS and TerrainTypes.conceals(t):
			others = false
	_check(others, "A: no other built-in type conceals (plain GRASS included)")
	_check(not TerrainTypes.conceals(&"lava"), "A: unknown type does not conceal")
	_check(not TerrainTypes.properties(TerrainTypes.TALL_GRASS)["blocks_projectiles"], "A: shots fly through tall grass")
	var layout := TerrainFixedLayout.new()
	_check(layout.type_for("w") == TerrainTypes.TALL_GRASS, "A: fixed-layout 'w' is tall grass")

func _rule_legs() -> void:
	var m := _grass_map()
	var out_a := Vector2(400, 300)
	var out_b := Vector2(500, 300)
	var in_a := Vector2(900, 300)
	var in_near := in_a + Vector2(TallGrass.SIGHT_RADIUS - 10.0, 0)
	var in_far := in_a + Vector2(TallGrass.SIGHT_RADIUS + 60.0, 0)
	_check(TallGrass.conceals_at(m, in_a) and not TallGrass.conceals_at(m, out_a), "B: conceals_at reads the grid")
	_check(TallGrass.can_see(m, out_a, out_b), "B: outside sees outside")
	_check(not TallGrass.can_see(m, out_a, in_a), "B: outside cannot see into the grass")
	_check(not TallGrass.can_see(m, Vector2(630, 300), Vector2(650, 300)), "B: outside cannot see in even right at the edge")
	_check(TallGrass.can_see(m, in_a, out_a), "B: inside sees outside freely")
	_check(TallGrass.can_see(m, in_a, in_near), "B: inside sees inside within the small radius")
	_check(not TallGrass.can_see(m, in_a, in_far), "B: inside cannot see inside beyond the radius")
	_check(TallGrass.can_see(null, out_a, in_a), "B: no grid = nobody hidden")
	m.queue_free()

func _enemy_legs() -> void:
	var m := _grass_map()
	# --- (C) outside enemy vs hidden player ---
	var p := _player(Vector2(900, 300), m)
	var e := _enemy(Vector2(500, 300), m)
	await _frames(2)
	_check(e._resolve_target() == null, "C: enemy outside has no target while the player hides in grass")
	var start := e.global_position
	await _frames(45)
	_check(e.global_position.distance_to(start) < 4.0, "C: enemy does not close in on a hidden player")
	p.global_position = Vector2(560, 300) # step out of the grass
	await _frames(2)
	_check(e._resolve_target() == p, "C: the player is a target again once out of the grass")
	await _frames(20)
	_check(e.global_position.x > start.x + 10.0, "C: enemy chases the player out of the grass")
	e.queue_free()

	# --- (D) enemy in the grass ---
	var e2 := _enemy(Vector2(900, 300), m)
	p.global_position = Vector2(900 + TallGrass.SIGHT_RADIUS - 20.0, 300)
	await _frames(2)
	_check(e2._resolve_target() == p, "D: enemy in grass sees a player in grass close by")
	p.global_position = Vector2(1200, 300)
	await _frames(1)
	_check(e2._resolve_target() == null, "D: enemy in grass cannot see a player in grass far away")
	p.global_position = Vector2(400, 300)
	await _frames(1)
	_check(e2._resolve_target() == p, "D: enemy in grass sees a player outside")

	# --- (E) drawing ---
	await process_frame
	_check(not e2.visible, "E: enemy in grass is not drawn for a player outside it")
	_check(is_equal_approx(p.modulate.a, 1.0), "E: player outside the grass is drawn opaque")
	p.global_position = Vector2(900 + 50.0, 300)
	await process_frame
	await process_frame
	_check(e2.visible, "E: enemy is drawn once the player is in the grass beside it")
	_check(p.is_concealed() and p.modulate.a < 1.0, "E: concealed player is drawn translucent")
	var e_out := _enemy(Vector2(300, 300), m)
	await process_frame
	await process_frame
	_check(e_out.visible, "E: enemies outside the grass stay drawn for a player inside it")
	e_out.queue_free()
	e2.queue_free()

	# --- (F) guard aggro ---
	var guard := _enemy(Vector2(560, 300), m, load("res://resources/enemies/overworld_guard.tres") as EnemyDefinition)
	p.global_position = Vector2(720, 300) # 160 px: inside AGGRO_RADIUS, but in grass
	await _frames(30)
	var b := guard._behavior as EnemyBehaviorGuard
	_check(b != null and not b.engaged, "F: guard does not aggro on a player hidden in grass")
	p.global_position = Vector2(620, 300)
	await _frames(3)
	_check(b != null and b.engaged, "F: guard aggros once the player leaves the grass")
	guard.queue_free()

	# --- (G) summons and homing ---
	var hidden := _enemy(Vector2(900, 500), m)
	var open := _enemy(Vector2(300, 500), m)
	hidden.set_physics_process(false)
	open.set_physics_process(false)
	var ally := Summon.new()
	ally.terrain = m
	root.add_child(ally)
	ally.global_position = Vector2(600, 500) # nearer the hidden one
	await process_frame
	var picked := SummonBehaviorGuard.new()._nearest_enemy(ally)
	_check(picked == open, "G: summon skips the nearer enemy hidden in grass")
	ally.global_position = Vector2(880, 500) # summon in the grass next to it
	_check(SummonBehaviorGuard.new()._nearest_enemy(ally) == hidden, "G: summon in grass sees the enemy beside it")
	ally.queue_free()
	hidden.queue_free()
	open.queue_free()
	p.queue_free()
	m.queue_free()
	await _frames(2)

func _overworld_legs() -> void:
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	await _frames(2)
	var ground := area.get_node("Ground") as OverworldGround
	var map := area.get_node("Terrain") as TerrainMap
	_check(ground.grass_patches.size() >= 10, "H: overworld has tall-grass patches (%d)" % ground.grass_patches.size())
	_check(ground.grass_cells.size() > 0, "H: patches are written to the Terrain grid (%d cells)" % ground.grass_cells.size())
	var typed := true
	var walkable := true
	for c in ground.grass_cells:
		if map.tile_type_at_cell(c) != TerrainTypes.TALL_GRASS:
			typed = false
		if not map.is_walkable_at_cell(c):
			walkable = false
	_check(typed, "H: every drawn grass cell is TALL_GRASS on the grid")
	_check(walkable, "H: every grass cell is walkable")
	var trees_kept := true
	for d in ground.decor:
		if d["kind"] == "tree" and map.tile_type_at(d["at"]) != TerrainTypes.OBSTACLE:
			trees_kept = false
	_check(trees_kept, "H: tall grass never replaces a tree's collision")
	_check(not map.conceals_at(ground.spawn), "H: arrival point is open ground")
	var gates_open := true
	for l in ground.landmarks:
		for c in ground.grass_cells:
			if map.cell_to_world(c).distance_to(l) < OverworldGround.GRASS_CLEAR:
				gates_open = false
	_check(gates_open, "H: no tall grass within %d px of a gate" % int(OverworldGround.GRASS_CLEAR))
	var posts_open := true
	for g in area.get_node("EntranceGuards").get_children():
		var guards := g as EntranceGuards
		if guards == null:
			continue
		for entry in guards.entries:
			if map.conceals_at(area.to_global(entry["position"])):
				posts_open = false
	_check(posts_open, "H: no gate guard or patrol spawns inside tall grass")
	_check(ground.grass_top() != null and ground.grass_top().z_index > 0 and ground.grass_top().z_index < OverworldGround.CANOPY_Z,
		"H: grass blades draw over characters, under tree crowns")
	area.queue_free()
	await _frames(2)
