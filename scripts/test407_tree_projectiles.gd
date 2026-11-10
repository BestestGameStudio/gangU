extends SceneTree
## #407 harness: trees block projectiles (Daniel, 2026-11-09: "trees should
## block projectiles").
##   (A) production overworld: every decor tree (and no rock) registers its
##       drawn circle as a projectile blocker on the area's Terrain grid.
##   (B) a real shot fired into a real overworld tree stops at its canopy.
##   (C) fixture: a player shot is stopped by a tree, the enemy behind it is
##       untouched, the shot ends at the canopy edge and the tree survives.
##   (D) enemy shots are blocked the same way (the player behind is safe).
##   (E) PIERCING shots are stopped too (trees are solid cover).
##   (F) a body in front of the tree still takes the hit first.
##   (G) a shot fired from inside a canopy edge flies out; shots that miss
##       the tree and terrain-less sources (hub, fixtures) are unaffected.
##       #433 superseded the OBSTACLE carve-out: dungeon walls are solid
##       cover now (full wall coverage in test433).

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[407] ", label, " -> ", "PASS" if ok else "FAIL")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _fire(stage: Node, spell: Spell, from: Vector2, dir: Vector2, src: Node2D) -> Projectile:
	var p: Projectile = load("res://scenes/projectile.tscn").instantiate()
	p.setup(spell, dir, src)
	stage.add_child(p)
	p.global_position = from
	return p

func _gone(p: Variant) -> bool: # untyped: a freed shot fails a typed argument
	return not is_instance_valid(p) or p.is_queued_for_deletion()

## Tracks where a shot was last seen and whether it reported `blocked`.
func _watch(p: Projectile) -> Dictionary:
	var w := {"pos": p.global_position, "blocked": false}
	p.blocked.connect(func(): w.blocked = true; w.pos = p.global_position)
	return w

func _run(p: Projectile, w: Dictionary, n: int) -> void:
	for i in n:
		await physics_frame
		if _gone(p):
			return
		w.pos = p.global_position

func _initialize() -> void:
	# --- (A) production overworld registration ---
	var area: Node2D = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(area)
	await _frames(2)
	var ground := area.get_node("Ground") as OverworldGround
	var omap := area.get_node("Terrain") as TerrainMap
	var trees: Array[Dictionary] = []
	for d in ground.decor:
		if d["kind"] == "tree":
			trees.append(d)
	var blockers := omap.projectile_blockers()
	_check(trees.size() > 0 and blockers.size() >= trees.size(), "A: a projectile blocker per decor tree (trees first; #546 appends village footprints) (%d trees, %d blockers)" % [trees.size(), blockers.size()])
	var match_ok := true
	for i in trees.size():
		var at: Vector2 = trees[i]["at"]
		# Vector3 is single precision: compare within a hundredth of a pixel.
		if i >= blockers.size() or Vector2(blockers[i].x, blockers[i].y).distance_to(at) > 0.01 or absf(blockers[i].z - float(trees[i]["r"])) > 0.01:
			match_ok = false
	_check(match_ok, "A: each blocker is the tree's drawn circle (centre + radius)")
	var rock_free := true
	for d in ground.decor:
		if d["kind"] == "rock":
			for b in blockers:
				if Vector2(b.x, b.y).distance_to(d["at"]) < 0.01:
					rock_free = false
	_check(rock_free, "A: rocks do not block shots")

	# --- (B) real shot into a real overworld tree ---
	var oshooter: Player = load("res://scenes/player.tscn").instantiate()
	area.add_child(oshooter)
	oshooter.global_position = omap.cell_to_world(Vector2i(0, 0)) + Vector2(0, 5000)
	oshooter.terrain = omap
	oshooter.set_physics_process(false)
	oshooter.get_node("SpellCaster").set_process(false)
	await _frames(1)
	var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")
	var tree: Dictionary = trees[0]
	var tat: Vector2 = tree["at"]
	var tr: float = tree["r"]
	var bp := _fire(area, bolt, tat + Vector2(tr + 12.0, 0), Vector2.LEFT, oshooter)
	var bw := _watch(bp)
	await _run(bp, bw, 20)
	_check(_gone(bp) and bw.blocked, "B: a bolt fired at an overworld tree is blocked")
	_check(bw.pos.distance_to(tat) >= tr - 1.0, "B: it stops at the canopy edge (%.1f px from centre, r %.1f)" % [bw.pos.distance_to(tat), tr])
	_check(omap.projectile_blockers().size() == blockers.size(), "B: the tree is indestructible cover")
	area.queue_free()
	await _frames(2)

	# --- fixture stage: one tree at (400, 0) on an empty grid ---
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var map := TerrainMap.new()
	map.cell_size = 32
	stage.add_child(map)
	var tree_at := Vector2(400, 0)
	var tree_r := 24.0
	var circles: Array[Vector3] = [Vector3(tree_at.x, tree_at.y, tree_r)]
	map.set_projectile_blockers(circles)
	var player: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(player)
	player.global_position = Vector2(100, 400) # off every flight line
	player.terrain = map
	player.set_physics_process(false)
	player.get_node("SpellCaster").set_process(false)
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy)
	enemy.global_position = Vector2(470, 0) # right behind the tree
	enemy.set_physics_process(false)
	await _frames(3)

	# --- (C) player shot blocked, enemy behind it safe ---
	var hp0 := enemy.hp
	var p := _fire(stage, bolt, Vector2(250, 0), Vector2.RIGHT, player)
	var w := _watch(p)
	await _run(p, w, 40)
	_check(_gone(p) and w.blocked, "C: player shot is blocked by the tree")
	_check(enemy.hp == hp0, "C: the enemy behind the tree takes no damage (hp %d)" % enemy.hp)
	_check(absf(w.pos.x - (tree_at.x - tree_r)) < 1.0, "C: shot ends at the canopy edge (x %.1f, edge %.1f)" % [w.pos.x, tree_at.x - tree_r])
	_check(map.projectile_blockers().size() == 1, "C: the tree survives the hit")

	# --- (D) enemy shot blocked, player behind it safe ---
	var eshooter: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(eshooter)
	eshooter.global_position = Vector2(400, 300)
	eshooter.terrain = map
	eshooter.set_physics_process(false)
	player.global_position = Vector2(400, -70) # behind the tree, seen from below
	await _frames(3)
	var php0 := player.hp
	var ep := _fire(stage, bolt, Vector2(400, 150), Vector2.UP, eshooter)
	var ew := _watch(ep)
	await _run(ep, ew, 40)
	_check(_gone(ep) and ew.blocked, "D: enemy shot is blocked by the tree")
	_check(player.hp == php0, "D: the player behind the tree takes no damage (hp %d)" % player.hp)
	player.global_position = Vector2(100, 400)
	await _frames(2)

	# --- (E) piercing is stopped too ---
	var lance: Spell = bolt.duplicate()
	var tags: Array[StringName] = [SpellTags.PIERCING]
	lance.tags = tags
	lance.range = 1000.0
	var lp := _fire(stage, lance, Vector2(250, 0), Vector2.RIGHT, player)
	var lw := _watch(lp)
	await _run(lp, lw, 40)
	_check(_gone(lp) and lw.blocked and enemy.hp == hp0, "E: a PIERCING shot stops at the tree too")

	# --- (F) a body in front of the tree is still hit ---
	var front: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(front)
	front.global_position = Vector2(330, 0)
	front.set_physics_process(false)
	await _frames(3)
	var fhp := front.hp
	var fp := _fire(stage, bolt, Vector2(250, 0), Vector2.RIGHT, player)
	var fw := _watch(fp)
	await _run(fp, fw, 40)
	_check(front.hp < fhp and not fw.blocked, "F: an enemy in front of the tree takes the hit (hp %d -> %d)" % [fhp, front.hp])
	front.queue_free()
	await _frames(2)

	# --- (G) unaffected cases ---
	enemy.global_position = Vector2(470, 600) # clear the flight lines below
	await _frames(2)
	var op := _fire(stage, bolt, tree_at + Vector2(tree_r - 4.0, 0), Vector2.RIGHT.rotated(-PI / 2.0 + 0.3), player)
	var ow := _watch(op)
	await _run(op, ow, 20)
	_check(not ow.blocked and ow.pos.distance_to(tree_at) > tree_r + 20.0, "G: a shot fired from inside a canopy edge flies out")
	if is_instance_valid(op):
		op.queue_free()
	var mp := _fire(stage, bolt, Vector2(250, 60), Vector2.RIGHT, player)
	var mw := _watch(mp)
	await _run(mp, mw, 40)
	_check(not mw.blocked and mw.pos.x > tree_at.x + tree_r, "G: a shot that misses the tree flies past it")
	if is_instance_valid(mp):
		mp.queue_free()
	var np := _fire(stage, bolt, Vector2(250, 0), Vector2.RIGHT, null)
	var nw := _watch(np)
	await _run(np, nw, 40)
	_check(not nw.blocked and nw.pos.x > tree_at.x + tree_r, "G: a terrain-less source (hub, fixtures) is not blocked")
	if is_instance_valid(np):
		np.queue_free()
	map.set_projectile_blockers([] as Array[Vector3])
	map.set_cell(map.world_to_cell(tree_at), TerrainTypes.OBSTACLE)
	var wp := _fire(stage, bolt, Vector2(250, 0), Vector2.RIGHT, player)
	var ww := _watch(wp)
	await _run(wp, ww, 40)
	# #433: the #407 carve-out is gone - a plain OBSTACLE cell (dungeon
	# wall) is solid cover now and stops the shot at its face (x 384 on
	# this 32px grid). Full wall coverage lives in test433.
	_check(ww.blocked and absf(ww.pos.x - 384.0) < 1.0, "G: an OBSTACLE cell (dungeon wall) blocks the shot at its face (x %.1f)" % ww.pos.x)

	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
