extends SceneTree
## #443 harness: mustache men throw rocks from behind cover (Daniel,
## 2026-11-09: "When hiding behind cover mustache men throw rocks. Rocks go
## over terrain like barricades and trees"; answers: low damage, only while
## hiding behind cover, rocks fly toward the player, over low cover only -
## maze walls and stone blocks still block them).
##   (A) vocabulary + data: LOBBED is a known tag; the rock spell is a
##       lobbed projectile with low damage (below the mob's contact hit).
##   (B) TerrainMap.is_low_cover_cell: TREE and overworld-tree canopy cells
##       are low; plain OBSTACLE walls, MOUNTAIN and BLOCK are not.
##   (C) a rock flies over a TREE cell (not destroyed) and over an overworld
##       tree (canopy circle + OBSTACLE cells) and hits the player behind.
##   (D) a rock is stopped by a maze wall (OBSTACLE) and by a stone block.
##   (E) a rock flies over a cover-group solid (crate, undamaged) and over
##       another enemy (no friendly fire), then hits the player.
##   (F) regression: an ordinary (non-lobbed) shot is still blocked by the
##       tree canopy (#407).
##   (G) behavior: a mustache man HOLDing behind an overworld tree throws
##       rocks at the player, which land and deal damage.
##   (H) behind a maze wall (high cover) it holds but throws nothing.
##   (I) not hiding (no cover anywhere - plain chase): no rocks.
##   (J) the rock lands just past the aim point: a player who moved away
##       takes no damage and the rock is gone.

const DT := 1.0 / 60.0
var failures := 0
var _bolt: Spell
var _rock: Spell

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[443] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _gone(p: Variant) -> bool:
	return not is_instance_valid(p) or p.is_queued_for_deletion()

func _mk_stage() -> Array:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var map := TerrainMap.new()
	map.name = "Terrain"
	map.cell_size = 32
	stage.add_child(map)
	return [stage, map]

func _mk_player(stage: Node2D, map: TerrainMap, pos: Vector2) -> Player:
	var p: Player = load("res://scenes/player.tscn").instantiate()
	p.name = "Player"
	p.set_process(false)
	stage.add_child(p)
	p.global_position = pos
	p.terrain = map
	p.set_physics_process(false)
	p.get_node("SpellCaster").set_process(false)
	return p

func _mk_enemy(stage: Node2D, map: TerrainMap, pos: Vector2) -> Enemy:
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	e.player_path = NodePath("../Player")
	e.terrain = map
	e.set_physics_process(false)
	stage.add_child(e)
	e.global_position = pos
	return e

func _fire(stage: Node, spell: Spell, from: Vector2, dir: Vector2, src: Node2D) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(spell, dir, src)
	if spell.tags.has(SpellTags.LOBBED):
		p.visual_override = RockVisual.new()
	stage.add_child(p)
	p.global_position = from
	return p

func _fly(p: Projectile, n: int) -> Vector2:
	var last := p.global_position
	for i in n:
		await physics_frame
		if _gone(p):
			break
		last = p.global_position
	return last

func _cover(e: Enemy) -> EnemyBehaviorCover:
	return (e.get("_behavior") as RefCounted).get("_cover") as EnemyBehaviorCover

func _teardown(stage: Node) -> void:
	stage.queue_free()
	await process_frame
	await process_frame

func _initialize() -> void:
	_bolt = load("res://resources/spells/placeholder_bolt.tres")
	_rock = load("res://resources/spells/mustache_rock.tres")
	_leg_a()
	_leg_b()
	await _leg_c()
	await _leg_d()
	await _leg_e()
	await _leg_f()
	await _leg_g()
	await _leg_h()
	await _leg_i()
	await _leg_j()
	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)

func _leg_a() -> void:
	_check(SpellTags.LOBBED in SpellTags.ALL, "A: LOBBED is in the tag vocabulary")
	_check(_rock.tags.has(SpellTags.LOBBED) and _rock.tags.has(SpellTags.PROJECTILE) and SpellTags.unknown_tags(_rock.tags).is_empty(), "A: rock is a lobbed projectile with known tags")
	var e: Enemy = load("res://scenes/enemy.tscn").instantiate()
	_check(_rock.damage > 0.0 and _rock.damage < float(e.contact_damage), "A: low damage (%.0f < contact %d)" % [_rock.damage, e.contact_damage])
	e.free()

func _leg_b() -> void:
	var map := TerrainMap.new()
	map.cell_size = 32
	map.set_cells({Vector2i(0, 0): TerrainTypes.TREE, Vector2i(1, 0): TerrainTypes.OBSTACLE,
		Vector2i(2, 0): TerrainTypes.MOUNTAIN, Vector2i(3, 0): TerrainTypes.BLOCK, Vector2i(10, 0): TerrainTypes.OBSTACLE})
	var c: Vector2 = map.cell_to_world(Vector2i(10, 0))
	var blockers: Array[Vector3] = [Vector3(c.x, c.y, 20.0)]
	map.set_projectile_blockers(blockers)
	_check(map.is_low_cover_cell(Vector2i(0, 0)), "B: TREE cell is low cover")
	_check(map.is_low_cover_cell(Vector2i(10, 0)), "B: overworld tree canopy cell is low cover")
	_check(not map.is_low_cover_cell(Vector2i(1, 0)), "B: plain OBSTACLE (maze wall) is high cover")
	_check(not map.is_low_cover_cell(Vector2i(2, 0)), "B: MOUNTAIN is high cover")
	_check(not map.is_low_cover_cell(Vector2i(3, 0)), "B: BLOCK (stone block) is high cover")
	_check(not map.lob_blocked(map.cell_to_world(Vector2i(-2, 0)), map.cell_to_world(Vector2i(0, 0))), "B: lob over a tree is clear")
	_check(map.lob_blocked(map.cell_to_world(Vector2i(-2, 0)), map.cell_to_world(Vector2i(2, 0))), "B: lob into a wall is blocked")
	map.free()

func _leg_c() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	# Destroyable TREE cell at x 384..416, and an overworld tree (circle +
	# OBSTACLE cells, the #391/#407 planting) at x ~ 560 on the same lane.
	map.set_cells({Vector2i(12, 0): TerrainTypes.TREE, Vector2i(17, 0): TerrainTypes.OBSTACLE, Vector2i(18, 0): TerrainTypes.OBSTACLE})
	var tc := Vector2(576, 16)
	var blockers: Array[Vector3] = [Vector3(tc.x, tc.y, 30.0)]
	map.set_projectile_blockers(blockers)
	var player := _mk_player(stage, map, Vector2(640, 16))
	var thrower := _mk_enemy(stage, map, Vector2(200, 400))
	await _frames(2)
	player.global_position = Vector2(640, 16)
	var hp0 := player.hp
	var rock := _fire(stage, _rock, Vector2(250, 16), Vector2.RIGHT, thrower)
	await _fly(rock, 150)
	_check(map.tile_type_at_cell(Vector2i(12, 0)) == TerrainTypes.TREE, "C: the TREE cell under the arc is not destroyed")
	_check(player.hp == hp0 - int(_rock.damage), "C: rock sails over both trees and hits the player (hp %d -> %d)" % [hp0, player.hp])
	await _teardown(stage)

func _leg_d() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	map.set_cells({Vector2i(12, 0): TerrainTypes.OBSTACLE, Vector2i(12, 4): TerrainTypes.BLOCK})
	var player := _mk_player(stage, map, Vector2(500, 16))
	var thrower := _mk_enemy(stage, map, Vector2(200, 400))
	await _frames(2)
	player.global_position = Vector2(500, 16)
	var hp0 := player.hp
	var r1 := _fire(stage, _rock, Vector2(250, 16), Vector2.RIGHT, thrower)
	var w := {"blocked": false}
	r1.blocked.connect(func(): w.blocked = true)
	var last := await _fly(r1, 90)
	_check(_gone(r1) and w.blocked and last.x <= 386.0, "D: a maze wall stops the rock (x %.1f)" % last.x)
	_check(player.hp == hp0, "D: player behind the wall is untouched")
	player.global_position = Vector2(500, 144)
	await _frames(1)
	var r2 := _fire(stage, _rock, Vector2(250, 144), Vector2.RIGHT, thrower)
	var w2 := {"blocked": false}
	r2.blocked.connect(func(): w2.blocked = true)
	last = await _fly(r2, 90)
	_check(_gone(r2) and w2.blocked and last.x <= 386.0, "D: a stone block stops the rock at its face (x %.1f)" % last.x)
	_check(player.hp == hp0, "D: player behind the stone block is untouched")
	# #443 review: the rock is blocked, not a block-breaker (#216 destroy rule
	# applies to other shots only).
	_check(map.tile_type_at_cell(Vector2i(12, 4)) == TerrainTypes.BLOCK, "D: the stone block remains intact after the rock")
	await _teardown(stage)

func _leg_e() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var player := _mk_player(stage, map, Vector2(640, 16))
	var thrower := _mk_enemy(stage, map, Vector2(200, 400))
	var ally := _mk_enemy(stage, map, Vector2(550, 16))
	var box: StaticBody2D = load("res://scenes/destroyable_container.tscn").instantiate()
	stage.add_child(box)
	box.global_position = Vector2(400, 16)
	await _frames(2)
	ally.set_physics_process(false) # a static bystander, not a chaser
	thrower.set_physics_process(false)
	player.global_position = Vector2(640, 16)
	ally.global_position = Vector2(550, 16)
	await _frames(1)
	var hp0 := player.hp
	var box_hp: int = box.hp
	var ally_hp := ally.hp
	var rock := _fire(stage, _rock, Vector2(250, 16), Vector2.RIGHT, thrower)
	var last := await _fly(rock, 150)
	_check(is_instance_valid(box) and box.hp == box_hp, "E: the crate (cover group) is flown over, undamaged")
	_check(ally.hp == ally_hp, "E: another mustache man is flown over (no friendly fire)")
	_check(player.hp == hp0 - int(_rock.damage), "E: rock still lands on the player")
	await _teardown(stage)

func _leg_f() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tc := Vector2(450, 16)
	var blockers: Array[Vector3] = [Vector3(tc.x, tc.y, 30.0)]
	map.set_projectile_blockers(blockers)
	map.set_cell(map.world_to_cell(tc), TerrainTypes.OBSTACLE)
	var player := _mk_player(stage, map, Vector2(600, 16))
	var shooter := _mk_enemy(stage, map, Vector2(200, 400))
	await _frames(2)
	player.global_position = Vector2(600, 16)
	var hp0 := player.hp
	var bolt := _fire(stage, _bolt, Vector2(250, 16), Vector2.RIGHT, shooter)
	await _fly(bolt, 90)
	_check(_gone(bolt) and player.hp == hp0, "F: a non-lobbed shot is still stopped by the tree (#407)")
	await _teardown(stage)

## Overworld tree at cell (20,20): OBSTACLE cell + #407 canopy circle.
func _plant_tree(map: TerrainMap, cell: Vector2i) -> Vector2:
	var at: Vector2 = map.cell_to_world(cell)
	map.set_cell(cell, TerrainTypes.OBSTACLE)
	var blockers: Array[Vector3] = [Vector3(at.x, at.y, 16.0)]
	map.set_projectile_blockers(blockers)
	return at

func _drive_hold(e: Enemy, p: Player, frames: int) -> void:
	e.set_physics_process(true)
	for i in frames:
		p.global_rotation = (e.global_position - p.global_position).angle() # aimed at: keep holding
		await physics_frame
	e.set_physics_process(false)

func _leg_g() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := _plant_tree(map, Vector2i(20, 20))
	var p := _mk_player(stage, map, tree + Vector2(220, 0))
	var e := _mk_enemy(stage, map, tree + Vector2(-220, 0))
	await process_frame
	e.global_position = tree + Vector2(-220, 0)
	p.global_position = tree + Vector2(220, 0)
	var hp0 := p.hp
	await _drive_hold(e, p, 200) # walk to cover and settle
	var cov := _cover(e)
	_check(cov._state == EnemyBehaviorCover.State.HOLD, "G: mustache man is HOLDing behind the tree")
	var thrown_at_hold := cov.rocks_thrown
	await _drive_hold(e, p, 300) # 5s aimed at, still hiding
	_check(cov.rocks_thrown - thrown_at_hold >= 2, "G: throws rocks while hiding (%d in 5s)" % (cov.rocks_thrown - thrown_at_hold))
	_check(p.hp < hp0, "G: the rocks land on the player (hp %d -> %d)" % [hp0, p.hp])
	_check(p.hp >= hp0 - int(_rock.damage) * cov.rocks_thrown, "G: each rock deals only the low rock damage")
	await _teardown(stage)

func _leg_h() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var wall := Vector2i(20, 20)
	map.set_cell(wall, TerrainTypes.OBSTACLE) # maze-wall style: no canopy circle
	var at: Vector2 = map.cell_to_world(wall)
	var p := _mk_player(stage, map, at + Vector2(220, 0))
	var e := _mk_enemy(stage, map, at + Vector2(-220, 0))
	await process_frame
	e.global_position = at + Vector2(-220, 0)
	p.global_position = at + Vector2(220, 0)
	var hp0 := p.hp
	await _drive_hold(e, p, 400)
	var cov := _cover(e)
	_check(cov._state == EnemyBehaviorCover.State.HOLD, "H: holding behind a wall")
	_check(cov.rocks_thrown == 0 and p.hp == hp0, "H: no rocks thrown into high cover")
	await _teardown(stage)

func _leg_i() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var p := _mk_player(stage, map, Vector2(600, 0))
	var e := _mk_enemy(stage, map, Vector2(300, 0))
	await process_frame
	p.global_position = Vector2(600, 0)
	e.global_position = Vector2(300, 0)
	await _drive_hold(e, p, 120)
	var cov := _cover(e)
	_check(cov._state != EnemyBehaviorCover.State.HOLD and cov.rocks_thrown == 0, "I: not hiding behind cover - no rocks")
	await _teardown(stage)

func _leg_j() -> void:
	var s := _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var p := _mk_player(stage, map, Vector2(500, 0))
	var e := _mk_enemy(stage, map, Vector2(200, 0))
	await _frames(2)
	p.global_position = Vector2(500, 0)
	e.global_position = Vector2(200, 0)
	var hp0 := p.hp
	var rock := _cover(e).throw_rock(e, p.global_position)
	await process_frame
	_check(rock.spell.range == 300.0 + EnemyBehaviorCover.ROCK_OVERSHOOT, "J: rock range is the throw distance plus overshoot (%.0f)" % rock.spell.range)
	_check(_rock.range == 420.0, "J: the shared rock spell is never mutated")
	p.global_position = Vector2(500, 200) # sidestep after release
	var last := await _fly(rock, 120)
	_check(_gone(rock) and p.hp == hp0, "J: a dodged rock lands and is gone (last x %.0f)" % last.x)
	await _teardown(stage)
