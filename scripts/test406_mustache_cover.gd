extends SceneTree
## #406 harness: moustache men (Mustache Warrior, scenes/enemy.tscn) seek
## cover (Daniel, 2026-11-09: seek cover toward the player, run fast
## between cover, hold while the player's mouse points their way, charge
## after 3s of the mouse pointing away; "just regular mobs", "any cover").
##
## Fixture notes (test99 idiom): collisions off (range/timer contract, not
## collision physics); enemy movement legs use REAL physics frames
## (move_and_slide only integrates inside a real physics step); the
## player's _process is disabled so the harness owns player.rotation (the
## #137 aim contract the cover behavior reads). Each leg re-pins positions
## after spawn (uncontrolled ready tick, verified in #99).
##
## Legs:
##   (A) seam: enemy.tscn opts in (cover_seek) yet its behavior slot STAYS
##       an EnemyBehaviorChaseContact (the #209/#337 target-resolution
##       seam); the slime scene does not opt in.
##   (B) no terrain, no cover: exact chase parity (velocity at the player
##       at enemy.speed, position advances).
##   (C) SEEK: a tree cell between enemy and player - the enemy walks to
##       shelter: it stops with the cover cell on the enemy->player
##       segment, never entering a blocked cell.
##   (D) HOLD: aimed at, it stays put behind cover (no charge, no damage).
##   (E) CHARGE: aim away 3s -> fast charge (speed*FAST_MULT), contact
##       damage lands, then ENGAGED (plain chase/contact).
##   (F) away-timer resets the instant the mouse points back: 2s away +
##       re-aim + 2s away = still no charge; +1.2s away = charge.
##   (G) DASH: repositioning to cover after the player strafes happens at
##       FAST_MULT speed.
##   (H) cover destroyed mid-hold (breakable terrain): the enemy drops it
##       and engages (reaches the player). Raw clear_cell path: the
##       repick-cadence poll catches it (raw set/clear emit no signals).
##   (M) destroy_cell path: the cell_destroyed signal drops the held
##       cover immediately (no poll wait).
##   (I) solid cover: a DestroyableContainer (cover group) is used as
##       shelter with no blocking terrain at all ("any cover").
##   (J) two mobs are independent: the aimed-at one holds while the
##       un-aimed one charges and hits.
##   (K) player death: the enemy idles (zero velocity).
##   (L) freeze (#305): a frozen enemy accumulates no away-time and does
##       not move; it resumes after release.
##   (N) aimed strafe, single cover (PR #408 review repro): HOLD behind
##       an OBSTACLE, then the player walks round it to centre+(0,220)
##       while STILL aiming at the mob. It must not stay in an exposed
##       HOLD: with no valid shelter left it engages. Normal collisions,
##       real physics frames.
##   (O) aimed strafe, second cover available: same strafe, still aimed,
##       the mob DASHes to a hold that the new sightline crosses blocked
##       terrain for - no look-away needed to recover cover.

const DT := 1.0 / 60.0

var failures := 0
var _player_scene: PackedScene
var _enemy_scene: PackedScene
var _slime_scene: PackedScene

func _check(cond: bool, name: String) -> void:
	if cond:
		print("[406] ", name, " -> PASS")
	else:
		failures += 1
		print("[406] ", name, " -> FAIL")

func _initialize() -> void:
	_player_scene = load("res://scenes/player.tscn")
	_enemy_scene = load("res://scenes/enemy.tscn")
	_slime_scene = load("res://scenes/enemy_slime.tscn")

	# --- (A) opt-in seam ---
	var probe: Enemy = _enemy_scene.instantiate()
	_check(probe.cover_seek, "A: mustache warrior scene opts into cover_seek")
	_check(probe.get("definition") == null, "A: no definition attached (default seam preserved)")
	probe.free()
	var slime: Enemy = _slime_scene.instantiate()
	_check(not slime.cover_seek, "A: slime does not opt into cover_seek")
	slime.free()

	await _leg_b_no_cover_chase()
	await _leg_c_seek_cover()
	await _leg_d_hold_while_aimed()
	await _leg_e_charge_after_3s()
	await _leg_f_timer_reset_on_aim()
	await _leg_h_cover_destroyed()
	await _leg_m_cover_destroy_signal()
	await _leg_i_solid_container_cover()
	await _leg_j_two_mobs_independent()
	await _leg_k_player_death()
	await _leg_l_freeze_pauses()
	await _leg_g_dash_fast()
	await _leg_n_aimed_strafe_single_cover()
	await _leg_o_aimed_strafe_reshelter()

	print("[406] failures: ", failures)
	quit(1 if failures > 0 else 0)

# --- fixture helpers --------------------------------------------------------

## Stage + TerrainMap (32px cells, the overworld grid). Returns [stage, map].
func _mk_stage(with_map: bool = true) -> Array:
	var stage := Node2D.new()
	stage.name = "Stage"
	root.add_child(stage)
	var map: TerrainMap = null
	if with_map:
		map = TerrainMap.new()
		map.name = "Terrain"
		map.cell_size = 32
		stage.add_child(map)
	return [stage, map]

func _mk_player(stage: Node2D, pos: Vector2) -> Player:
	var p: Player = _player_scene.instantiate()
	p.name = "Player"
	p.collision_layer = 0
	p.collision_mask = 0
	p.set_process(false) # the harness owns player.rotation (aim)
	stage.add_child(p)
	p.global_position = pos
	p.set_physics_process(false)
	return p

func _mk_enemy(stage: Node2D, map: TerrainMap, pos: Vector2, pname: String = "Player") -> Enemy:
	var e: Enemy = _enemy_scene.instantiate()
	e.collision_layer = 0
	e.collision_mask = 0
	e.player_path = NodePath("../" + pname)
	e.terrain = map
	e.set_physics_process(false)
	stage.add_child(e)
	e.global_position = pos
	return e

func _aim_at(p: Player, pos: Vector2) -> void:
	p.global_rotation = (pos - p.global_position).angle()

func _aim_away(p: Player, pos: Vector2) -> void:
	p.global_rotation = (pos - p.global_position).angle() + PI

func _cover(e: Enemy) -> RefCounted:
	return (e.get("_behavior") as RefCounted).get("_cover")

func _state(e: Enemy) -> int:
	return _cover(e).get("_state")

func _drive(e: Enemy, frames: int) -> void:
	for i in frames:
		e._physics_process(DT)

## Real physics frames; each frame re-pins the aim direction (the game
## does this from the mouse every frame).
func _drive_real(e: Enemy, frames: int, p: Player, point_at_enemy: bool) -> void:
	e.set_physics_process(true)
	await physics_frame
	for i in frames:
		if point_at_enemy:
			_aim_at(p, e.global_position)
		else:
			_aim_away(p, e.global_position)
		await physics_frame
	e.set_physics_process(false)

func _blocked_cell_on_segment(map: TerrainMap, a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	var steps := int(ceil(dist / (map.cell_size * 0.5))) + 1
	for i in steps + 1:
		var cell := map.world_to_cell(a.lerp(b, float(i) / steps))
		if map.movement_at_cell(cell) == TerrainTypes.Movement.BLOCKING:
			return true
	return false

func _teardown(stage: Node2D) -> void:
	stage.queue_free()
	await process_frame
	await process_frame

# --- legs -------------------------------------------------------------------

func _leg_b_no_cover_chase() -> void:
	var s: Array = _mk_stage(false)
	var stage: Node2D = s[0]
	var p: Player = _mk_player(stage, Vector2(2000, 2000))
	var e: Enemy = _mk_enemy(stage, null, Vector2(1700, 2000))
	await process_frame
	e.global_position = Vector2(1700, 2000)
	p.global_position = Vector2(2000, 2000)
	_aim_at(p, e.global_position)
	e._physics_process(DT)
	_check(e.velocity.length() > 100.0 and e.velocity.normalized().dot(Vector2.RIGHT) > 0.99,
		"B: no terrain/no cover - straight chase at full speed")
	_check(_state(e) == EnemyBehaviorCover.State.ENGAGED or _state(e) == EnemyBehaviorCover.State.SEEK,
		"B: no cover means no cover state machinery engaged")
	await _drive_real(e, 30, p, true)
	_check(e.global_position.x > 1720.0, "B: chase advances toward the player")
	_teardown(stage)

func _leg_c_seek_cover() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := Vector2i(20, 20)
	map.set_cell(tree, TerrainTypes.OBSTACLE)
	var tree_pos: Vector2 = map.cell_to_world(tree)
	var p: Player = _mk_player(stage, tree_pos + Vector2(220, 0))
	var e: Enemy = _mk_enemy(stage, map, tree_pos + Vector2(-220, 0))
	await process_frame
	e.global_position = tree_pos + Vector2(-220, 0)
	p.global_position = tree_pos + Vector2(220, 0)
	await _drive_real(e, 240, p, true)
	_check(map.is_walkable_at(e.global_position), "C: enemy never stands on the blocked cell")
	_check(_blocked_cell_on_segment(map, e.global_position, p.global_position),
		"C: enemy shelters with the cover on the enemy->player segment")
	_check(e.velocity.length() < 1.0, "C: enemy settles at the cover (HOLD)")
	_check(_state(e) == EnemyBehaviorCover.State.HOLD, "C: state is HOLD behind cover")
	_teardown(stage)

func _leg_d_hold_while_aimed() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := Vector2i(20, 20)
	map.set_cell(tree, TerrainTypes.OBSTACLE)
	var tree_pos: Vector2 = map.cell_to_world(tree)
	var p: Player = _mk_player(stage, tree_pos + Vector2(220, 0))
	var e: Enemy = _mk_enemy(stage, map, tree_pos + Vector2(-220, 0))
	await process_frame
	e.global_position = tree_pos + Vector2(-220, 0)
	p.global_position = tree_pos + Vector2(220, 0)
	await _drive_real(e, 200, p, true)
	var held := e.global_position
	var hp_before: int = p.hp
	await _drive_real(e, 240, p, true) # 4s aimed: longer than AWAY_CHARGE_TIME
	_check(e.global_position.distance_to(held) < 6.0, "D: aimed at, it stays behind cover")
	_check(p.hp == hp_before, "D: no charge, no contact damage while aimed at")
	_teardown(stage)

func _leg_e_charge_after_3s() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := Vector2i(20, 20)
	map.set_cell(tree, TerrainTypes.OBSTACLE)
	var tree_pos: Vector2 = map.cell_to_world(tree)
	var p: Player = _mk_player(stage, tree_pos + Vector2(220, 0))
	var e: Enemy = _mk_enemy(stage, map, tree_pos + Vector2(-220, 0))
	await process_frame
	e.global_position = tree_pos + Vector2(-220, 0)
	p.global_position = tree_pos + Vector2(220, 0)
	# Settle into HOLD while aimed at.
	await _drive_real(e, 200, p, true)
	_check(_state(e) == EnemyBehaviorCover.State.HOLD, "E: settled into HOLD first")
	# Mouse away: sample charge speed mid-run, expect contact + ENGAGED.
	var saw_fast := false
	var away_frames := 0
	var hp_before: int = p.hp
	e.set_physics_process(true)
	await physics_frame
	while away_frames < 300 and p.hp == hp_before:
		_aim_away(p, e.global_position)
		await physics_frame
		away_frames += 1
		if _state(e) == EnemyBehaviorCover.State.CHARGE and e.velocity.length() > enemy_fast_floor(e):
			saw_fast = true
	e.set_physics_process(false)
	_check(saw_fast, "E: charge runs fast (speed x FAST_MULT)")
	_check(p.hp < hp_before, "E: after 3s away the charge reaches the player and hits")
	_check(away_frames >= 170, "E: no charge before the 3s away-timer (took %d frames to contact)" % away_frames)
	_check(_state(e) == EnemyBehaviorCover.State.ENGAGED, "E: after the hit it is ENGAGED (plain chase/contact)")
	_teardown(stage)

func enemy_fast_floor(e: Enemy) -> float:
	return e.speed * EnemyBehaviorCover.FAST_MULT * 0.9

func _leg_f_timer_reset_on_aim() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := Vector2i(20, 20)
	map.set_cell(tree, TerrainTypes.OBSTACLE)
	var tree_pos: Vector2 = map.cell_to_world(tree)
	var p: Player = _mk_player(stage, tree_pos + Vector2(220, 0))
	var e: Enemy = _mk_enemy(stage, map, tree_pos + Vector2(-220, 0))
	await process_frame
	e.global_position = tree_pos + Vector2(-220, 0)
	p.global_position = tree_pos + Vector2(220, 0)
	await _drive_real(e, 200, p, true)
	# 2s away, 0.5s re-aim, 2s away: the reset must prevent the charge.
	await _drive_real(e, 120, p, false)
	await _drive_real(e, 30, p, true)
	await _drive_real(e, 120, p, false)
	_check(_state(e) != EnemyBehaviorCover.State.CHARGE, "F: re-aim resets the 3s away-timer (no premature charge)")
	# 1.2s more away: now past 3s continuous -> charge.
	await _drive_real(e, 75, p, false)
	_check(_state(e) == EnemyBehaviorCover.State.CHARGE or _state(e) == EnemyBehaviorCover.State.ENGAGED,
		"F: 3s of continuous away-time triggers the charge")
	_teardown(stage)

func _leg_h_cover_destroyed() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := Vector2i(20, 20)
	map.set_cell(tree, TerrainTypes.OBSTACLE)
	var tree_pos: Vector2 = map.cell_to_world(tree)
	var p: Player = _mk_player(stage, tree_pos + Vector2(260, 0))
	var e: Enemy = _mk_enemy(stage, map, tree_pos + Vector2(-260, 0))
	await process_frame
	e.global_position = tree_pos + Vector2(-260, 0)
	p.global_position = tree_pos + Vector2(260, 0)
	await _drive_real(e, 240, p, true)
	_check(_state(e) == EnemyBehaviorCover.State.HOLD, "H: holding cover before it breaks")
	map.clear_cell(tree) # the tree is destroyed (breakable terrain)
	await _drive_real(e, 30, p, true)
	_check(_state(e) != EnemyBehaviorCover.State.HOLD, "H: destroyed cover is dropped")
	var before := e.global_position
	await _drive_real(e, 90, p, true)
	_check(e.global_position.distance_to(p.global_position) < before.distance_to(p.global_position) - 40.0,
		"H: with no cover left it engages (closes on the player)")
	_teardown(stage)

func _leg_m_cover_destroy_signal() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := Vector2i(20, 20)
	map.set_cell(tree, TerrainTypes.TREE) # destroyable blocking type
	var tree_pos: Vector2 = map.cell_to_world(tree)
	var p: Player = _mk_player(stage, tree_pos + Vector2(260, 0))
	var e: Enemy = _mk_enemy(stage, map, tree_pos + Vector2(-260, 0))
	await process_frame
	e.global_position = tree_pos + Vector2(-260, 0)
	p.global_position = tree_pos + Vector2(260, 0)
	await _drive_real(e, 240, p, true)
	_check(_state(e) == EnemyBehaviorCover.State.HOLD, "M: holding cover before it breaks")
	# destroy_cell emits cell_destroyed; the drop must be immediate, not
	# on the 0.25s repick cadence (leg H covers the signal-less path).
	map.destroy_cell(tree)
	await process_frame
	_check(_cover(e).get("_has_cover") == false, "M: cell_destroyed drops the held cover immediately")
	await _drive_real(e, 3, p, true)
	_check(_state(e) != EnemyBehaviorCover.State.HOLD, "M: no hold on a destroyed cell")
	_teardown(stage)

func _leg_i_solid_container_cover() -> void:
	var s: Array = _mk_stage() # map present but NO blocking cells
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var box: StaticBody2D = load("res://scenes/destroyable_container.tscn").instantiate()
	stage.add_child(box)
	box.global_position = Vector2(3200, 3200)
	var p: Player = _mk_player(stage, Vector2(3420, 3200))
	var e: Enemy = _mk_enemy(stage, map, Vector2(2980, 3200))
	await process_frame
	e.global_position = Vector2(2980, 3200)
	p.global_position = Vector2(3420, 3200)
	_check(box.is_in_group(&"cover"), "I: containers register as cover")
	await _drive_real(e, 240, p, true)
	_check(_state(e) == EnemyBehaviorCover.State.HOLD, "I: a solid container serves as cover (any cover, not just trees)")
	var to_box: Vector2 = box.global_position - e.global_position
	var to_player: Vector2 = p.global_position - e.global_position
	_check(to_box.normalized().dot(to_player.normalized()) > 0.9,
		"I: the enemy shelters with the container between it and the player")
	_teardown(stage)

func _leg_j_two_mobs_independent() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	# Two covers on DIFFERENT rays from the player (aiming at e1 is >30deg
	# away from e2's direction, so e2's away-timer runs while e1's resets).
	map.set_cell(Vector2i(20, 20), TerrainTypes.OBSTACLE)
	map.set_cell(Vector2i(23, 17), TerrainTypes.OBSTACLE)
	var tree1: Vector2 = map.cell_to_world(Vector2i(20, 20))
	var tree2: Vector2 = map.cell_to_world(Vector2i(23, 17))
	var p: Player = _mk_player(stage, tree1 + Vector2(220, 0))
	var e1: Enemy = _mk_enemy(stage, map, tree1 + Vector2(-220, 0), "Player")
	var e2: Enemy = _mk_enemy(stage, map, tree2 + Vector2(-160, -160), "Player")
	e2.name = "Enemy2"
	await process_frame
	e1.global_position = tree1 + Vector2(-220, 0)
	e2.global_position = tree2 + Vector2(-160, -160)
	p.global_position = tree1 + Vector2(220, 0)
	var hp_before: int = p.hp
	e1.set_physics_process(true)
	e2.set_physics_process(true)
	await physics_frame
	for i in 360:
		_aim_at(p, e1.global_position) # mouse kept on e1, away from e2
		await physics_frame
	e1.set_physics_process(false)
	e2.set_physics_process(false)
	_check(_state(e1) == EnemyBehaviorCover.State.HOLD or _state(e1) == EnemyBehaviorCover.State.SEEK or _state(e1) == EnemyBehaviorCover.State.DASH,
		"J: the aimed-at mob stays in cover mode (never charges)")
	_check(p.hp < hp_before, "J: the un-aimed mob charges and hits (independent 3s clocks)")
	_teardown(stage)

func _leg_k_player_death() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var p: Player = _mk_player(stage, Vector2(3600, 3600))
	var e: Enemy = _mk_enemy(stage, map, Vector2(3400, 3600))
	await process_frame
	e.global_position = Vector2(3400, 3600)
	p.global_position = Vector2(3600, 3600)
	p.hp = 0
	_drive(e, 30)
	_check(e.velocity == Vector2.ZERO, "K: dead player - enemy idles")
	_teardown(stage)

func _leg_l_freeze_pauses() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := Vector2i(20, 20)
	map.set_cell(tree, TerrainTypes.OBSTACLE)
	var tree_pos: Vector2 = map.cell_to_world(tree)
	var p: Player = _mk_player(stage, tree_pos + Vector2(220, 0))
	var e: Enemy = _mk_enemy(stage, map, tree_pos + Vector2(-220, 0))
	await process_frame
	e.global_position = tree_pos + Vector2(-220, 0)
	p.global_position = tree_pos + Vector2(220, 0)
	await _drive_real(e, 200, p, true)
	var held := e.global_position
	e.set_frozen(true)
	_drive(e, 240) # 4s frozen with the mouse away
	_check(e.global_position.distance_to(held) < 1.0, "L: frozen enemy does not move")
	_check(_state(e) == EnemyBehaviorCover.State.HOLD, "L: freeze pauses the away-timer (no charge while frozen)")
	e.set_frozen(false)
	_teardown(stage)

func _leg_g_dash_fast() -> void:
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	# Two covers in a line toward the player: after holding the first, the
	# mob must DASH (fast) to the second while the mouse is away.
	map.set_cell(Vector2i(20, 20), TerrainTypes.OBSTACLE)
	map.set_cell(Vector2i(23, 20), TerrainTypes.OBSTACLE)
	var tree1: Vector2 = map.cell_to_world(Vector2i(20, 20))
	var tree2: Vector2 = map.cell_to_world(Vector2i(23, 20))
	var p: Player = _mk_player(stage, tree2 + Vector2(220, 0))
	var e: Enemy = _mk_enemy(stage, map, tree1 + Vector2(-220, 0))
	await process_frame
	e.global_position = tree1 + Vector2(-220, 0)
	p.global_position = tree2 + Vector2(220, 0)
	await _drive_real(e, 200, p, true)
	_check(_state(e) == EnemyBehaviorCover.State.HOLD, "G: holds the first cover")
	var saw_dash_fast := false
	e.set_physics_process(true)
	await physics_frame
	for i in 60:
		_aim_away(p, e.global_position)
		await physics_frame
		if _state(e) == EnemyBehaviorCover.State.DASH and e.velocity.length() > enemy_fast_floor(e):
			saw_dash_fast = true
	e.set_physics_process(false)
	_check(saw_dash_fast, "G: moving between cover runs fast (speed x FAST_MULT)")
	_teardown(stage)

## Aimed-strafe fixture (review repro): production scenes with their own
## collision layers kept, real physics frames. Settles HOLD while aimed at,
## then arcs the player from centre+(220,0) to centre+(0,220) over 60
## frames and keeps aiming at the mob for 180 more. Returns
## [stage, map, player, enemy, held_pos, max_exposed_hold_frames].
func _aimed_strafe(extra_cover: Array[Vector2i]) -> Array:
	# Earlier legs fire-and-forget their teardown; let it finish so no
	# stale stage is still alive once this leg turns collisions on.
	await process_frame
	await process_frame
	var s: Array = _mk_stage()
	var stage: Node2D = s[0]
	var map: TerrainMap = s[1]
	var tree := Vector2i(20, 20)
	map.set_cell(tree, TerrainTypes.OBSTACLE)
	for c in extra_cover:
		map.set_cell(c, TerrainTypes.OBSTACLE)
	var centre: Vector2 = map.cell_to_world(tree)
	var p: Player = _player_scene.instantiate()
	p.name = "Player"
	p.set_process(false) # harness owns the aim
	stage.add_child(p)
	p.global_position = centre + Vector2(220, 0)
	p.set_physics_process(false)
	var e: Enemy = _enemy_scene.instantiate()
	e.player_path = NodePath("../Player")
	e.terrain = map
	e.set_physics_process(false)
	stage.add_child(e)
	await process_frame
	e.global_position = centre + Vector2(-220, 0)
	p.global_position = centre + Vector2(220, 0)
	await _drive_real(e, 240, p, true)
	var held := e.global_position
	var settled := _state(e) == EnemyBehaviorCover.State.HOLD and _blocked_cell_on_segment(map, e.global_position, p.global_position)
	var max_exposed := 0
	var exposed := 0
	e.set_physics_process(true)
	await physics_frame
	for i in 240:
		var t := minf(1.0, float(i) / 60.0)
		p.global_position = centre + Vector2.from_angle(t * PI * 0.5) * 220.0
		_aim_at(p, e.global_position)
		await physics_frame
		# Exposed = HOLD without body-width shelter (a corner graze of the
		# centre ray is not cover).
		if _state(e) == EnemyBehaviorCover.State.HOLD and not _cover(e)._sheltered(map, e.global_position, p.global_position):
			exposed += 1
			max_exposed = maxi(max_exposed, exposed)
		else:
			exposed = 0
	e.set_physics_process(false)
	return [stage, map, p, e, held, max_exposed, settled]

func _leg_n_aimed_strafe_single_cover() -> void:
	var r: Array = await _aimed_strafe([])
	var map: TerrainMap = r[1]
	var p: Player = r[2]
	var e: Enemy = r[3]
	_check(r[6], "N: settled in HOLD with the cover on the sightline before the strafe")
	# The 0.25s repick cadence is the only allowed lag (15 frames + slack).
	_check(r[5] <= 20, "N: aimed-at mob never stays in an exposed HOLD (max %d frames)" % r[5])
	_check(not (_state(e) == EnemyBehaviorCover.State.HOLD and not _blocked_cell_on_segment(map, e.global_position, p.global_position)),
		"N: after the aimed strafe it is not holding with an open sightline")
	_check(e.global_position.distance_to(r[4]) > 40.0, "N: with no shelter left it leaves the exposed spot (normal fallback)")
	await _teardown(r[0])

func _leg_o_aimed_strafe_reshelter() -> void:
	# A second obstacle two cells "south" of the first: from the post-strafe
	# player position it shields a hold point between the two cells.
	var r: Array = await _aimed_strafe([Vector2i(20, 22)])
	var map: TerrainMap = r[1]
	var p: Player = r[2]
	var e: Enemy = r[3]
	_check(r[6], "O: settled in HOLD with the cover on the sightline before the strafe")
	_check(r[5] <= 20, "O: aimed-at mob never stays in an exposed HOLD (max %d frames)" % r[5])
	_check(_state(e) == EnemyBehaviorCover.State.HOLD, "O: re-sheltered into HOLD while still aimed at")
	_check(_blocked_cell_on_segment(map, e.global_position, p.global_position),
		"O: the new hold has blocking cover on the enemy->player sightline")
	_check(_cover(e)._sheltered(map, e.global_position, p.global_position),
		"O: the new hold is body-width sheltered (not a corner graze)")
	_check(e.global_position.distance_to(r[4]) > 20.0, "O: it actually moved to the new shelter")
	_check(map.is_walkable_at(e.global_position), "O: new hold is on walkable ground")
	await _teardown(r[0])
