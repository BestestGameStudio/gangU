extends SceneTree
## #499 harness: attacking while in tall grass reveals the player's position
## to enemies (Colin: every attack or spell cast counts; revealed until they
## leave the grass; revealed to all enemies regardless of range, who then run
## their normal logic; bosses too).
##   (A) a hidden player is no target; one real cast from the grass makes them
##       a target for a near enemy, a far enemy and a boss alike.
##   (B) the revealed player is drawn opaque; a revealed player is chased.
##   (C) the reveal persists while they stay (and move) in the grass.
##   (D) leaving the grass ends the reveal: stepping back in hides them again.
##   (E) a cast made OUTSIDE the grass does not reveal them after they enter.
##   (F) a guard aggros on a revealed player inside its aggro radius.

var failures := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("[499] ", label, " -> ", "PASS" if ok else "FAIL")

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

func _cast(p: Player) -> void:
	var caster := p.get_node("SpellCaster") as SpellCaster
	caster.aim_override = p.global_position + Vector2(0, 200) # fire away from everyone
	caster._cooldowns.clear()
	caster.cast()

func _initialize() -> void:
	var world := Node2D.new() # casts spawn shots/effects into current_scene
	root.add_child(world)
	current_scene = world
	var m := _grass_map()
	var p := _player(Vector2(900, 300), m)
	var near := _enemy(Vector2(560, 300), m)
	var far := _enemy(Vector2(-2400, 300), m)
	var boss := _enemy(Vector2(400, 1400), m, load("res://resources/enemies/head_boss.tres") as EnemyDefinition)
	near.set_physics_process(false)
	far.set_physics_process(false)
	boss.set_physics_process(false)
	await _frames(2)

	# --- (A) ---
	_check(p.is_concealed() and p.is_hidden_in_grass(), "A: player in grass is hidden before attacking")
	_check(near._resolve_target() == null and far._resolve_target() == null and boss._resolve_target() == null,
		"A: no enemy (near, far, boss) targets the hidden player")
	_cast(p)
	_check(p.is_grass_revealed(), "A: a spell cast from the grass reveals the player")
	_check(near._resolve_target() == p, "A: near enemy now targets the revealed player")
	_check(far._resolve_target() == p, "A: far enemy (%d px away) targets the revealed player - any range" % int(far.global_position.distance_to(p.global_position)))
	_check(boss._resolve_target() == p, "A: boss targets the revealed player")

	# --- (B) ---
	await process_frame
	await process_frame
	_check(is_equal_approx(p.modulate.a, 1.0), "B: revealed player is drawn opaque")
	var gap0 := near.global_position.distance_to(p.global_position)
	near.set_physics_process(true)
	await _frames(20)
	_check(near.global_position.distance_to(p.global_position) < gap0 - 10.0, "B: enemy chases the revealed player (normal logic)")
	near.set_physics_process(false)

	# --- (C) ---
	p.global_position = Vector2(1100, 500) # moved, still in the grass
	await _frames(2)
	_check(p.is_grass_revealed() and far._resolve_target() == p, "C: still revealed after moving within the grass")

	# --- (D) ---
	p.global_position = Vector2(400, 300) # out of the grass
	await _frames(1)
	_check(not p.is_grass_revealed(), "D: leaving the grass ends the reveal")
	p.global_position = Vector2(900, 300) # back in
	await _frames(1)
	_check(p.is_hidden_in_grass(), "D: re-entering the grass hides the player again")
	_check(far._resolve_target() == null and boss._resolve_target() == null, "D: enemies lose the player again after re-entering")
	await process_frame
	await process_frame
	_check(p.modulate.a < 1.0, "D: hidden player is translucent again")

	# --- (E) ---
	p.global_position = Vector2(400, 300)
	await _frames(1)
	_cast(p)
	p.global_position = Vector2(900, 300)
	await _frames(1)
	_check(p.is_hidden_in_grass(), "E: a cast made outside the grass does not reveal after entering")
	_cast(p)
	_check(p.is_grass_revealed(), "E: the next cast inside the grass reveals (every cast counts)")

	# --- (F) guard aggro ---
	p.global_position = Vector2(400, 300)
	await _frames(1)
	p.global_position = Vector2(720, 300) # in grass, hidden again
	var guard := _enemy(Vector2(560, 300), m, load("res://resources/enemies/overworld_guard.tres") as EnemyDefinition)
	await _frames(20)
	var gb := guard._behavior as EnemyBehaviorGuard
	_check(gb != null and not gb.engaged, "F: guard ignores the hidden player in its radius")
	_cast(p)
	await _frames(3)
	_check(gb != null and gb.engaged, "F: guard aggros once the player attacks from the grass")

	print("[499] DONE failures=", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)
