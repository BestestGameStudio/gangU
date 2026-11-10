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

## One single-step ordering shot along row 0 of `omap` (map-local y = 32):
## BLOCK at `block_cell`, a stationary real Enemy at map-local x = `enemy_x`,
## projectile from x = 32 flying RIGHT. Returns what happened after ONE step.
func _order_case(stage: Node, omap: TerrainMap, src: Node2D, s: Spell, block_cell: Vector2i, enemy_x: float, order: Array) -> Dictionary:
	order.clear()
	omap.set_cell(block_cell, TerrainTypes.BLOCK)
	var e: Node2D = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(e)
	e.global_position = omap.to_global(Vector2(enemy_x, 32))
	e.set_physics_process(false)
	await physics_frame
	await physics_frame # body registered in the physics space
	var p := _fire(stage, s, omap.to_global(Vector2(32, 32)), Vector2.RIGHT, src)
	p.hit.connect(func(_b): order.append("body"))
	var start_x := p.global_position.x
	await physics_frame
	var out := {
		"block_gone": omap.tile_type_at_cell(block_cell) != TerrainTypes.BLOCK,
		"enemy_hp": float(e.hp),
		"consumed": not is_instance_valid(p) or p.is_queued_for_deletion(),
		"order": order.duplicate(),
	}
	_check(out.consumed or p.global_position.x - start_x > 250.0, "fixture: one step spans block and enemy")
	if is_instance_valid(p):
		p.queue_free()
	e.queue_free()
	omap.clear_cell(block_cell)
	await physics_frame
	return out

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
	# #465 (Daniel, 2026-11-09: regular mobs drop currency only): the
	# production mob table no longer carries spells, so the Stone Block
	# SPELL reward wiring is pinned with an in-code fixture entry.
	var table := RewardTable.new()
	var entry := RewardEntry.new()
	entry.kind = RewardEntry.Kind.SPELL
	entry.spell = spell
	entry.weight = 1.0
	var fixture_entries: Array[RewardEntry] = [entry]
	table.entries = fixture_entries
	_check(table.roll([]) == entry, "fixture reward table rolls the Stone Block spell entry (weight 1.0)")

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

	# non-destroyable tiles are untouched; #433 made them solid cover
	events.clear()
	var wall := map.cell_to_world(Vector2i(20, 1))
	var p3 := _fire(stage, bolt, wall + Vector2(-150, 0), Vector2.RIGHT, shooter)
	var blocked_at: Array = [] # lambda writes need a reference type
	p3.blocked.connect(func(): blocked_at.append(p3.global_position))
	for i in 25:
		await physics_frame
	_check(events.is_empty() and map.tile_type_at_cell(Vector2i(20, 1)) == TerrainTypes.OBSTACLE, "an OBSTACLE wall is not destroyed")
	# #433: the pass-through carve-out is superseded - a non-destroyable
	# wall cell is solid cover now and stops the shot at its face (the
	# cell's left edge here: 20 * 64 = 1280).
	_check(not blocked_at.is_empty() and absf((blocked_at[0] as Vector2).x - (wall.x - 32.0)) < 1.0, "a non-destroyable wall now blocks the shot at its face (#433)")

	# a source with no terrain never touches the map
	map.set_cell(gap, TerrainTypes.BLOCK)
	events.clear()
	_fire(stage, bolt, left, Vector2.RIGHT, null)
	for i in 30:
		await physics_frame
	_check(events.is_empty() and map.tile_type_at_cell(gap) == TerrainTypes.BLOCK, "a terrain-less source leaves the block standing")

	# --- review: body and terrain hits resolve in flight order within ONE step ---
	# speed 16000 at 60 Hz = ~267 px per physics step, so a single segment
	# spans both the block and the enemy in every case below.
	var omap := _new_map(stage)
	omap.position = Vector2(0, 4096) # away from every earlier fixture
	var oshooter: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(oshooter)
	oshooter.global_position = omap.to_global(Vector2(32, 600)) # off the flight line
	oshooter.terrain = omap
	oshooter.set_physics_process(false)
	oshooter.get_node("SpellCaster").set_process(false)
	await process_frame
	var fast: Spell = bolt.duplicate()
	fast.projectile_speed = 16000.0
	fast.range = 1000.0
	fast.damage = 7.0
	fast.radius = 4.0
	var fast_pierce: Spell = fast.duplicate()
	var fp_tags: Array[StringName] = [SpellTags.PIERCING]
	fast_pierce.tags = fp_tags
	var order: Array = []
	omap.cell_destroyed.connect(func(c, _o, _n): order.append("block"))

	# block (cell 2) nearer than enemy (x=224): the block absorbs the shot
	var r := await _order_case(stage, omap, oshooter, fast, Vector2i(2, 0), 224.0, order)
	_check(r.block_gone and r.enemy_hp == 30.0, "non-piercing: nearer block destroyed, farther enemy untouched (hp %s)" % r.enemy_hp)
	_check(r.consumed and r.order == ["block"], "non-piercing: projectile consumed by the block, nothing else hit")
	# enemy (x=96) nearer than block (cell 3): the enemy consumes the shot
	r = await _order_case(stage, omap, oshooter, fast, Vector2i(3, 0), 96.0, order)
	_check(r.enemy_hp < 30.0 and not r.block_gone, "non-piercing: nearer enemy damaged, farther block intact")
	_check(r.consumed and r.order == ["body"], "non-piercing: projectile consumed by the enemy, nothing else hit")
	# piercing: both resolve, in flight order, and the shot keeps flying
	r = await _order_case(stage, omap, oshooter, fast_pierce, Vector2i(2, 0), 224.0, order)
	_check(r.block_gone and r.enemy_hp < 30.0 and not r.consumed, "piercing: block then enemy both hit in one step, shot continues")
	_check(r.order == ["block", "body"], "piercing: block resolved before the farther enemy (%s)" % [r.order])
	r = await _order_case(stage, omap, oshooter, fast_pierce, Vector2i(3, 0), 96.0, order)
	_check(r.block_gone and r.enemy_hp < 30.0 and not r.consumed, "piercing: enemy then block both hit in one step, shot continues")
	_check(r.order == ["body", "block"], "piercing: enemy resolved before the farther block (%s)" % [r.order])
	# re-review: the shot STARTS overlapping the enemy (x=32, the spawn point);
	# that initial contact is t=0 and must sort before the farther block (cell 2)
	r = await _order_case(stage, omap, oshooter, fast, Vector2i(2, 0), 32.0, order)
	_check(r.enemy_hp < 30.0 and not r.block_gone, "initial overlap, non-piercing: overlapped enemy damaged, farther block intact (hp %s)" % r.enemy_hp)
	_check(r.consumed and r.order == ["body"], "initial overlap, non-piercing: consumed by the overlapped enemy (%s)" % [r.order])
	r = await _order_case(stage, omap, oshooter, fast_pierce, Vector2i(2, 0), 32.0, order)
	_check(r.block_gone and r.enemy_hp < 30.0 and not r.consumed, "initial overlap, piercing: overlapped enemy then block both hit, shot continues")
	_check(r.order == ["body", "block"], "initial overlap, piercing: overlapped enemy resolved first (%s)" % [r.order])
	_check(r.enemy_hp == 23.0, "initial overlap, piercing: enemy hit exactly once (hp %s)" % r.enemy_hp)

	print("[216] failures: ", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
