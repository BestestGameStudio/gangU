extends SceneTree
## #433 harness: solid terrain blocks projectiles (Daniel, 2026-11-09:
## "enemy projectiles clip through terrain"). The #407 carve-out that let
## shots through plain OBSTACLE cells is gone: a BLOCKING, non-swimmable
## cell (dungeon walls, mountains, palette wall tiles) is solid cover, the
## same rule #407 gave trees.
##   (A) an enemy shot into a dungeon wall stops at the wall face; the
##       player behind it is untouched.
##   (B) a player shot from the other side stops at the far face too
##       (symmetric - one Projectile class, as with #407).
##   (C) a PIERCING shot is stopped as well (solid cover, tree parity).
##   (D) a shot fired from inside a wall cell flies out (a caster hugging
##       a wall never kills its own shot on frame one).
##   (E) swimmable WATER stays fly-over: shots cross it unchanged.
##   (F) MOUNTAIN (non-swimmable BLOCKING) blocks the same way.
##   (G) destroyable BLOCK cells keep the destroy path: a plain shot
##       destroys the cell and stops; a piercing shot destroys it and
##       flies on.
##   (H) #167 interactions keep priority: a cold shot over water freezes
##       it to ice and flies on (water is fly-over, never a wall).

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[433] ", label, " -> ", "PASS" if ok else "FAIL")

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
	# --- fixture stage: a 32px grid; wall column 12 (x 384..416) ----------
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var map := TerrainMap.new()
	map.cell_size = 32
	stage.add_child(map)
	var wall_col: Dictionary = {}
	for row in range(-4, 5):
		wall_col[Vector2i(12, row)] = TerrainTypes.OBSTACLE
	map.set_cells(wall_col)
	var player: Player = load("res://scenes/player.tscn").instantiate()
	stage.add_child(player)
	player.global_position = Vector2(200, 500) # off every flight line
	player.terrain = map
	player.set_physics_process(false)
	player.get_node("SpellCaster").set_process(false)
	var eshooter: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(eshooter)
	eshooter.global_position = Vector2(250, 300) # off the flight lines
	eshooter.terrain = map
	eshooter.set_physics_process(false)
	await _frames(3)
	var bolt: Spell = load("res://resources/spells/placeholder_bolt.tres")

	# --- (A) enemy shot into the wall, player behind it safe --------------
	player.global_position = Vector2(460, 0) # behind the wall, on the lane
	await _frames(2)
	var php := player.hp
	var ap := _fire(stage, bolt, Vector2(250, 0), Vector2.RIGHT, eshooter)
	var aw := _watch(ap)
	await _run(ap, aw, 30)
	_check(_gone(ap) and aw.blocked, "A: an enemy shot into a dungeon wall is blocked")
	_check(absf(aw.pos.x - 384.0) < 1.0, "A: it stops at the wall face (x %.1f, face 384)" % aw.pos.x)
	_check(player.hp == php, "A: the player behind the wall takes no damage (hp %d)" % player.hp)
	player.global_position = Vector2(200, 500)
	await _frames(2)

	# --- (B) player shot from the other side stops at the far face --------
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	stage.add_child(enemy)
	enemy.global_position = Vector2(300, 0) # behind the wall, seen from the right
	enemy.set_physics_process(false)
	await _frames(2)
	var ehp := enemy.hp
	var bp := _fire(stage, bolt, Vector2(530, 0), Vector2.LEFT, player)
	var bw := _watch(bp)
	await _run(bp, bw, 30)
	_check(_gone(bp) and bw.blocked, "B: a player shot is blocked by the wall too")
	_check(absf(bw.pos.x - 416.0) < 1.0, "B: it stops at the far wall face (x %.1f, face 416)" % bw.pos.x)
	_check(enemy.hp == ehp, "B: the enemy behind the wall takes no damage (hp %d)" % enemy.hp)
	enemy.queue_free()
	await _frames(2)

	# --- (C) piercing is stopped too --------------------------------------
	var lance: Spell = bolt.duplicate()
	var ltags: Array[StringName] = [SpellTags.PIERCING]
	lance.tags = ltags
	lance.range = 1000.0
	var cp := _fire(stage, lance, Vector2(250, 0), Vector2.RIGHT, player)
	var cw := _watch(cp)
	await _run(cp, cw, 30)
	_check(_gone(cp) and cw.blocked and absf(cw.pos.x - 384.0) < 1.0, "C: a PIERCING shot stops at the wall too")

	# --- (D) fired from inside a wall cell, the shot flies out ------------
	var dp := _fire(stage, bolt, Vector2(400, 0), Vector2.RIGHT, eshooter)
	var dw := _watch(dp)
	await _run(dp, dw, 40)
	_check(not dw.blocked and dw.pos.x > 416.0 + 40.0, "D: a shot fired from inside a wall cell flies out (x %.1f)" % dw.pos.x)
	if is_instance_valid(dp):
		dp.queue_free()

	# --- (E) swimmable WATER stays fly-over -------------------------------
	var water_col: Dictionary = {}
	for row in range(-10, -6):
		water_col[Vector2i(12, row)] = TerrainTypes.WATER
	map.set_cells(water_col)
	var ep := _fire(stage, bolt, Vector2(250, -272), Vector2.RIGHT, eshooter)
	var ew := _watch(ep)
	await _run(ep, ew, 60)
	_check(not ew.blocked and ew.pos.x > 500.0, "E: a shot crosses swimmable water (x %.1f)" % ew.pos.x)
	if is_instance_valid(ep):
		ep.queue_free()
	_check(map.tile_type_at_cell(Vector2i(12, -9)) == TerrainTypes.WATER, "E: the water is unchanged")

	# --- (F) MOUNTAIN blocks the same way ---------------------------------
	var mtn_col: Dictionary = {}
	for row in range(6, 10):
		mtn_col[Vector2i(12, row)] = TerrainTypes.MOUNTAIN
	map.set_cells(mtn_col)
	var fp := _fire(stage, bolt, Vector2(250, 240), Vector2.RIGHT, eshooter)
	var fw := _watch(fp)
	await _run(fp, fw, 30)
	_check(_gone(fp) and fw.blocked and absf(fw.pos.x - 384.0) < 1.0, "F: MOUNTAIN blocks the shot at its face (x %.1f)" % fw.pos.x)

	# --- (G) destroyable BLOCK cells keep the destroy path ----------------
	map.set_cell(Vector2i(12, 11), TerrainTypes.BLOCK)
	var gp := _fire(stage, bolt, Vector2(250, 368), Vector2.RIGHT, eshooter)
	var gw := _watch(gp)
	await _run(gp, gw, 30)
	_check(_gone(gp) and not gw.blocked, "G: a plain shot is consumed destroying a BLOCK cell")
	_check(map.tile_type_at_cell(Vector2i(12, 11)) == TerrainTypes.GROUND, "G: the BLOCK cell is destroyed")
	map.set_cell(Vector2i(12, 11), TerrainTypes.BLOCK)
	var gp2 := _fire(stage, lance, Vector2(250, 368), Vector2.RIGHT, eshooter)
	var gw2 := _watch(gp2)
	await _run(gp2, gw2, 60)
	_check(not gw2.blocked and gw2.pos.x > 500.0, "G: a piercing shot destroys the cell and flies on (x %.1f)" % gw2.pos.x)
	_check(map.tile_type_at_cell(Vector2i(12, 11)) == TerrainTypes.GROUND, "G: the piercing shot destroyed the cell too")
	if is_instance_valid(gp2):
		gp2.queue_free()

	# --- (H) #167 interactions keep priority over fly-over water ----------
	var cold: Spell = bolt.duplicate()
	var ctags: Array[StringName] = [SpellTags.COLD]
	cold.tags = ctags
	var hp2 := _fire(stage, cold, Vector2(250, -272), Vector2.RIGHT, eshooter)
	var hw := _watch(hp2)
	await _run(hp2, hw, 60)
	_check(map.tile_type_at_cell(Vector2i(12, -9)) == TerrainTypes.ICE, "H: a cold shot freezes the water to ice")
	_check(not hw.blocked and hw.pos.x > 500.0, "H: it flies on (freeze_water never consumes the shot)")
	if is_instance_valid(hp2):
		hp2.queue_free()

	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
