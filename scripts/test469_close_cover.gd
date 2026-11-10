extends SceneTree
## #469 harness: moustache men stopped seeking cover and walked straight at
## the player when the player was close (Daniel, 2026-11-09: "mustache men
## sometimes stop seeking cover" / "Walking at you" / "When im close").
##
## Root cause (reproduced by legs A-C against the pre-fix code):
##   1. Candidate starvation: every cover had to sit strictly nearer to the
##      enemy than the player AND inside a 60deg cone toward the player.
##      With the player close that disc is tiny, so _pick_cover found
##      nothing and SEEK dropped to ENGAGED (the plain chase).
##   2. ENGAGED lock: a no-cover ENGAGED only re-scanned once the player was
##      past RE_ENGAGE_DIST (280px), so at close range it never looked for
##      cover again, even once valid cover existed.
##
## Fixture: the test406 idiom (collisions off, real physics frames, the
## harness owns player.rotation and keeps the mouse ON the mob so the
## 3s away-charge never fires - every leg is about cover choice, not charge).
##
## Legs:
##   (A) cover just past the player (player between enemy and tree, 110px):
##       the mob reaches HOLD with body-width shelter.
##   (B) cover behind the enemy (player 100px ahead): the mob falls back
##       behind it instead of walking at the player.
##   (C) ENGAGED lock: no cover at first (mob ENGAGED, close), then a tree
##       appears beside it - it re-seeks and shelters without the player
##       ever leaving 280px.
##   (D) range gate: at long range (player 360px away) a tree behind the
##       enemy is still ignored - "nearest cover towards the player" is
##       unchanged away from close range; it advances on the player.
##   (E) post-charge ENGAGED is unchanged: after a charge hit it stays
##       ENGAGED at close range (only the no-cover fallback re-scans).

const DT := 1.0 / 60.0

var failures := 0
var _player_scene: PackedScene
var _enemy_scene: PackedScene

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[469] ", name, " -> PASS")
	else:
		failures += 1
		print("[469] ", name, " -> FAIL")

func _initialize() -> void:
	_player_scene = load("res://scenes/player.tscn")
	_enemy_scene = load("res://scenes/enemy.tscn")
	await _leg_a_cover_past_player()
	await _leg_b_cover_behind_enemy()
	await _leg_c_engaged_lock()
	await _leg_d_long_range_unchanged()
	await _leg_e_post_charge_engaged()
	print("[469] failures: ", failures)
	if failures == 0:
		print("RESULT: ALL PASS")
	quit(1 if failures > 0 else 0)

# --- fixture helpers (test406 idiom) ----------------------------------------

func _mk_stage() -> Array:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	var map := TerrainMap.new()
	map.name = "Terrain"
	map.cell_size = 32
	stage.add_child(map)
	return [stage, map]

func _mk_player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = _player_scene.instantiate()
	p.name = "Player"
	p.collision_layer = 0
	p.collision_mask = 0
	p.set_process(false)
	stage.add_child(p)
	p.global_position = pos
	p.set_physics_process(false)
	return p

func _mk_enemy(stage: Node2D, map: TerrainMap, pos: Vector2) -> Enemy:
	var e: Enemy = _enemy_scene.instantiate()
	e.collision_layer = 0
	e.collision_mask = 0
	e.player_path = NodePath("../Player")
	e.terrain = map
	e.set_physics_process(false)
	stage.add_child(e)
	e.global_position = pos
	return e

func _cover(e: Enemy) -> RefCounted:
	return (e.get("_behavior") as RefCounted).get("_cover")

func _state(e: Enemy) -> int:
	return _cover(e).get("_state")

func _aim(p: Player, at: Vector2, away: bool) -> void:
	p.global_rotation = (at - p.global_position).angle() + (PI if away else 0.0)

## Real physics frames, mouse kept on the mob. Returns how many frames the
## mob spent ENGAGED (the "walking at you" state).
func _drive_aimed(e: Enemy, p: Player, frames: int) -> int:
	var engaged := 0
	e.set_physics_process(true)
	await physics_frame
	for i in frames:
		_aim(p, e.global_position, false)
		await physics_frame
		if _state(e) == EnemyBehaviorCover.State.ENGAGED:
			engaged += 1
	e.set_physics_process(false)
	return engaged

func _sheltered_hold(e: Enemy, map: TerrainMap, p: Player) -> bool:
	return _state(e) == EnemyBehaviorCover.State.HOLD and _cover(e)._sheltered(map, e.global_position, p.global_position)

func _teardown(stage: Node2D) -> void:
	stage.queue_free()
	await process_frame
	await process_frame

## Pins positions after the uncontrolled ready tick (test406 idiom).
func _setup(map_cells: Array[Vector2i], p_off: Vector2, e_off: Vector2) -> Array:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	for c in map_cells:
		map.set_cell(c, TerrainTypes.OBSTACLE)
	var t: Vector2 = map.cell_to_world(Vector2i(20, 20))
	var p: Player = _mk_player(stage, t + p_off)
	var e: Enemy = _mk_enemy(stage, map, t + e_off)
	await process_frame
	e.global_position = t + e_off
	p.global_position = t + p_off
	return [stage, map, p, e, t]

# --- legs -------------------------------------------------------------------

func _leg_a_cover_past_player() -> void:
	# Tree at T, player 64px in front of it, enemy 110px further out: the
	# tree is farther from the enemy than the player is (old rule rejects).
	var r: Array = await _setup([Vector2i(20, 20)], Vector2(-64, 0), Vector2(-174, 0))
	var map: TerrainMap = r[1]
	var p: Player = r[2]
	var e: Enemy = r[3]
	await _drive_aimed(e, p, 300)
	_check(_sheltered_hold(e, map, p), "A: close player, cover just past them - mob shelters (state=%d)" % _state(e))
	_check(map.is_walkable_at(e.global_position), "A: hold is on walkable ground")
	await _teardown(r[0])

func _leg_b_cover_behind_enemy() -> void:
	# Player 100px ahead, the only tree 50px BEHIND the enemy (outside the
	# toward-player cone): falls back behind it.
	var r: Array = await _setup([Vector2i(20, 20)], Vector2(150, 0), Vector2(50, 0))
	var map: TerrainMap = r[1]
	var p: Player = r[2]
	var e: Enemy = r[3]
	var engaged: int = await _drive_aimed(e, p, 240)
	_check(_sheltered_hold(e, map, p), "B: close player, cover behind the mob - it falls back to shelter (state=%d)" % _state(e))
	_check(engaged <= 20, "B: it does not walk at the player meanwhile (%d engaged frames)" % engaged)
	await _teardown(r[0])

func _leg_c_engaged_lock() -> void:
	# No cover at all: the mob must fall back to ENGAGED (plain chase).
	var r: Array = await _setup([], Vector2(160, 0), Vector2(0, 0))
	var map: TerrainMap = r[1]
	var p: Player = r[2]
	var e: Enemy = r[3]
	await _drive_aimed(e, p, 10)
	_check(_state(e) == EnemyBehaviorCover.State.ENGAGED, "C: no cover - ENGAGED fallback first")
	# A tree appears beside the mob (perpendicular to the player line) while
	# the player is well inside RE_ENGAGE_DIST.
	var to_p: Vector2 = (p.global_position - e.global_position).normalized()
	var cell: Vector2i = map.world_to_cell(e.global_position + to_p.orthogonal() * 64.0)
	map.set_cell(cell, TerrainTypes.OBSTACLE)
	_check(e.global_position.distance_to(p.global_position) < EnemyBehaviorCover.RE_ENGAGE_DIST,
		"C: player still inside RE_ENGAGE_DIST when cover appears")
	await _drive_aimed(e, p, 240)
	_check(_sheltered_hold(e, map, p), "C: ENGAGED mob re-seeks the new cover at close range (state=%d)" % _state(e))
	await _teardown(r[0])

func _leg_d_long_range_unchanged() -> void:
	var r: Array = await _setup([Vector2i(20, 20)], Vector2(420, 0), Vector2(60, 0))
	var p: Player = r[2]
	var e: Enemy = r[3]
	var x0: float = e.global_position.x
	await _drive_aimed(e, p, 30)
	_check(e.global_position.x > x0 + 20.0, "D: long range - cover behind is ignored, it advances on the player")
	_check(_state(e) != EnemyBehaviorCover.State.HOLD, "D: long range - no retreat into rear cover")
	await _teardown(r[0])

func _leg_e_post_charge_engaged() -> void:
	# Hold behind a tree, look away 3s -> charge -> hit -> ENGAGED. With the
	# player close and the tree still there, it stays ENGAGED (unchanged).
	var r: Array = await _setup([Vector2i(20, 20)], Vector2(150, 0), Vector2(-150, 0))
	var p: Player = r[2]
	var e: Enemy = r[3]
	await _drive_aimed(e, p, 200)
	var hp0: int = p.hp
	e.set_physics_process(true)
	await physics_frame
	var n := 0
	while n < 400 and p.hp == hp0:
		_aim(p, e.global_position, true)
		await physics_frame
		n += 1
	_check(p.hp < hp0 and _state(e) == EnemyBehaviorCover.State.ENGAGED, "E: charge hit then ENGAGED")
	for i in 60:
		_aim(p, e.global_position, false)
		await physics_frame
	e.set_physics_process(false)
	_check(_state(e) == EnemyBehaviorCover.State.ENGAGED, "E: post-charge ENGAGED stays engaged at close range (unchanged)")
	await _teardown(r[0])
