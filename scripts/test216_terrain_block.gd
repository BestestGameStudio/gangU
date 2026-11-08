extends SceneTree
## #216 harness: the terrain-block spell (headless).
## Proves: the shipped Stone Block resource and its demo reward-table entry;
## the pure TerrainBlock placement rules (range clamp, walkable-only, occupied
## refusal, destroyable-only); the real unlock -> auto-bind -> slot cast path
## on the production player scene places a BLOCK tile with NO projectile and a
## normal cooldown, while refused casts (occupied cell, no terrain) cost no
## cooldown and emit nothing; the block blocks movement and seals a gap; and
## projectile hits destroy it through TerrainMap.destroy_at (#169), restoring
## walkability and navigability, with PIERCING continuing past it, untouched
## non-destroyable tiles, and no terrain hits for a terrain-less source.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if not cond:
		failures += 1
	print("[216] ", name, " -> ", "PASS" if cond else "FAIL")

func _new_map(stage: Node) -> TerrainMap:
	var m := TerrainMap.new()
	m.cell_size = 64
	stage.add_child(m)
	return m

func _projectiles(parent: Node) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for c in parent.get_children():
		if c is Projectile and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _fire(stage: Node, spell: Spell, from: Vector2, dir: Vector2, src: Node2D) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(spell, dir, src)
	stage.add_child(p)
	p.global_position = from
	return p

func _initialize() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	current_scene = stage
	await process_frame

	# --- shipped resources ---
	var spell: Spell = load("res://resources/spells/stone_block.tres")
	_check(spell != null and spell.spell_name == "Stone Block", "Stone Block spell resource loads")
	_check(spell.terrain_block == TerrainTypes.BLOCK and spell.projectile_count == 0, "spell places BLOCK and fires no projectile")
	_check(spell.cooldown == 3.0 and spell.range == 256.0, "placeholder cooldown 3s, range 256px")
	_check(TerrainTypes.is_destroyable(TerrainTypes.BLOCK) and not TerrainTypes.is_walkable(TerrainTypes.BLOCK), "BLOCK is a destroyable, unwalkable tile")
	_check(TerrainTypes.destroyed_into(TerrainTypes.BLOCK) == TerrainTypes.GROUND, "BLOCK breaks into GROUND")
	var table: RewardTable = load("res://resources/rewards/demo_table.tres")
	var entry: RewardEntry = null
	for e in table.entries:
		if e.spell == spell:
			entry = e
	_check(entry != null and entry.kind == RewardEntry.Kind.SPELL and entry.weight == 1.0, "demo reward table carries Stone Block (weight 1.0)")
	_check(table.entries.size() == 4 and table.entries[0].spell.spell_name == "Placeholder Bolt", "existing demo entries preserved, bolt still first")

	# --- pure placement rules ---
	var m := _new_map(stage)
	await process_frame
	var origin := m.cell_to_world(Vector2i(0, 0))
	_check(TerrainBlock.target_cell(m, origin, m.cell_to_world(Vector2i(2, 0)), 256.0) == Vector2i(2, 0), "aim inside range targets the aimed cell")
	_check(TerrainBlock.target_cell(m, origin, m.cell_to_world(Vector2i(20, 0)), 256.0) == Vector2i(4, 0), "aim beyond range is pulled back to range (4 cells)")
	var none: Array[Vector2] = []
	m.set_cell(Vector2i(1, 1), TerrainTypes.WATER)
	_check(not TerrainBlock.can_place(m, Vector2i(1, 1), TerrainTypes.BLOCK, none), "refused on an unwalkable cell (water)")
	_check(not TerrainBlock.can_place(m, Vector2i(2, 2), TerrainTypes.OBSTACLE, none), "refused for a non-destroyable type")
	_check(not TerrainBlock.can_place(m, Vector2i(2, 2), &"lava", none), "refused for an unregistered type")
	var occupied: Array[Vector2] = [m.cell_to_world(Vector2i(2, 2)) + Vector2(20, -20)]
	_check(not TerrainBlock.can_place(m, Vector2i(2, 2), TerrainTypes.BLOCK, occupied), "refused on a cell a body stands in")
	_check(TerrainBlock.place(m, origin, m.cell_to_world(Vector2i(2, 2)), 256.0, TerrainTypes.BLOCK, none) == Vector2i(2, 2), "place returns the placed cell")
	_check(m.tile_type_at_cell(Vector2i(2, 2)) == TerrainTypes.BLOCK and m.debug_layer_cells(false).has(Vector2i(2, 2)), "placed BLOCK is stored and drawn on the obstacle layer")
	_check(TerrainBlock.place(m, origin, m.cell_to_world(Vector2i(2, 2)), 256.0, TerrainTypes.BLOCK, none) == null, "a second block on the same cell is refused")
	m.set_cell(Vector2i(3, 3), TerrainTypes.GRASS)
	_check(TerrainBlock.place(m, origin, m.cell_to_world(Vector2i(3, 3)), 256.0, TerrainTypes.BLOCK, none) == Vector2i(3, 3), "placement allowed on walkable non-default ground (grass)")
	m.queue_free()
	await process_frame

	# --- production composition: real player scene + slot cast ---
	var map := _new_map(stage)
	var player: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(player)
	player.global_position = map.cell_to_world(Vector2i(10, 10))
	player.terrain = map
	await process_frame
	var caster: SpellCaster = player.get_node("SpellCaster")
	caster.unlock_spell(spell)
	var slot := caster.get_slots().find(spell)
	_check(slot != -1, "grant auto-binds Stone Block to a free slot (#262)")
	var aim := caster.get_global_mouse_position()
	var expected := TerrainBlock.target_cell(map, caster.global_position, aim, spell.range)
	var casts := [0]
	var placed: Array = []
	caster.spell_cast.connect(func(_s): casts[0] += 1)
	caster.terrain_block_placed.connect(func(_s, c): placed.append(c))
	_check(map.is_walkable_at_cell(expected) and expected != map.world_to_cell(player.global_position), "fixture: aimed cell is free walkable ground (cell %s)" % [expected])
	caster.cast_slot(slot)
	await process_frame
	_check(map.tile_type_at_cell(expected) == TerrainTypes.BLOCK, "slot cast places a BLOCK at the aimed cell")
	_check(placed == [expected] and casts[0] == 1, "terrain_block_placed + spell_cast fire once")
	_check(_projectiles(stage).is_empty(), "no projectile for the block cast")
	var cd := caster.cooldown_remaining(spell)
	_check(cd > 2.8 and cd <= 3.0, "cast starts the 3s cooldown (%.3f left after a frame)" % cd)
	caster._cooldowns.clear()
	caster.cast_slot(slot)
	await process_frame
	_check(casts[0] == 1 and caster.cooldown_remaining(spell) == 0.0, "refused re-cast on the same cell: no cooldown, no spell_cast")
	map.clear_cell(expected)
	player.terrain = null
	caster.cast_slot(slot)
	await process_frame
	_check(casts[0] == 1 and map.tile_type_at_cell(expected) == TerrainTypes.GROUND and caster.cooldown_remaining(spell) == 0.0, "no terrain in the area: cast refused, nothing placed")
	player.terrain = map
	var under_player := map.world_to_cell(player.global_position)
	var blockers := TerrainBlock.blockers_in(self, player)
	_check(not TerrainBlock.can_place(map, under_player, TerrainTypes.BLOCK, blockers), "the caster's own cell is never a valid target")
	player.queue_free()
	await process_frame

	# --- movement + navigability: a block seals a gap ---
	for y in range(0, 7):
		if y != 3:
			map.set_cell(Vector2i(20, y), TerrainTypes.OBSTACLE)
	var left := map.cell_to_world(Vector2i(17, 3))
	var right := map.cell_to_world(Vector2i(23, 3))
	var bounds := {}
	for x in range(14, 27):
		bounds[Vector2i(x, -1)] = TerrainTypes.OBSTACLE
		bounds[Vector2i(x, 7)] = TerrainTypes.OBSTACLE
	for y in range(-1, 8):
		bounds[Vector2i(14, y)] = TerrainTypes.OBSTACLE
		bounds[Vector2i(26, y)] = TerrainTypes.OBSTACLE
	map.set_cells(bounds)
	_check(TerrainNav.is_navigable(map, left, right), "fixture: the gap at (20,3) connects both sides")
	var gap := Vector2i(20, 3)
	_check(TerrainBlock.place(map, left, map.cell_to_world(gap), 1000.0, TerrainTypes.BLOCK, none) == gap, "block placed in the gap")
	_check(not TerrainNav.is_navigable(map, left, right), "the block seals the gap")
	var before := map.cell_to_world(Vector2i(19, 3)) + Vector2(28, 0)
	var v := TerrainMotion.resolve(map, before, Vector2.ZERO, Vector2(320, 0), 1.0 / 60.0, true)
	_check(v.x <= 0.0, "a mover cannot walk into the block")

	# --- projectile destroys the block (#169 destroy_at) ---
	var events: Array = []
	map.cell_destroyed.connect(func(c, o, n): events.append([c, o, n]))
	var shooter: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(shooter)
	shooter.global_position = map.cell_to_world(Vector2i(16, 5))
	shooter.terrain = map
	shooter.set_physics_process(false)
	shooter.get_node("SpellCaster").set_process(false)
	await process_frame
	var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")
	var p1 := _fire(stage, bolt, left, Vector2.RIGHT, shooter)
	for i in 30:
		await physics_frame
	_check(events == [[gap, TerrainTypes.BLOCK, TerrainTypes.GROUND]], "a bolt hit destroys the block once via destroy_at")
	_check(map.is_walkable_at_cell(gap) and not map.debug_layer_cells(false).has(gap), "destroyed block: walkable again and gone from the obstacle layer")
	_check(TerrainNav.is_navigable(map, left, right), "the gap is navigable again")
	_check(not is_instance_valid(p1) or p1.is_queued_for_deletion(), "a non-piercing projectile despawns on the block")

	# piercing breaks the block and keeps flying
	events.clear()
	map.set_cell(gap, TerrainTypes.BLOCK)
	map.set_cell(Vector2i(22, 3), TerrainTypes.BLOCK)
	var lance: Spell = bolt.duplicate()
	var lance_tags: Array[StringName] = [SpellTags.PIERCING]
	lance.tags = lance_tags
	lance.range = 1000.0
	_fire(stage, lance, left, Vector2.RIGHT, shooter)
	for i in 40:
		await physics_frame
	_check(events.size() == 2 and map.is_walkable_at_cell(gap) and map.is_walkable_at_cell(Vector2i(22, 3)), "a PIERCING projectile breaks both blocks in its path")

	# non-destroyable tiles are untouched and still pass-through
	events.clear()
	var wall := map.cell_to_world(Vector2i(20, 1))
	var p3 := _fire(stage, bolt, wall + Vector2(-150, 0), Vector2.RIGHT, shooter)
	for i in 25:
		await physics_frame
	_check(events.is_empty() and map.tile_type_at_cell(Vector2i(20, 1)) == TerrainTypes.OBSTACLE, "an OBSTACLE wall is not destroyed")
	_check(is_instance_valid(p3) and not p3.is_queued_for_deletion() and p3.global_position.x > wall.x, "projectiles still pass through non-destroyable tiles")

	# a source with no terrain never touches the map
	map.set_cell(gap, TerrainTypes.BLOCK)
	events.clear()
	_fire(stage, bolt, left, Vector2.RIGHT, null)
	for i in 30:
		await physics_frame
	_check(events.is_empty() and map.tile_type_at_cell(gap) == TerrainTypes.BLOCK, "a terrain-less source leaves the block standing")

	print("[216] failures: ", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
